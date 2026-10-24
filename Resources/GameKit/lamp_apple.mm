// Lamp's game kit: the host on the Mac, the iPhone and the iPad. Lamp writes this file before every build.
//
// The game drawn with Metal into the layer of the app's window (Lamp's Swift around it, Sources/LampGame.swift, makes
// the window, its menus and Lamp's chat beside it, and calls in here each frame), always at the console's 1920x1080
// scaled to the window, so the game is laid out once for every place. The controllers connected to the device are its
// pads (GameController); on a Mac the keyboard plays as the first one, and on an iPhone or iPad with no controller
// connected the touch controls Lamp draws over the game do (`lamp_touch_buttons` says which buttons they show). The
// kit's sound mix plays on the device's speakers through AVAudioEngine, as XAudio2 plays it on the console. Assets are
// read from the app's bundle (Assets/), saves kept in the folder Lamp's Swift names.
#include "lamp_game.h"
#include "lamp_host.h"
#include "sokol_gfx.h"
#import <AVFoundation/AVFoundation.h>
#include <TargetConditionals.h>
#if TARGET_OS_IOS
// The controllers' rumble. macOS's SDK can't compile CoreHaptics' header beside AVFoundation's (it names
// AVAudioSession, which the Mac hasn't), so on the Mac a controller doesn't rumble.
#import <CoreHaptics/CoreHaptics.h>
#endif
#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <TargetConditionals.h>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <mach/mach_time.h>

static std::string g_assets, g_saves;
static uint64_t g_frame;
static double g_time;
static int g_lines;

extern "C" void lamp_log(const char* format, ...) {
    // A game that logs every frame would fill the log in a minute.
    if (++g_lines > 2000) { if (g_lines == 2001) fprintf(stderr, "[%.2f s] Lamp: the game logged more than 2000 lines; the rest are left out.\n", g_time); return; }
    fprintf(stderr, "[%.2f s] ", g_time);
    va_list args;
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
    fputc('\n', stderr);
    fflush(stderr);
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

// The controllers by pad, as the last frame found them, for their rumble.
static GCController* g_pads[4];
static float g_rumbling[4][2];

extern "C" void lamp_rumble(int pad, float low, float high) {
    if (pad < 0 || pad > 3) return;
    g_rumbling[pad][0] = low < 0 ? 0 : low > 1 ? 1 : low;
    g_rumbling[pad][1] = high < 0 ? 0 : high > 1 ? 1 : high;
}

// A controller's two motors, as the console has them: a low one for the left handle, a high one for the right. One
// engine a pad, made when it first rumbles, and a player for each motor that's restarted with the new strength.
#if TARGET_OS_IOS
struct Rumble {
    CHHapticEngine* engine = nil;
    id<CHHapticPatternPlayer> players[2] = { nil, nil };
    float playing[2] = { 0, 0 };
    GCController* controller = nil;
};
static Rumble g_rumble[4];

static void rumble_pad(int index, GCController* controller) {
    Rumble& r = g_rumble[index];
    if (r.controller != controller) { [r.engine stopWithCompletionHandler:nil]; r = Rumble(); r.controller = controller; }
    if (!controller || !controller.haptics) return;
    for (int motor = 0; motor < 2; motor++) {
        float want = g_rumbling[index][motor];
        if (want == r.playing[motor]) continue;
        r.playing[motor] = want;
        if (!r.engine) {
            r.engine = [controller.haptics createEngineWithLocality:GCHapticsLocalityDefault];
            [r.engine startAndReturnError:nil];
        }
        [r.players[motor] stopAtTime:0 error:nil];
        r.players[motor] = nil;
        if (want <= 0 || !r.engine) continue;
        NSArray* parameters = @[[[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity value:want],
                                [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness value:motor == 0 ? 0.2f : 0.8f]];
        CHHapticEvent* event = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous parameters:parameters
                                                           relativeTime:0 duration:30];
        CHHapticPattern* pattern = [[CHHapticPattern alloc] initWithEvents:@[event] parameters:@[] error:nil];
        if (pattern) { r.players[motor] = [r.engine createPlayerWithPattern:pattern error:nil]; [r.players[motor] startAtTime:0 error:nil]; }
    }
}
#else
static void rumble_pad(int, GCController*) {}
#endif

// MARK: Input

// What the keyboard holds now, by key code: on a Mac the keys stand in for the first controller.
static bool g_keys[256];
static LampPad g_touch;
static LampPad keyboard_pad() {
    auto down = [](unsigned short code) { return code < 256 && g_keys[code]; };
    // Key codes of the US layout's places, so WASD is where it is whatever the layout's letters.
    enum { A = 0, S = 1, D = 2, F = 3, Q = 12, W = 13, E = 14, R = 15, Z = 6, C = 8, I = 34, J = 38, K = 40, L = 37, P = 35,
           Tab = 48, Space = 49, Return = 36, Escape = 53, Delete = 51, Left = 123, Right = 124, Down = 125, Up = 126 };
    LampPad pad = {};
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

// Adds what the keyboard or the touch controls hold to a pad: whichever moves a stick or a trigger further wins.
static void merge(LampPad& pad, const LampPad& more) {
    pad.down |= more.down;
    auto further = [](float a, float b) { return fabsf(b) > fabsf(a) ? b : a; };
    pad.lx = further(pad.lx, more.lx); pad.ly = further(pad.ly, more.ly);
    pad.rx = further(pad.rx, more.rx); pad.ry = further(pad.ry, more.ry);
    pad.lt = further(pad.lt, more.lt); pad.rt = further(pad.rt, more.rt);
}

// MARK: Sound

// The kit's mix on the speakers, pulled by the audio engine as it needs it, so it keeps playing through a slow frame of
// the game's. The kit mixes interleaved stereo at 48 kHz; the engine wants each channel apart.
static AVAudioEngine* start_speaker() {
#if TARGET_OS_IOS
    // Played as a game's sound is: under the ring switch, beside the person's own music if it's playing.
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
#endif
    AVAudioEngine* engine = [AVAudioEngine new];
    AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:2];
    AVAudioSourceNode* source = [[AVAudioSourceNode alloc] initWithFormat:format renderBlock:
        ^OSStatus(BOOL* silent, const AudioTimeStamp* when, AVAudioFrameCount frames, AudioBufferList* out) {
            (void)silent; (void)when;
            static float mix[2 * 512];
            float* left = (float*)out->mBuffers[0].mData;
            float* right = out->mNumberBuffers > 1 ? (float*)out->mBuffers[1].mData : left;
            for (AVAudioFrameCount done = 0; done < frames;) {
                int n = (int)MIN(frames - done, 512u);
                lamp_host_mix(mix, n);
                for (int i = 0; i < n; i++) { left[done + i] = mix[2 * i]; right[done + i] = mix[2 * i + 1]; }
                done += n;
            }
            return noErr;
        }];
    [engine attachNode:source];
    [engine connect:source to:engine.mainMixerNode format:format];
    NSError* error = nil;
    if (![engine startAndReturnError:&error]) {
        lamp_log("Lamp: the sound couldn't start (%s); the game plays without it.", error.localizedDescription.UTF8String);
        return nil;
    }
    return engine;
}

// MARK: The frame

static const int W = 1920, H = 1080;
static CAMetalLayer* g_layer;
static id<MTLTexture> g_depth;
static AVAudioEngine* g_speaker;
static uint32_t g_before[4];
static int g_seen = -1;
static bool g_started;
// How the frames keep to time, said every ten seconds like the console's host does.
static double g_window_time, g_slowest;
static int g_window_frames, g_late;

extern "C" void lamp_apple_start(void* layer, const char* assets, const char* saves) {
    if (g_started) return;
    g_started = true;
    g_assets = assets ? assets : "";
    g_saves = saves ? saves : "";
    g_layer = (__bridge CAMetalLayer*)layer;
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) { lamp_log("Lamp: this device has no Metal device to draw the game with."); exit(3); }
    g_layer.device = device;
    g_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    // Always the console's size, scaled to the window: the game is laid out for 1920x1080 wherever it plays.
    g_layer.drawableSize = CGSizeMake(W, H);
    g_layer.contentsGravity = kCAGravityResizeAspect;
    g_layer.framebufferOnly = NO;
    MTLTextureDescriptor* dd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float_Stencil8 width:W height:H mipmapped:NO];
    dd.usage = MTLTextureUsageRenderTarget;
    dd.storageMode = MTLStorageModePrivate;
    g_depth = [device newTextureWithDescriptor:dd];
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
    g_speaker = start_speaker();
}

extern "C" void lamp_apple_key(unsigned short code, bool down) { if (code < 256) g_keys[code] = down; }
extern "C" void lamp_apple_keys_up(void) { memset(g_keys, 0, sizeof g_keys); }
extern "C" void lamp_apple_touch(float lx, float ly, float rx, float ry, uint32_t down) {
    g_touch = LampPad{};
    g_touch.lx = lx; g_touch.ly = ly; g_touch.rx = rx; g_touch.ry = ry; g_touch.down = down;
}
extern "C" uint32_t lamp_apple_touch_buttons(void) { return lamp_host_touch_buttons; }

// How many controllers are connected now, for the touch controls to step aside.
extern "C" int lamp_apple_controllers(void) {
    int n = 0;
    for (GCController* c in [GCController controllers]) if (c.extendedGamepad) n++;
    return n;
}

// One frame: `dt` is the time since the last, as the display gave it, held to a twentieth of a second so a stall
// doesn't throw things across the screen; `keys` whether the keyboard is the game's now (its window has it).
extern "C" void lamp_apple_frame(double dt, bool keys) {
    if (!g_started) return;
    @autoreleasepool {
        if (dt <= 0 || dt > 0.05) dt = dt <= 0 ? 1.0 / 60.0 : 0.05;
        // Each controller connected is a pad, by the player number it was given, else in the order they came.
        NSArray<GCController*>* controllers = [GCController controllers];
        int connected = 0;
        LampFrame frame = {};
        for (int i = 0; i < 4; i++) {
            GCController* found = nil;
            for (GCController* c in controllers) if (c.extendedGamepad && (int)c.playerIndex == i) found = c;
            if (!found) {
                int n = 0;
                for (GCController* c in controllers) if (c.extendedGamepad && c.playerIndex == GCControllerPlayerIndexUnset && n++ == i) found = c;
            }
            LampPad pad = found ? controller_pad(found.extendedGamepad) : LampPad{};
            if (found) connected++;
            g_pads[i] = found;
            if (i == 0) {
                // The keyboard and the touch controls always play as the first controller, beside a real one.
                if (keys) merge(pad, keyboard_pad());
                merge(pad, g_touch);
                pad.connected = true;
            }
            lamp_host_edges(&pad, g_before[i]);
            g_before[i] = pad.down;
            frame.pads[i] = pad;
            rumble_pad(i, found);
        }
        if (connected != g_seen) { lamp_log("Lamp: %d controller%s connected.", connected, connected == 1 ? "" : "s"); g_seen = connected; }
        id<CAMetalDrawable> drawable = [g_layer nextDrawable];
        if (!drawable) return;
        g_time += dt;
        frame.dt = dt;
        frame.time = g_time;
        frame.number = g_frame;
        frame.width = W; frame.height = H;
        frame.swapchain.width = W; frame.swapchain.height = H; frame.swapchain.sample_count = 1;
        frame.swapchain.color_format = SG_PIXELFORMAT_BGRA8; frame.swapchain.depth_format = SG_PIXELFORMAT_DEPTH_STENCIL;
        frame.swapchain.metal.current_drawable = (__bridge const void*)drawable;
        frame.swapchain.metal.depth_stencil_texture = (__bridge const void*)g_depth;
        game_frame(&frame);
        g_frame++;
        g_window_time += dt; g_window_frames++;
        if (dt > g_slowest) g_slowest = dt;
        if (dt > 1.5 / 60.0) g_late++;
        if (g_window_time >= 10) {
            lamp_log("Lamp: frames %.1f ms on average, slowest %.1f ms, %d of %d late.", g_window_time * 1000 / g_window_frames, g_slowest * 1000, g_late, g_window_frames);
            g_window_time = 0; g_window_frames = 0; g_slowest = 0; g_late = 0;
        }
    }
}
