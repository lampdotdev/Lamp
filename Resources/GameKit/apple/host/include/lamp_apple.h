// Lamp's game kit: what the app's Swift calls of the game's host on Apple's devices (Lamp/lamp_apple.mm, compiled
// into build/<place>/libgame.a with the game). Lamp writes this file before every build; don't edit it.
#pragma once
#include <stdbool.h>
#include <stdint.h>

// Sets up drawing into the window's CAMetalLayer, the sound and the game (game_init), once.
void lamp_apple_start(void* layer, const char* assets, const char* saves);
// One frame of the game, `dt` seconds after the last; `keys` while the keyboard is the game's.
void lamp_apple_frame(double dt, bool keys);
// The Mac's keyboard, by key code.
void lamp_apple_key(unsigned short code, bool down);
void lamp_apple_keys_up(void);
// What the touch controls hold now: the sticks, -1 to 1 with up positive, and the buttons as the kit's bits.
void lamp_apple_touch(float lx, float ly, float rx, float ry, uint32_t down);
// The buttons the game wants on the touch controls (`lamp_touch_buttons`).
uint32_t lamp_apple_touch_buttons(void);
// How many controllers are connected.
int lamp_apple_controllers(void);
