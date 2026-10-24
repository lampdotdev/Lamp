// Lamp's game kit: the host on Android. Lamp writes this file before every build.
//
// The game drawn with sokol_gfx on OpenGL ES 3 into the surface of Lamp's Android app (a SurfaceView, the Kotlin in
// Lamp/Android, which calls in here through `dev.lamp.game.Native`), always at 1920x1080 (the surface's buffers are
// that size, and Android scales them to the view), on a thread of its own that presents with vsync. The app hands it
// the first controller and the touch controls it draws, and the other controllers by player; the kit's sound mix plays
// through AAudio, as XAudio2 plays it on the console. Assets are read from the app's package (assets/Assets), saves
// kept in the app's own folder.
#include <jni.h>
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <aaudio/AAudio.h>
#include <android/asset_manager.h>
#include <android/asset_manager_jni.h>
#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <atomic>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <time.h>
#include "lamp_game.h"
#include "lamp_host.h"
#include "sokol_gfx.h"

static AAssetManager* g_assets;
static std::string g_saves;
static double g_time;
static int g_lines;

extern "C" void lamp_log(const char* format, ...) {
    if (++g_lines > 2000) { if (g_lines == 2001) __android_log_print(ANDROID_LOG_INFO, "Lamp", "[%.2f s] Lamp: the game logged more than 2000 lines; the rest are left out.", g_time); return; }
    char line[2048];
    va_list args;
    va_start(args, format);
    vsnprintf(line, sizeof line, format, args);
    va_end(args);
    __android_log_print(ANDROID_LOG_INFO, "Lamp", "[%.2f s] %s", g_time, line);
}

static bool relative(const char* path) {
    if (!path || !*path || path[0] == '/') return false;
    return ("/" + std::string(path) + "/").find("/../") == std::string::npos;
}

extern "C" LampFile lamp_asset(const char* path) {
    LampFile file = { nullptr, 0 };
    if (!relative(path)) { lamp_log("lamp_asset: \"%s\" isn't a path inside Assets/", path ? path : ""); return file; }
    AAsset* asset = g_assets ? AAssetManager_open(g_assets, ("Assets/" + std::string(path)).c_str(), AASSET_MODE_BUFFER) : nullptr;
    if (!asset) { lamp_log("lamp_asset: no Assets/%s", path); return file; }
    off_t size = AAsset_getLength(asset);
    if ((file.data = malloc((size_t)size + 1))) {
        if (AAsset_read(asset, file.data, (size_t)size) == size) { ((char*)file.data)[size] = 0; file.size = (size_t)size; }
        else { free(file.data); file.data = nullptr; }
    }
    AAsset_close(asset);
    return file;
}

static bool save_name(const char* name) {
    if (!name || !*name || strstr(name, "..")) return false;
    for (const char* c = name; *c; c++) if (!isalnum((unsigned char)*c) && *c != '-' && *c != '_' && *c != '.') return false;
    return true;
}

extern "C" LampFile lamp_load(const char* name) {
    LampFile file = { nullptr, 0 };
    if (!save_name(name)) return file;
    FILE* f = fopen((g_saves + "/save-" + name).c_str(), "rb");
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

extern "C" bool lamp_save(const char* name, const void* data, size_t size) {
    if (!save_name(name)) { lamp_log("lamp_save: \"%s\" isn't a name (letters, digits, - _ .)", name ? name : ""); return false; }
    std::string path = g_saves + "/save-" + name;
    FILE* f = fopen((path + ".new").c_str(), "wb");
    if (!f) return false;
    bool ok = fwrite(data, 1, size, f) == size;
    ok = fclose(f) == 0 && ok;
    return ok && rename((path + ".new").c_str(), path.c_str()) == 0;
}

// The controllers' rumble goes to the app, which shakes the controller (`Native.rumble`, read on its next frame).
static std::atomic<uint32_t> g_rumble[4];
extern "C" void lamp_rumble(int pad, float low, float high) {
    if (pad < 0 || pad > 3) return;
    auto clamp = [](float v) { return (uint32_t)(v < 0 ? 0 : v > 1 ? 255 : v * 255); };
    g_rumble[pad] = clamp(low) << 8 | clamp(high);
}

// MARK: Input, as the app hands it over: four pads, the first with the touch controls merged in

struct Pads {
    LampPad pads[4];
    uint32_t tapped;   // a touch press shorter than a frame, held for the next frame
};
static std::mutex g_input;
static Pads g_given;

// MARK: Sound

static AAudioStream* g_stream;

static aaudio_data_callback_result_t mix(AAudioStream*, void*, void* data, int32_t frames) {
    lamp_host_mix((float*)data, frames);
    return AAUDIO_CALLBACK_RESULT_CONTINUE;
}

static void start_speaker() {
    AAudioStreamBuilder* builder = nullptr;
    if (AAudio_createStreamBuilder(&builder) != AAUDIO_OK) { lamp_log("Lamp: the sound couldn't start; the game plays without it."); return; }
    AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_FLOAT);
    AAudioStreamBuilder_setChannelCount(builder, 2);
    AAudioStreamBuilder_setSampleRate(builder, 48000);
    AAudioStreamBuilder_setPerformanceMode(builder, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    AAudioStreamBuilder_setDataCallback(builder, mix, nullptr);
    if (AAudioStreamBuilder_openStream(builder, &g_stream) != AAUDIO_OK || AAudioStream_requestStart(g_stream) != AAUDIO_OK) {
        lamp_log("Lamp: the sound couldn't start; the game plays without it.");
        g_stream = nullptr;
    }
    AAudioStreamBuilder_delete(builder);
}

// MARK: The frame, on a thread of its own

static const int W = 1920, H = 1080;
static std::mutex g_surface;
static ANativeWindow* g_window;          // the surface the app gave last, or none while it's in the background
static std::atomic<bool> g_changed;      // a new surface to draw into
static ANativeWindow* g_drawing;         // the one the frames go into, the render thread's own
static std::atomic<bool> g_running;
static std::thread g_thread;

static double now() {
    timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

static void run() {
    EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    eglInitialize(display, nullptr, nullptr);
    const EGLint attributes[] = { EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8,
                                  EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_DEPTH_SIZE, 24, EGL_STENCIL_SIZE, 8, EGL_NONE };
    EGLConfig config;
    EGLint count = 0;
    if (!eglChooseConfig(display, attributes, &config, 1, &count) || count == 0) { lamp_log("Lamp: this device can't draw with OpenGL ES 3."); return; }
    const EGLint version[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
    EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, version);
    EGLSurface surface = EGL_NO_SURFACE;
    bool started = false;
    uint32_t before[4] = {};
    int seen = -1;
    double last = 0, window_time = 0, slowest = 0;
    int window_frames = 0, late = 0;
    uint64_t number = 0;
    while (g_running) {
        if (g_changed.exchange(false)) {
            std::lock_guard<std::mutex> lock(g_surface);
            // The window drawn into is let go only once nothing draws into it any more.
            if (surface != EGL_NO_SURFACE) { eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT); eglDestroySurface(display, surface); }
            surface = EGL_NO_SURFACE;
            if (g_drawing) ANativeWindow_release(g_drawing);
            g_drawing = g_window;
            if (g_drawing) {
                ANativeWindow_acquire(g_drawing);
                // Always the console's size: Android scales the buffers to the view.
                ANativeWindow_setBuffersGeometry(g_drawing, W, H, 0);
                surface = eglCreateWindowSurface(display, config, g_drawing, nullptr);
                eglMakeCurrent(display, surface, surface, context);
                eglSwapInterval(display, 1);
            }
            last = 0;
        }
        if (surface == EGL_NO_SURFACE) { std::this_thread::sleep_for(std::chrono::milliseconds(16)); continue; }
        if (!started) {
            started = true;
            sg_desc desc = {};
            desc.environment.defaults.color_format = SG_PIXELFORMAT_RGBA8;
            desc.environment.defaults.depth_format = SG_PIXELFORMAT_DEPTH_STENCIL;
            desc.environment.defaults.sample_count = 1;
            desc.logger.func = lamp_host_sokol_log;
            sg_setup(&desc);
            lamp_host_seed((uint64_t)(now() * 1e6));
            LampSetup setup = { W, H, SG_PIXELFORMAT_RGBA8, SG_PIXELFORMAT_DEPTH_STENCIL, 1 };
            game_init(&setup);
            start_speaker();
        }
        double t = now();
        double dt = last == 0 ? 1.0 / 60.0 : t - last;
        if (dt > 0.05) dt = 0.05;
        last = t;
        LampFrame frame = {};
        {
            std::lock_guard<std::mutex> lock(g_input);
            int connected = 0;
            for (int i = 0; i < 4; i++) {
                LampPad pad = g_given.pads[i];
                if (i == 0) { pad.down |= g_given.tapped; pad.connected = true; }
                else if (pad.connected) connected++;
                lamp_host_edges(&pad, before[i]);
                before[i] = pad.down;
                frame.pads[i] = pad;
            }
            g_given.tapped = 0;
            if (connected != seen) { seen = connected; lamp_log("Lamp: %d controller%s connected.", connected, connected == 1 ? "" : "s"); }
        }
        g_time += dt;
        frame.dt = dt;
        frame.time = g_time;
        frame.number = number++;
        frame.width = W; frame.height = H;
        frame.swapchain.width = W; frame.swapchain.height = H; frame.swapchain.sample_count = 1;
        frame.swapchain.color_format = SG_PIXELFORMAT_RGBA8; frame.swapchain.depth_format = SG_PIXELFORMAT_DEPTH_STENCIL;
        frame.swapchain.gl.framebuffer = 0;
        game_frame(&frame);
        eglSwapBuffers(display, surface);
        window_time += dt; window_frames++;
        if (dt > slowest) slowest = dt;
        if (dt > 1.5 / 60.0) late++;
        if (window_time >= 10) {
            lamp_log("Lamp: frames %.1f ms on average, slowest %.1f ms, %d of %d late.", window_time * 1000 / window_frames, slowest * 1000, late, window_frames);
            window_time = 0; window_frames = 0; slowest = 0; late = 0;
        }
    }
}

// MARK: What the app calls

extern "C" JNIEXPORT void JNICALL Java_dev_lamp_game_Native_start(JNIEnv* env, jclass, jobject assets, jstring saves) {
    if (g_running) return;
    g_assets = AAssetManager_fromJava(env, env->NewGlobalRef(assets));
    const char* path = env->GetStringUTFChars(saves, nullptr);
    g_saves = path;
    env->ReleaseStringUTFChars(saves, path);
    g_running = true;
    g_thread = std::thread(run);
    g_thread.detach();
}

// The app's surface, or none when it's gone: the same one given again (Android says it changed) changes nothing.
extern "C" JNIEXPORT void JNICALL Java_dev_lamp_game_Native_surface(JNIEnv* env, jclass, jobject surface) {
    std::lock_guard<std::mutex> lock(g_surface);
    ANativeWindow* window = surface ? ANativeWindow_fromSurface(env, surface) : nullptr;
    if (window && window == g_window) { ANativeWindow_release(window); return; }
    if (g_window) ANativeWindow_release(g_window);
    g_window = window;
    g_changed = true;
}

// One pad, as the app reads it: sticks -1 to 1 with up positive, triggers 0 to 1, buttons as the kit's bits.
extern "C" JNIEXPORT void JNICALL Java_dev_lamp_game_Native_pad(JNIEnv*, jclass, jint index, jboolean connected, jfloat lx, jfloat ly,
                                                                 jfloat rx, jfloat ry, jfloat lt, jfloat rt, jint down, jint tapped) {
    if (index < 0 || index > 3) return;
    std::lock_guard<std::mutex> lock(g_input);
    LampPad& pad = g_given.pads[index];
    pad.connected = connected;
    pad.lx = lx; pad.ly = ly; pad.rx = rx; pad.ry = ry; pad.lt = lt; pad.rt = rt;
    pad.down = (uint32_t)down;
    if (index == 0) g_given.tapped |= (uint32_t)tapped;
}

extern "C" JNIEXPORT jint JNICALL Java_dev_lamp_game_Native_touchButtons(JNIEnv*, jclass) { return (jint)lamp_host_touch_buttons; }

// What a pad's motors should do now, low motor in the high byte, for the app to play on the controller.
extern "C" JNIEXPORT jint JNICALL Java_dev_lamp_game_Native_rumble(JNIEnv*, jclass, jint index) {
    return index >= 0 && index < 4 ? (jint)g_rumble[index].load() : 0;
}

extern "C" JNIEXPORT void JNICALL Java_dev_lamp_game_Native_pause(JNIEnv*, jclass, jboolean paused) {
    if (!g_stream) return;
    if (paused) AAudioStream_requestPause(g_stream); else AAudioStream_requestStart(g_stream);
}
