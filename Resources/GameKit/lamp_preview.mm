// Lamp's game kit: the preview on the Mac. Lamp writes this file before every build.
//
// The same game drawn with Metal, two ways. For the agent, out of sight (no window, nothing asked of the person), at
// 1920x1080 and exactly 60 frames a second of game time, as fast as the Mac goes. A play is a script Lamp writes from
// what the agent asked for: hold the controller this way for so many frames, take a picture now. Every play starts
// from the beginning with the same random seed, so the same script plays the same way, and Lamp replays the whole of
// it after a change.
//
//   lamp_preview <script> <pictures folder> <assets folder> <saves folder>
//
// The script's lines:   hold <frames> <lx> <ly> <rx> <ry> <lt> <rt> <buttons>    and    shot <name>
//
// For the person, in a window they play with a controller connected to the Mac or the keyboard, until they close it:
//
//   lamp_preview --window <title> <assets folder> <saves folder>
#include "lamp_game.h"
#include "lamp_host.h"
#include "sokol_gfx.h"
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <ImageIO/ImageIO.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <mach/mach_time.h>

static std::string g_assets, g_saves;
static uint64_t g_frame;
static int g_lines;

extern "C" void lamp_log(const char* format, ...) {
    // The preview runs much faster than the console: a game that logs every frame would print thousands of lines.
    if (++g_lines > 400) { if (g_lines == 401) printf("[%.2f s] Lamp: the game logged more than 400 lines; the rest are left out.\n", g_frame / 60.0); return; }
    printf("[%.2f s] ", g_frame / 60.0);
    va_list args;
    va_start(args, format);
    vprintf(format, args);
    va_end(args);
    putchar('\n');
    fflush(stdout);
}

static bool relative(const char* path) {
    if (!path || !*path || path[0] == '/') return false;
    return ("/" + std::string(path) + "/").find("/../") == std::string::npos;
}

static LampFile read_whole(const std::string& path) {
    LampFile file = { nullptr, 0 };
    FILE* f = fopen(path.c_str(), "rb");
    if (!f) return file;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size >= 0 && (file.data = malloc((size_t)size + 1))) {
        if (fread(file.data, 1, (size_t)size, f) == (size_t)size) { ((char*)file.data)[size] = 0; file.size = (size_t)size; }
        else { free(file.data); file.data = nullptr; }
    }
    fclose(f);
    return file;
}

extern "C" LampFile lamp_asset(const char* path) {
    if (!relative(path)) { lamp_log("lamp_asset: \"%s\" isn't a path inside Assets/", path ? path : ""); return { nullptr, 0 }; }
    LampFile file = read_whole(g_assets + "/" + path);
    if (!file.data) lamp_log("lamp_asset: no Assets/%s", path);
    return file;
}

static bool save_name(const char* name) {
    if (!name || !*name || strstr(name, "..")) return false;
    for (const char* c = name; *c; c++) if (!isalnum((unsigned char)*c) && *c != '-' && *c != '_' && *c != '.') return false;
    return true;
}

extern "C" LampFile lamp_load(const char* name) {
    if (!save_name(name)) return { nullptr, 0 };
    return read_whole(g_saves + "/save-" + name);
}

extern "C" bool lamp_save(const char* name, const void* data, size_t size) {
    if (!save_name(name)) { lamp_log("lamp_save: \"%s\" isn't a name (letters, digits, - _ .)", name ? name : ""); return false; }
    std::string path = g_saves + "/save-" + name;
    FILE* f = fopen((path + ".new").c_str(), "wb");
    if (!f) return false;
    bool ok = fwrite(data, 1, size, f) == size;
    ok = fclose(f) == 0 && ok;
    return ok && rename((path + ".new").c_str(), path.c_str()) == 0;
}

extern "C" void lamp_rumble(int pad, float low, float high) {
    static float last[4][2];
    if (pad < 0 || pad > 3 || (last[pad][0] == low && last[pad][1] == high)) return;
    last[pad][0] = low; last[pad][1] = high;
    printf("[%.2f s] Lamp: controller %d rumbles %.2f %.2f\n", g_frame / 60.0, pad + 1, low, high);
}

// What the frames cost, from sokol's own count of draws and of the vertices they draw.
static uint64_t g_vertices, g_draws;
static void count_draw(int base, int elements, int instances, void*) { (void)base; g_draws++; g_vertices += (uint64_t)elements * (uint64_t)(instances > 0 ? instances : 1); }
static void count_draw_ex(int base, int elements, int instances, int base_vertex, int base_instance, void* user) { (void)base_vertex; (void)base_instance; count_draw(base, elements, instances, user); }

static bool save_png(id<MTLTexture> texture, id<MTLCommandQueue> queue, const std::string& path) {
    NSUInteger w = texture.width, h = texture.height, row = w * 4;
    id<MTLBuffer> buffer = [queue.device newBufferWithLength:row * h options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> commands = [queue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [commands blitCommandEncoder];
    [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(w, h, 1)
                 toBuffer:buffer destinationOffset:0 destinationBytesPerRow:row destinationBytesPerImage:row * h];
    [blit endEncoding];
    [commands commit];
    [commands waitUntilCompleted];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(buffer.contents, w, h, 8, row, space,
                                                 kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGImageRef image = context ? CGBitmapContextCreateImage(context) : nullptr;
    bool ok = false;
    if (image) {
        NSURL* url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path.c_str()]];
        CGImageDestinationRef out = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, (__bridge CFStringRef)UTTypePNG.identifier, 1, nullptr);
        if (out) { CGImageDestinationAddImage(out, image, nullptr); ok = CGImageDestinationFinalize(out); CFRelease(out); }
        CGImageRelease(image);
    }
    if (context) CGContextRelease(context);
    CGColorSpaceRelease(space);
    return ok;
}

// MARK: The window the person plays in

// What the keyboard holds now, by key code: the keys stand in for a controller when none is connected.
static bool g_keys[256];

static LampPad keyboard_pad() {
    auto down = [](unsigned short code) { return code < 256 && g_keys[code]; };
    // Key codes of the US layout's places, so WASD is where it is whatever the layout's letters.
    enum { A = 0, S = 1, D = 2, F = 3, Q = 12, W = 13, E = 14, R = 15, Z = 6, C = 8, I = 34, J = 38, K = 40, L = 37, P = 35,
           Tab = 48, Space = 49, Return = 36, Escape = 53, Delete = 51, Left = 123, Right = 124, Down = 125, Up = 126 };
    LampPad pad = {};
    pad.connected = true;
    pad.lx = (down(D) || down(Right) ? 1.f : 0.f) - (down(A) || down(Left) ? 1.f : 0.f);
    pad.ly = (down(W) || down(Up) ? 1.f : 0.f) - (down(S) || down(Down) ? 1.f : 0.f);
    pad.rx = (down(L) ? 1.f : 0.f) - (down(J) ? 1.f : 0.f);
    pad.ry = (down(I) ? 1.f : 0.f) - (down(K) ? 1.f : 0.f);
    pad.lt = down(Z) ? 1.f : 0.f;
    pad.rt = down(C) ? 1.f : 0.f;
    const struct { unsigned short key; uint32_t bit; } map[] = {
        { Space, LAMP_A }, { Return, LAMP_A }, { Escape, LAMP_B }, { Delete, LAMP_B }, { F, LAMP_X }, { R, LAMP_Y },
        { Q, LAMP_LB }, { E, LAMP_RB }, { P, LAMP_MENU }, { Tab, LAMP_VIEW },
        { Up, LAMP_UP }, { Down, LAMP_DOWN }, { Left, LAMP_LEFT }, { Right, LAMP_RIGHT } };
    for (auto& m : map) if (down(m.key)) pad.down |= m.bit;
    return pad;
}

static LampPad controller_pad(GCExtendedGamepad* g) {
    LampPad pad = {};
    pad.connected = true;
    pad.lx = lamp_host_dead_zone(g.leftThumbstick.xAxis.value); pad.ly = lamp_host_dead_zone(g.leftThumbstick.yAxis.value);
    pad.rx = lamp_host_dead_zone(g.rightThumbstick.xAxis.value); pad.ry = lamp_host_dead_zone(g.rightThumbstick.yAxis.value);
    pad.lt = g.leftTrigger.value; pad.rt = g.rightTrigger.value;
    const struct { GCControllerButtonInput* button; uint32_t bit; } map[] = {
        { g.buttonA, LAMP_A }, { g.buttonB, LAMP_B }, { g.buttonX, LAMP_X }, { g.buttonY, LAMP_Y },
        { g.leftShoulder, LAMP_LB }, { g.rightShoulder, LAMP_RB }, { g.buttonMenu, LAMP_MENU }, { g.buttonOptions, LAMP_VIEW },
        { g.dpad.up, LAMP_UP }, { g.dpad.down, LAMP_DOWN }, { g.dpad.left, LAMP_LEFT }, { g.dpad.right, LAMP_RIGHT },
        { g.leftThumbstickButton, LAMP_LSTICK }, { g.rightThumbstickButton, LAMP_RSTICK } };
    for (auto& m : map) if (m.button.pressed) pad.down |= m.bit;
    return pad;
}

@interface LampPlayView : NSView
@end

@implementation LampPlayView
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }
- (CALayer*)makeBackingLayer { return [CAMetalLayer layer]; }
- (void)keyDown:(NSEvent*)event { if (event.keyCode < 256) g_keys[event.keyCode] = true; }
- (void)keyUp:(NSEvent*)event { if (event.keyCode < 256) g_keys[event.keyCode] = false; }
- (void)flagsChanged:(NSEvent*)event { (void)event; }
@end

@interface LampPlayer : NSObject <NSWindowDelegate, NSApplicationDelegate>
@property (strong) NSWindow* window;
@property (strong) CAMetalLayer* layer;
@property (strong) id<MTLTexture> depth;
@property (strong) NSTimer* timer;
@end

@implementation LampPlayer {
    LampFrame _frame;
    uint32_t _before[4];
    int _seen;
}

- (void)start:(NSString*)title {
    const int W = 1920, H = 1080;
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) { printf("Lamp: this Mac has no Metal device for the preview.\n"); exit(3); }
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 960, 540)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                backing:NSBackingStoreBuffered defer:NO];
    self.window.title = title;
    self.window.contentAspectRatio = NSMakeSize(16, 9);
    self.window.contentMinSize = NSMakeSize(480, 270);
    self.window.delegate = self;
    self.window.releasedWhenClosed = NO;
    LampPlayView* view = [[LampPlayView alloc] initWithFrame:NSMakeRect(0, 0, 960, 540)];
    view.wantsLayer = YES;
    self.window.contentView = view;
    self.layer = (CAMetalLayer*)view.layer;
    self.layer.device = device;
    self.layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    // Always the console's size, scaled to the window: the game is laid out for 1920x1080 whatever the window is.
    self.layer.drawableSize = CGSizeMake(W, H);
    self.layer.contentsGravity = kCAGravityResizeAspect;
    MTLTextureDescriptor* dd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float_Stencil8 width:W height:H mipmapped:NO];
    dd.usage = MTLTextureUsageRenderTarget;
    dd.storageMode = MTLStorageModePrivate;
    self.depth = [device newTextureWithDescriptor:dd];

    sg_desc desc = {};
    desc.environment.defaults.color_format = SG_PIXELFORMAT_BGRA8;
    desc.environment.defaults.depth_format = SG_PIXELFORMAT_DEPTH_STENCIL;
    desc.environment.defaults.sample_count = 1;
    desc.environment.metal.device = (__bridge const void*)device;
    desc.logger.func = lamp_host_sokol_log;
    sg_setup(&desc);
    lamp_host_seed(mach_absolute_time());
    LampSetup setup = { W, H, SG_PIXELFORMAT_BGRA8, SG_PIXELFORMAT_DEPTH_STENCIL, 1 };
    game_init(&setup);
    _frame = {};
    _frame.width = W; _frame.height = H;
    _frame.dt = 1.0 / 60.0;
    _seen = -1;
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:view];
    [NSApp activateIgnoringOtherApps:YES];
    self.timer = [NSTimer timerWithTimeInterval:1.0 / 60.0 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)tick {
    @autoreleasepool {
        // Each controller connected to the Mac is a pad; with none, the keyboard is the first.
        NSArray<GCController*>* controllers = [GCController controllers];
        int connected = 0;
        for (int i = 0; i < 4; i++) {
            LampPad pad = {};
            GCExtendedGamepad* gamepad = nil;
            for (GCController* c in controllers) if (c.extendedGamepad && (int)c.playerIndex == i) gamepad = c.extendedGamepad;
            if (!gamepad) {
                int n = 0;
                for (GCController* c in controllers) if (c.extendedGamepad && c.playerIndex == GCControllerPlayerIndexUnset && n++ == i) gamepad = c.extendedGamepad;
            }
            if (gamepad) { pad = controller_pad(gamepad); connected++; }
            // The keyboard always plays as the first controller, beside a real one.
            if (i == 0 && self.window.isKeyWindow) {
                LampPad keys = keyboard_pad();
                if (!gamepad) pad = keys;
                else {
                    pad.down |= keys.down;
                    if (keys.lx) pad.lx = keys.lx; if (keys.ly) pad.ly = keys.ly;
                    if (keys.rx) pad.rx = keys.rx; if (keys.ry) pad.ry = keys.ry;
                    if (keys.lt) pad.lt = keys.lt; if (keys.rt) pad.rt = keys.rt;
                }
            } else if (i == 0 && !gamepad) {
                pad.connected = true;
            }
            lamp_host_edges(&pad, _before[i]);
            _before[i] = pad.down;
            _frame.pads[i] = pad;
        }
        if (connected != _seen) { lamp_log("Lamp: %d controller%s connected to this Mac.", connected, connected == 1 ? "" : "s"); _seen = connected; }
        id<CAMetalDrawable> drawable = [self.layer nextDrawable];
        if (!drawable) return;
        _frame.time = g_frame / 60.0;
        _frame.number = g_frame;
        _frame.swapchain = {};
        _frame.swapchain.width = 1920; _frame.swapchain.height = 1080; _frame.swapchain.sample_count = 1;
        _frame.swapchain.color_format = SG_PIXELFORMAT_BGRA8; _frame.swapchain.depth_format = SG_PIXELFORMAT_DEPTH_STENCIL;
        _frame.swapchain.metal.current_drawable = (__bridge const void*)drawable;
        _frame.swapchain.metal.depth_stencil_texture = (__bridge const void*)self.depth;
        game_frame(&_frame);
        g_frame++;
    }
}

- (void)windowDidResignKey:(NSNotification*)note { (void)note; memset(g_keys, 0, sizeof g_keys); }
- (void)windowWillClose:(NSNotification*)note { (void)note; [self.timer invalidate]; sg_shutdown(); exit(0); }
@end

static int play_in_window(const char* title) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        // A menu with Quit, so ⌘Q and ⌘W close the game as they close any window.
        NSMenu* bar = [NSMenu new];
        NSMenuItem* item = [NSMenuItem new];
        [bar addItem:item];
        NSMenu* menu = [NSMenu new];
        [menu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
        [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
        item.submenu = menu;
        NSApp.mainMenu = bar;
        LampPlayer* player = [LampPlayer new];
        NSApp.delegate = player;
        [player start:[NSString stringWithUTF8String:title]];
        [NSApp run];
    }
    return 0;
}

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc == 5 && strcmp(argv[1], "--window") == 0) {
            g_assets = argv[3];
            g_saves = argv[4];
            return play_in_window(argv[2]);
        }
        if (argc < 5) { fprintf(stderr, "usage: lamp_preview <script> <pictures> <assets> <saves>\n"); return 2; }
        FILE* script = fopen(argv[1], "r");
        if (!script) { fprintf(stderr, "Lamp: no script at %s\n", argv[1]); return 2; }
        std::string pictures = argv[2];
        g_assets = argv[3];
        g_saves = argv[4];
        const int W = 1920, H = 1080;
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) { printf("Lamp: this Mac has no Metal device for the preview.\n"); return 3; }
        sg_desc desc = {};
        desc.environment.defaults.color_format = SG_PIXELFORMAT_BGRA8;
        desc.environment.defaults.depth_format = SG_PIXELFORMAT_DEPTH_STENCIL;
        desc.environment.defaults.sample_count = 1;
        desc.environment.metal.device = (__bridge const void*)device;
        desc.logger.func = lamp_host_sokol_log;
        sg_setup(&desc);
        sg_trace_hooks hooks = {};
        hooks.draw = count_draw;
        hooks.draw_ex = count_draw_ex;
        sg_install_trace_hooks(&hooks);
        CAMetalLayer* layer = [CAMetalLayer layer];
        layer.device = device;
        layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        layer.framebufferOnly = NO;
        layer.drawableSize = CGSizeMake(W, H);
        MTLTextureDescriptor* dd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float_Stencil8 width:W height:H mipmapped:NO];
        dd.usage = MTLTextureUsageRenderTarget;
        dd.storageMode = MTLStorageModePrivate;
        id<MTLTexture> depth = [device newTextureWithDescriptor:dd];
        id<MTLCommandQueue> queue = (__bridge id<MTLCommandQueue>)sg_mtl_command_queue();

        lamp_host_seed(1);
        LampSetup setup = { W, H, SG_PIXELFORMAT_BGRA8, SG_PIXELFORMAT_DEPTH_STENCIL, 1 };
        uint64_t started = mach_absolute_time();
        game_init(&setup);
        LampFrame frame = {};
        frame.width = W; frame.height = H;
        frame.dt = 1.0 / 60.0;
        frame.pads[0].connected = true;
        uint32_t before = 0;
        id<CAMetalDrawable> last = nil;
        uint64_t most_draws = 0, most_vertices = 0, total_vertices = 0;
        char line[512];
        // Ten minutes of game time at most: a longer play is a mistake in the script, not a wish to wait.
        const uint64_t limit = 60 * 600;
        while (fgets(line, sizeof line, script) && g_frame < limit) {
            char word[32] = {};
            if (sscanf(line, "%31s", word) != 1) continue;
            if (strcmp(word, "shot") == 0) {
                char name[128] = {};
                if (sscanf(line, "shot %127s", name) == 1 && last) {
                    if (!save_png(last.texture, queue, pictures + "/" + name + ".png")) printf("Lamp: the picture %s couldn't be saved.\n", name);
                }
                continue;
            }
            if (strcmp(word, "hold") != 0) continue;
            long frames = 0;
            LampPad pad = {};
            unsigned buttons = 0;
            if (sscanf(line, "hold %ld %f %f %f %f %f %f %u", &frames, &pad.lx, &pad.ly, &pad.rx, &pad.ry, &pad.lt, &pad.rt, &buttons) != 8) continue;
            pad.connected = true;
            pad.down = buttons;
            for (long i = 0; i < frames && g_frame < limit; i++) {
                @autoreleasepool {
                    frame.pads[0] = pad;
                    lamp_host_edges(&frame.pads[0], before);
                    before = pad.down;
                    frame.time = g_frame / 60.0;
                    frame.number = g_frame;
                    id<CAMetalDrawable> drawable = [layer nextDrawable];
                    frame.swapchain = {};
                    frame.swapchain.width = W; frame.swapchain.height = H; frame.swapchain.sample_count = 1;
                    frame.swapchain.color_format = SG_PIXELFORMAT_BGRA8; frame.swapchain.depth_format = SG_PIXELFORMAT_DEPTH_STENCIL;
                    frame.swapchain.metal.current_drawable = (__bridge const void*)drawable;
                    frame.swapchain.metal.depth_stencil_texture = (__bridge const void*)depth;
                    g_draws = 0; g_vertices = 0;
                    game_frame(&frame);
                    if (g_draws > most_draws) most_draws = g_draws;
                    if (g_vertices > most_vertices) most_vertices = g_vertices;
                    total_vertices += g_vertices;
                    last = drawable;
                    g_frame++;
                }
            }
        }
        fclose(script);
        if (g_frame >= limit) printf("Lamp: the play was cut at ten minutes of game time.\n");
        // The last frame's commands are finished before anything reads it.
        id<MTLCommandBuffer> fence = [queue commandBuffer];
        [fence commit];
        [fence waitUntilCompleted];
        mach_timebase_info_data_t base;
        mach_timebase_info(&base);
        double seconds = double(mach_absolute_time() - started) * base.numer / base.denom / 1e9;
        printf("Lamp stats: %llu frames (%.1f s of play) in %.1f s on this Mac; at most %llu draws and %llu vertices in a frame, %llu vertices a frame on average.\n",
               (unsigned long long)g_frame, g_frame / 60.0, seconds, (unsigned long long)most_draws, (unsigned long long)most_vertices,
               (unsigned long long)(g_frame ? total_vertices / g_frame : 0));
        sg_shutdown();
    }
    return 0;
}
