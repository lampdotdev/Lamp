// Lamp's game kit: the sokol libraries' code and what both hosts share. Lamp writes this file before every build.
// Compiled once per host, with SOKOL_D3D11 for the Xbox or SOKOL_METAL (as Objective-C++) for the Mac preview.
#if defined(SOKOL_D3D11)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
// LoadLibraryA isn't in an app's part of the Windows API; LoadLibraryExA is, and loads the same system library
// (sokol_gfx loads d3dcompiler_47.dll with it to compile the shaders on the console).
#define LoadLibraryA(name) LoadLibraryExA(name, NULL, 0)
#endif
// The declarations first, then each library's code (sokol's headers allow being included again with SOKOL_IMPL).
#include "lamp_game.h"
#include "lamp_host.h"
#define SOKOL_IMPL
#include "sokol_gfx.h"
#include "sokol_log.h"
#include "sokol_gl.h"
#include "sokol_debugtext.h"
#include "sokol_shape.h"
#define HANDMADE_MATH_IMPLEMENTATION
#include "HandmadeMath.h"
#define CGLTF_IMPLEMENTATION
#include "cgltf.h"
#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_STDIO
#include "stb_image.h"
#include <stdlib.h>

static uint64_t lamp_seed = 0x9E3779B97F4A7C15ull;

void lamp_host_seed(uint64_t seed) { lamp_seed = seed ? seed : 0x9E3779B97F4A7C15ull; }

// xorshift64*: small, fast and the same on both hosts.
uint32_t lamp_random(void) {
    lamp_seed ^= lamp_seed >> 12;
    lamp_seed ^= lamp_seed << 25;
    lamp_seed ^= lamp_seed >> 27;
    return (uint32_t)((lamp_seed * 0x2545F4914F6CDD1Dull) >> 32);
}

float lamp_random_float(void) { return (float)(lamp_random() >> 8) / 16777216.0f; }

void lamp_free(LampFile file) { free(file.data); }

void lamp_host_edges(LampPad* pad, uint32_t before) {
    pad->pressed = pad->down & ~before;
    pad->released = before & ~pad->down;
}

float lamp_host_dead_zone(float value) {
    const float zone = 0.12f;
    if (value > zone) return (value - zone) / (1 - zone);
    if (value < -zone) return (value + zone) / (1 - zone);
    return 0;
}

void lamp_host_sokol_log(const char* tag, uint32_t level, uint32_t item, const char* message, uint32_t line, const char* file, void*) {
    // Errors and warnings only: sokol's info lines would fill the log.
    if (level > 1) return;
    lamp_log("[%s] %s: %s (%s:%u)", tag ? tag : "sokol", level == 0 ? "panic" : "error", message ? message : "", file ? file : "", line);
    (void)item;
}
