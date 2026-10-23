// Lamp's game kit: what a game is written against. Lamp writes this file before every build; don't edit it.
//
// The game is two functions, game_init and game_frame, drawn with sokol_gfx (sokol_gfx.h), with sokol_shape.h for
// boxes, spheres and the like, sokol_debugtext.h and sokol_gl.h for text and lines, HandmadeMath.h for vectors and
// matrices, cgltf.h for glTF models and stb_image.h for pictures. On the Xbox the host is a full-screen app drawing
// with Direct3D 11 at 1920x1080, 60 frames a second; on the Mac the same code is drawn with Metal, out of sight for
// Lamp's preview, or in a window the person plays in with a controller or the keyboard. Nothing here or in the game may call Windows or Apple APIs: everything the game needs from the
// machine goes through the functions below.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "sokol_gfx.h"

#ifdef __cplusplus
extern "C" {
#endif

// The controller's buttons, as bits of LampPad.down, .pressed and .released.
enum {
    LAMP_A = 1 << 0, LAMP_B = 1 << 1, LAMP_X = 1 << 2, LAMP_Y = 1 << 3,
    LAMP_LB = 1 << 4, LAMP_RB = 1 << 5,          // the bumpers
    LAMP_MENU = 1 << 6, LAMP_VIEW = 1 << 7,      // ≡ (start) and ⧉ (back)
    LAMP_UP = 1 << 8, LAMP_DOWN = 1 << 9, LAMP_LEFT = 1 << 10, LAMP_RIGHT = 1 << 11,   // the d-pad
    LAMP_LSTICK = 1 << 12, LAMP_RSTICK = 1 << 13 // a stick pressed in
};

typedef struct LampPad {
    bool connected;
    float lx, ly, rx, ry;  // the sticks, -1 to 1, up and right positive, with a small dead zone already taken out
    float lt, rt;          // the triggers, 0 to 1
    uint32_t down;         // buttons held now
    uint32_t pressed;      // buttons that went down since the last frame
    uint32_t released;     // buttons that came up since the last frame
} LampPad;

typedef struct LampSetup {
    int width, height;                 // 1920x1080
    sg_pixel_format color_format;      // what the screen is drawn in: pass to sdtx/sgl/pipelines
    sg_pixel_format depth_format;
    int sample_count;                  // 1
} LampSetup;

typedef struct LampFrame {
    double dt;          // seconds since the last frame: 1/60 at the console's pace, and always 1/60 on the Mac
    double time;        // seconds since the game started
    uint64_t number;    // frames since the game started
    int width, height;
    LampPad pads[4];    // pads[0] is the first controller
    sg_swapchain swapchain;   // give it to sg_begin_pass for the pass that draws the screen
} LampFrame;

// Written by the game.
void game_init(const LampSetup* setup);
void game_frame(const LampFrame* frame);   // draw one frame: sg_begin_pass(swapchain) … sg_end_pass(); sg_commit();

// What the game reads and keeps.
typedef struct LampFile { void* data; size_t size; } LampFile;   // data is NULL when there's nothing
LampFile lamp_asset(const char* path);   // a file from the app's Assets/ folder ("models/ship.glb")
LampFile lamp_load(const char* name);    // what the game saved under this name, or nothing
bool lamp_save(const char* name, const void* data, size_t size);   // kept on the console between plays
void lamp_free(LampFile file);

// A line in the game's log, which Lamp reads (printf's format). Keep it to what helps: a few lines, not one a frame.
void lamp_log(const char* format, ...);

// Random numbers. The preview starts every play with the same seed, so a play replays exactly; use these, never
// rand() or the time, for anything random.
uint32_t lamp_random(void);
float lamp_random_float(void);   // 0 up to 1

// The controller's rumble, 0 to 1 for its two motors, until called again with zeros.
void lamp_rumble(int pad, float low, float high);

#ifdef __cplusplus
}
#endif
