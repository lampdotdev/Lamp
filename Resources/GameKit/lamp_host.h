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
void lamp_host_sokol_log(const char* tag, uint32_t level, uint32_t item, const char* message, uint32_t line, const char* file, void* user);
#ifdef __cplusplus
}
#endif
