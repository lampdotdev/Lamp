// Lamp's game kit: sound. Lamp writes this file before every build.
//
// The game's effects and music, mixed here into one stereo stream at 48 kHz that the host plays: XAudio2 pulls it on
// the console, and the preview mixes it after each frame without playing it. Files are decoded with stb_vorbis
// (.ogg), dr_wav (.wav) and dr_mp3 (.mp3): an effect whole when it's loaded, music a little at a time as it plays.
// The game's calls and the host's mix share one lock, so the mix never sees half a change.
#include "lamp_game.h"
#include "lamp_host.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mutex>
#include <string>
#include <vector>

#define STB_VORBIS_NO_STDIO
#define STB_VORBIS_NO_PUSHDATA_API
#include "stb_vorbis.c"
#undef L
#undef C
#undef R
#define DR_WAV_IMPLEMENTATION
#define DR_WAV_NO_STDIO
#define DR_WAV_NO_WCHAR
#include "dr_wav.h"
#define DR_MP3_IMPLEMENTATION
#define DR_MP3_NO_STDIO
#include "dr_mp3.h"

namespace {

const int RATE = 48000;
const int VOICES = 32;
const double PI = 3.14159265358979323846;

struct Clip {
    std::vector<float> data;   // interleaved, `channels` of them
    int channels = 1;
    int rate = RATE;
    size_t frames = 0;
    std::string name;
    int plays = 0;
    double first = -1;         // when it first played, in seconds of the mix
};

struct Voice {
    uint32_t clip = 0;         // 0: the voice is free
    uint32_t generation = 0;
    double position = 0;       // in the clip's frames
    float volume = 1, pan = 0, pitch = 1;
    float gain = 0;            // what the voice played at the end of the last block, eased toward its volume
    bool loop = false, stopping = false;
    uint64_t started = 0;
};

std::vector<struct Clip>& all_clips();

// A piece of music being read from its file as it plays, or one of the game's own sounds played as music.
struct Stream {
    uint32_t clip = 0;          // the game's own sound, when it's that
    LampFile file = { nullptr, 0 };
    stb_vorbis* vorbis = nullptr;
    drwav wav;
    drmp3 mp3;
    bool has_wav = false, has_mp3 = false;
    int channels = 0, rate = RATE;
    std::vector<float> buffer;  // decoded frames, interleaved
    size_t frames = 0;          // how many are in the buffer
    double position = 0;        // in the buffer
    float gain = 0, target = 0; // eased over half a second
    std::string name;
    bool failed = false;

    bool open(const char* path) {
        name = path;
        file = lamp_asset(path);
        if (!file.data) return false;
        int error = 0;
        if ((vorbis = stb_vorbis_open_memory((const unsigned char*)file.data, (int)file.size, &error, nullptr))) {
            stb_vorbis_info info = stb_vorbis_get_info(vorbis);
            channels = info.channels; rate = (int)info.sample_rate;
        } else if (drwav_init_memory(&wav, file.data, file.size, nullptr)) {
            has_wav = true; channels = (int)wav.channels; rate = (int)wav.sampleRate;
        } else if (drmp3_init_memory(&mp3, file.data, file.size, nullptr)) {
            has_mp3 = true; channels = (int)mp3.channels; rate = (int)mp3.sampleRate;
        } else {
            lamp_log("lamp_music: Assets/%s isn't a sound Lamp can read (.ogg, .mp3 or .wav)", path);
            return false;
        }
        if (channels < 1 || channels > 2 || rate < 8000 || rate > 192000) {
            lamp_log("lamp_music: Assets/%s has %d channels at %d Hz; give it one or two", path, channels, rate);
            return false;
        }
        return true;
    }

    void close() {
        if (vorbis) stb_vorbis_close(vorbis);
        if (has_wav) drwav_uninit(&wav);
        if (has_mp3) drmp3_uninit(&mp3);
        lamp_free(file);
        vorbis = nullptr; has_wav = has_mp3 = false; file = { nullptr, 0 };
    }

    // Decodes up to `count` frames onto the end of the buffer, from the start again at the end of the file.
    void decode(size_t count) {
        buffer.resize((frames + count) * channels);
        float* into = buffer.data() + frames * channels;
        size_t got = 0;
        for (int tries = 0; got < count && tries < 2; tries++) {
            size_t read = 0;
            if (vorbis) read = (size_t)stb_vorbis_get_samples_float_interleaved(vorbis, channels, into + got * channels, (int)((count - got) * channels));
            else if (has_wav) read = (size_t)drwav_read_pcm_frames_f32(&wav, count - got, into + got * channels);
            else if (has_mp3) read = (size_t)drmp3_read_pcm_frames_f32(&mp3, count - got, into + got * channels);
            got += read;
            if (read > 0) tries = -1;   // more came: keep reading
            else if (got < count) {     // the end: round again
                if (vorbis) stb_vorbis_seek_start(vorbis);
                else if (has_wav) drwav_seek_to_pcm_frame(&wav, 0);
                else if (has_mp3) drmp3_seek_to_pcm_frame(&mp3, 0);
            }
        }
        if (got == 0) failed = true;   // a file that gives nothing even from its start
        frames += got;
        buffer.resize(frames * channels);
    }

    // The next frame of the music in stereo, moving on at the music's pace.
    void next(float& left, float& right) {
        if (clip) {
            const Clip& c = all_clips()[clip - 1];
            if (position >= (double)c.frames) position -= (double)c.frames;
            size_t at = (size_t)position, after = at + 1 < c.frames ? at + 1 : 0;
            float t = (float)(position - (double)at);
            left = c.data[at * c.channels] + (c.data[after * c.channels] - c.data[at * c.channels]) * t;
            right = c.channels == 2 ? c.data[at * 2 + 1] + (c.data[after * 2 + 1] - c.data[at * 2 + 1]) * t : left;
            position += (double)c.rate / RATE;
            return;
        }
        size_t at = (size_t)position;
        if (at + 1 >= frames && !failed) {
            // Keep the frame being played and the one after it; read on from there.
            size_t keep = frames > at ? frames - at : 0;
            memmove(buffer.data(), buffer.data() + at * channels, keep * channels * sizeof(float));
            frames = keep;
            position -= (double)at;
            at = 0;
            decode(4096);
        }
        if (at + 1 >= frames) { left = right = 0; return; }
        float t = (float)(position - (double)at);
        const float* a = buffer.data() + at * channels;
        const float* b = a + channels;
        left = a[0] + (b[0] - a[0]) * t;
        right = channels == 2 ? a[1] + (b[1] - a[1]) * t : left;
        position += (double)rate / RATE;
    }
};

std::mutex lock;
std::vector<Clip> clips;            // a LampSound's id is its place here, plus one
std::vector<Clip>& all_clips() { return clips; }
Voice voices[VOICES];
uint64_t voice_count = 0;           // voices started, to find the oldest
Stream* music = nullptr;            // what plays now
Stream* fading = nullptr;           // what plays out under it
float effects_volume = 1, music_volume = 1;
uint64_t mixed = 0;                 // frames mixed so far
float loudest = 0;                  // the highest the mix went before it was kept within full volume
uint64_t over = 0;                  // frames that went over full volume
std::string music_names;            // what music was asked for, for the report
uint32_t noise_seed = 0x12345678u;  // the kit's own, so a made sound never moves the game's random numbers

std::string base_name(const char* path) {
    std::string p(path ? path : "");
    size_t slash = p.find_last_of('/');
    if (slash != std::string::npos) p = p.substr(slash + 1);
    size_t dot = p.find_last_of('.');
    if (dot != std::string::npos && dot > 0) p = p.substr(0, dot);
    return p;
}

float clamp(float v, float lo, float hi) { return v < lo ? lo : v > hi ? hi : v; }

LampSound add(Clip&& clip) {
    std::lock_guard<std::mutex> hold(lock);
    if (clip.frames == 0) return { 0 };
    clips.push_back(std::move(clip));
    return { (uint32_t)clips.size() };
}

int play(LampSound sound, float volume, float pan, float pitch, bool loop) {
    std::lock_guard<std::mutex> hold(lock);
    if (sound.id == 0 || sound.id > clips.size()) return 0;
    int slot = -1;
    for (int i = 0; i < VOICES && slot < 0; i++) if (!voices[i].clip) slot = i;
    if (slot < 0) {   // all busy: the oldest one that doesn't loop gives way, else the oldest
        uint64_t oldest = UINT64_MAX;
        for (int pass = 0; pass < 2 && slot < 0; pass++)
            for (int i = 0; i < VOICES; i++)
                if ((pass == 1 || !voices[i].loop) && voices[i].started < oldest) { oldest = voices[i].started; slot = i; }
    }
    Voice& v = voices[slot];
    v.clip = sound.id;
    v.generation = (v.generation + 1) & 0x3FFFFF;   // so a voice, shifted up past its slot, stays a positive int
    if (v.generation == 0) v.generation = 1;
    v.position = 0;
    v.volume = clamp(volume, 0, 1); v.pan = clamp(pan, -1, 1); v.pitch = clamp(pitch, 0.05f, 8);
    v.gain = v.volume;   // an effect starts at once; easing it in would blunt its start
    v.loop = loop; v.stopping = false;
    v.started = ++voice_count;
    Clip& clip = clips[sound.id - 1];
    clip.plays++;
    if (clip.first < 0) clip.first = (double)mixed / RATE;
    return (int)((v.generation << 8) | (uint32_t)slot);
}

Voice* find(int voice) {
    if (voice <= 0) return nullptr;
    int slot = voice & 0xFF;
    uint32_t generation = (uint32_t)voice >> 8;
    if (slot >= VOICES || !voices[slot].clip || voices[slot].generation != generation) return nullptr;
    return &voices[slot];
}

}  // namespace

extern "C" LampSound lamp_sound_load(const char* path) {
    LampFile file = lamp_asset(path);
    if (!file.data) return { 0 };
    Clip clip;
    clip.name = base_name(path);
    unsigned int channels = 0, rate = 0;
    drwav_uint64 frames = 0;
    float* data = nullptr;
    bool mp3 = false;
    int error = 0;
    if (stb_vorbis* v = stb_vorbis_open_memory((const unsigned char*)file.data, (int)file.size, &error, nullptr)) {
        stb_vorbis_info info = stb_vorbis_get_info(v);
        channels = (unsigned)info.channels; rate = info.sample_rate;
        unsigned total = stb_vorbis_stream_length_in_samples(v);
        if (channels >= 1 && channels <= 2 && total > 0) {
            clip.data.resize((size_t)total * channels);
            frames = (drwav_uint64)stb_vorbis_get_samples_float_interleaved(v, (int)channels, clip.data.data(), (int)clip.data.size());
        }
        stb_vorbis_close(v);
    } else if ((data = drwav_open_memory_and_read_pcm_frames_f32(file.data, file.size, &channels, &rate, &frames, nullptr))) {
    } else {
        drmp3_config config;
        if ((data = drmp3_open_memory_and_read_pcm_frames_f32(file.data, file.size, &config, (drmp3_uint64*)&frames, nullptr))) {
            channels = config.channels; rate = config.sampleRate; mp3 = true;
        }
    }
    lamp_free(file);
    if (data) {
        if (channels >= 1 && channels <= 2) clip.data.assign(data, data + (size_t)frames * channels);
        if (mp3) drmp3_free(data, nullptr); else drwav_free(data, nullptr);
    }
    if (clip.data.empty() || channels < 1 || channels > 2 || rate < 8000 || rate > 192000) {
        lamp_log("lamp_sound_load: Assets/%s isn't a sound Lamp can read (.wav, .ogg or .mp3, one or two channels)", path);
        return { 0 };
    }
    clip.channels = (int)channels;
    clip.rate = (int)rate;
    clip.frames = (size_t)frames;
    if (clip.frames > (size_t)rate * 15) lamp_log("lamp_sound_load: Assets/%s is %.0f s long: play long sounds with lamp_music, which reads them as they play", path, (double)clip.frames / rate);
    return add(std::move(clip));
}

extern "C" LampSound lamp_sound_tone(LampTone tone) {
    float attack = clamp(tone.attack, 0, 10), held = clamp(tone.hold, 0, 10), release = clamp(tone.release, 0, 10);
    float length = attack + held + release;
    if (length <= 0) { lamp_log("lamp_sound_tone: a tone needs some attack, hold or release (seconds)"); return { 0 }; }
    float from = clamp(tone.from_hz, 1, 20000), to = tone.to_hz > 0 ? clamp(tone.to_hz, 1, 20000) : from;
    float volume = clamp(tone.volume, 0, 1);
    // A square or saw wave sounds far louder than a sine at the same height: each is brought to about a sine's.
    const float level[] = { 1.0f, 0.45f, 0.9f, 0.55f, 0.6f };
    float wave_level = level[tone.wave >= LAMP_SINE && tone.wave <= LAMP_NOISE ? tone.wave : 0];
    Clip clip;
    // Named for the preview's report by its wave and pitch, so two tones are told apart there.
    const char* waves[] = { "sine", "square", "triangle", "saw", "noise" };
    char name[64];
    if (to == from) snprintf(name, sizeof name, "%s tone %.0f Hz", waves[tone.wave >= LAMP_SINE && tone.wave <= LAMP_NOISE ? tone.wave : 0], from);
    else snprintf(name, sizeof name, "%s tone %.0f-%.0f Hz", waves[tone.wave >= LAMP_SINE && tone.wave <= LAMP_NOISE ? tone.wave : 0], from, to);
    clip.name = name;
    clip.frames = (size_t)(length * RATE);
    clip.data.resize(clip.frames);
    double phase = 0;
    float held_noise = 0;
    for (size_t i = 0; i < clip.frames; i++) {
        float t = (float)i / RATE;
        float envelope = t < attack ? t / attack : t < attack + held ? 1 : 1 - (t - attack - held) / (release > 0 ? release : 1);
        // The pitch moves evenly in octaves, as a slide sounds to the ear.
        double hz = from * pow((double)to / from, (double)t / length);
        double before = phase;
        phase += hz / RATE;
        phase -= floor(phase);
        float s;
        switch (tone.wave) {
            case LAMP_SQUARE: s = phase < 0.5 ? 1.0f : -1.0f; break;
            case LAMP_TRIANGLE: s = (float)(phase < 0.5 ? 4 * phase - 1 : 3 - 4 * phase); break;
            case LAMP_SAW: s = (float)(2 * phase - 1); break;
            case LAMP_NOISE:
                // A new random height each cycle of the pitch: high pitches hiss, low ones rumble.
                if (phase < before || i == 0) { noise_seed = noise_seed * 1664525u + 1013904223u; held_noise = (float)(noise_seed >> 8) / 8388608.0f - 1; }
                s = held_noise; break;
            default: s = (float)sin(2 * PI * phase); break;
        }
        clip.data[i] = s * envelope * volume * wave_level;
    }
    return add(std::move(clip));
}

extern "C" LampSound lamp_sound_samples(const float* samples, int count, int rate) {
    if (!samples || count <= 0 || rate < 8000 || rate > 192000) { lamp_log("lamp_sound_samples: give samples, how many, and a rate from 8000 to 192000"); return { 0 }; }
    Clip clip;
    clip.name = "samples";
    clip.rate = rate;
    clip.frames = (size_t)count;
    clip.data.assign(samples, samples + count);
    for (float& s : clip.data) s = s != s ? 0 : clamp(s, -1, 1);
    return add(std::move(clip));
}

extern "C" int lamp_play(LampSound sound, float volume, float pan, float pitch) { return play(sound, volume, pan, pitch, false); }
extern "C" int lamp_play_loop(LampSound sound, float volume, float pan, float pitch) { return play(sound, volume, pan, pitch, true); }

extern "C" void lamp_voice_set(int voice, float volume, float pan, float pitch) {
    std::lock_guard<std::mutex> hold(lock);
    if (Voice* v = find(voice)) { v->volume = clamp(volume, 0, 1); v->pan = clamp(pan, -1, 1); v->pitch = clamp(pitch, 0.05f, 8); }
}

extern "C" void lamp_stop(int voice) {
    std::lock_guard<std::mutex> hold(lock);
    if (Voice* v = find(voice)) v->stopping = true;   // faded out over the next few milliseconds, never cut with a click
}

extern "C" void lamp_stop_all(void) {
    std::lock_guard<std::mutex> hold(lock);
    for (Voice& v : voices) if (v.clip) v.stopping = true;
}

extern "C" void lamp_music(const char* path, float volume) {
    Stream* next = nullptr;
    if (path && *path) {
        {
            std::lock_guard<std::mutex> hold(lock);
            if (music && music->name == path) { music->target = clamp(volume, 0, 1); return; }   // already playing
        }
        next = new Stream();
        if (!next->open(path)) { next->close(); delete next; return; }
        next->target = clamp(volume, 0, 1);
        next->decode(4096);
    }
    Stream* gone = nullptr;
    {
        std::lock_guard<std::mutex> hold(lock);
        gone = fading;   // a third piece asked for mid-fade: the oldest goes at once
        fading = music;
        if (fading) fading->target = 0;
        music = next;
        if (next) { if (!music_names.empty()) music_names += ", "; music_names += path; }
    }
    if (gone) { gone->close(); delete gone; }
}

extern "C" void lamp_music_sound(LampSound sound, float volume) {
    Stream* gone = nullptr;
    {
        std::lock_guard<std::mutex> hold(lock);
        if (sound.id > clips.size()) return;
        if (sound.id && music && music->clip == sound.id) { music->target = clamp(volume, 0, 1); return; }
        Stream* next = nullptr;
        if (sound.id) {
            next = new Stream();
            next->clip = sound.id;
            next->name = clips[sound.id - 1].name;
            next->target = clamp(volume, 0, 1);
            if (!music_names.empty()) music_names += ", ";
            music_names += next->name;
        }
        gone = fading;
        fading = music;
        if (fading) fading->target = 0;
        music = next;
    }
    if (gone) { gone->close(); delete gone; }
}

extern "C" void lamp_music_volume(float volume) {
    std::lock_guard<std::mutex> hold(lock);
    if (music) music->target = clamp(volume, 0, 1);
}

extern "C" void lamp_volume(float effects, float music_) {
    std::lock_guard<std::mutex> hold(lock);
    effects_volume = clamp(effects, 0, 1);
    music_volume = clamp(music_, 0, 1);
}

extern "C" void lamp_host_mix(float* out, int frames) {
    memset(out, 0, sizeof(float) * 2 * (size_t)frames);
    Stream* done = nullptr;
    {
        std::lock_guard<std::mutex> hold(lock);
        const float ease = 1.0f / (RATE * 0.005f);   // a volume or a stop takes 5 ms, so nothing clicks
        for (Voice& v : voices) {
            if (!v.clip) continue;
            const Clip& clip = clips[v.clip - 1];
            double step = (double)clip.rate / RATE * v.pitch;
            float angle = (v.pan + 1) * (float)PI / 4;
            float left = cosf(angle) * 1.41421356f, right = sinf(angle) * 1.41421356f;
            if (left > 1) left = 1;
            if (right > 1) right = 1;
            for (int i = 0; i < frames; i++) {
                float aim = v.stopping ? 0 : v.volume;
                if (v.gain < aim) v.gain = fminf(aim, v.gain + ease); else if (v.gain > aim) v.gain = fmaxf(aim, v.gain - ease);
                if (v.stopping && v.gain <= 0) { v.clip = 0; break; }
                size_t at = (size_t)v.position;
                if (at >= clip.frames) {
                    if (!v.loop) { v.clip = 0; break; }
                    v.position -= (double)clip.frames;
                    at = (size_t)v.position;
                }
                size_t after = at + 1 < clip.frames ? at + 1 : (v.loop ? 0 : at);
                float t = (float)(v.position - (double)at);
                float l, r;
                if (clip.channels == 2) {
                    l = clip.data[at * 2] + (clip.data[after * 2] - clip.data[at * 2]) * t;
                    r = clip.data[at * 2 + 1] + (clip.data[after * 2 + 1] - clip.data[at * 2 + 1]) * t;
                } else {
                    l = r = clip.data[at] + (clip.data[after] - clip.data[at]) * t;
                }
                float g = v.gain * effects_volume;
                out[i * 2] += l * g * left;
                out[i * 2 + 1] += r * g * right;
                v.position += step;
            }
        }
        const float fade = 1.0f / (RATE * 0.5f);   // music comes and goes over half a second
        for (Stream* s : { music, fading }) {
            if (!s) continue;
            for (int i = 0; i < frames; i++) {
                if (s->gain < s->target) s->gain = fminf(s->target, s->gain + fade); else if (s->gain > s->target) s->gain = fmaxf(s->target, s->gain - fade);
                if (s == fading && s->gain <= 0) break;
                float l, r;
                s->next(l, r);
                float g = s->gain * music_volume;
                out[i * 2] += l * g;
                out[i * 2 + 1] += r * g;
            }
        }
        if (fading && fading->gain <= 0) { done = fading; fading = nullptr; }
        // Kept within full volume: what's under 0.9 passes as it is, and above that it's bent smoothly toward 1 rather
        // than cut, which would crackle.
        for (int i = 0; i < frames * 2; i++) {
            float x = out[i], a = fabsf(x);
            if (a > loudest) loudest = a;
            if (a > 0.9f) out[i] = copysignf(0.9f + 0.1f * tanhf((a - 0.9f) / 0.1f), x);
            if (a > 1 && (i & 1) == 0) over++;
        }
        mixed += (uint64_t)frames;
    }
    if (done) { done->close(); delete done; }
}

extern "C" void lamp_host_sound_report(char* out, size_t size) {
    std::lock_guard<std::mutex> hold(lock);
    std::string said;
    for (const Clip& clip : clips) {
        if (!clip.plays) continue;
        char part[160];
        snprintf(part, sizeof part, "%s%s ×%d (first at %.2f s)", said.empty() ? "" : ", ", clip.name.c_str(), clip.plays, clip.first);
        said += part;
    }
    if (said.empty()) said = "no effects played";
    else said = "effects played: " + said;
    if (!music_names.empty()) said += "; music: " + music_names;
    char tail[160];
    if (loudest <= 0) snprintf(tail, sizeof tail, "; silent");
    else snprintf(tail, sizeof tail, "; loudest %.1f dB of full volume%s", 20 * log10f(loudest),
                  over ? (", over full volume for " + std::to_string(over * 1000 / RATE) + " ms (too loud: play it quieter)").c_str() : "");
    said += tail;
    snprintf(out, size, "%s", said.c_str());
}
