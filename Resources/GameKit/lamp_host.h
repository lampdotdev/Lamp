// Lamp's game kit: what the two hosts share, not for the game. Lamp writes this file before every build.
#pragma once
#include <stdint.h>
#include "lamp_game.h"

#ifdef __cplusplus
extern "C" {
#endif
void lamp_host_seed(uint64_t seed);
// Sets a pad's pressed and released from what was down the frame before.
void lamp_host_edges(LampPad* pad, uint32_t before);
float lamp_host_dead_zone(float value);
// The mix: `frames` stereo frames at 48 kHz, interleaved, into `out`. Called by the host's sound thread on the
// console and after each frame in the preview; it takes a lock the game's sound calls take too.
void lamp_host_mix(float* out, int frames);
// What was played, for the preview's report: each effect's name and how often, the music, and the loudest moment.
void lamp_host_sound_report(char* out, size_t size);
void lamp_host_sokol_log(const char* tag, uint32_t level, uint32_t item, const char* message, uint32_t line, const char* file, void* user);
#ifdef __cplusplus
}
#endif
