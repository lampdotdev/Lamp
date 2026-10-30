// Phones as controllers for a game on the Xbox, run by the game's own host (lamp_web_host.cpp) with no Lamp: the phone
// page from the game's package and the relay its phones and its page meet at, as a Mac game runs them in its own
// process (LampRelayKit's ControllerRuntime, PhonePageServer and Relay, whose wire this keeps to message for message:
// ControllerWire, ControllerToken). Only the game part of Lamp's relay is here: a wish's room stays at Lamp's.
//
// Plain C++ with nothing of Windows in it, so the same protocol runs on a Mac too (scripts/check-web-host-controllers.sh).
// Whoever includes it supplies the platform's randomness, HMAC-SHA256 and SHA-1 (`lampc::platform`), and the sockets:
// a `Transport` under each WebSocket, and the bytes of each page request. Everything here runs on one thread.
#pragma once
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

namespace lampc {

namespace platform {
// Cryptographically random bytes from the system.
void random_bytes(uint8_t* out, size_t count);
std::array<uint8_t, 32> hmac_sha256(std::string_view key, std::string_view data);
std::array<uint8_t, 20> sha1(std::string_view data);
}

// ControllerWire's numbers, which lamp.js and lamp-controller.js keep too.
namespace wire {
constexpr size_t message = 16 * 1024;
constexpr size_t chunk = 64 * 1024;
constexpr size_t header = 8;
constexpr int64_t window = 512 * 1024;
constexpr int64_t file = 64 * 1024 * 1024;
constexpr size_t transfers = 2;
constexpr int players = 8;
constexpr double per_second = 120;
constexpr size_t backlog = 32;
constexpr int64_t silence_ms = 15000;
constexpr int64_t beat_ms = 5000;
// The largest message a socket takes: a file's piece with its header, sent by a browser as one frame.
constexpr size_t message_limit = chunk + 1024;
}

inline int64_t wall_ms() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
}

// MARK: JSON

// Enough JSON for the controllers' messages: objects keep their keys sorted (a credential's body is written that way),
// numbers are doubles, and text is UTF-8 passed through as it came.
struct Json {
    enum class Type { null, boolean, number, string, array, object };
    Type type = Type::null;
    bool b = false;
    double n = 0;
    std::string s;
    std::vector<Json> a;
    std::map<std::string, Json> o;

    Json() = default;
    Json(bool v) : type(Type::boolean), b(v) {}
    Json(int v) : type(Type::number), n(v) {}
    Json(int64_t v) : type(Type::number), n((double)v) {}
    Json(double v) : type(Type::number), n(v) {}
    Json(const char* v) : type(Type::string), s(v) {}
    Json(std::string v) : type(Type::string), s(std::move(v)) {}
    static Json object() { Json j; j.type = Type::object; return j; }
    static Json array() { Json j; j.type = Type::array; return j; }

    Json& operator[](const std::string& key) { type = Type::object; return o[key]; }
    const Json* get(const std::string& key) const {
        if (type != Type::object) return nullptr;
        auto found = o.find(key);
        return found == o.end() ? nullptr : &found->second;
    }
    std::optional<std::string> str(const std::string& key) const {
        auto v = get(key);
        if (!v || v->type != Type::string) return std::nullopt;
        return v->s;
    }
    // A whole number, as Swift's `as? Int` reads one.
    std::optional<int64_t> integer(const std::string& key) const {
        auto v = get(key);
        if (!v || v->type != Type::number || !std::isfinite(v->n) || v->n != std::floor(v->n) || std::fabs(v->n) > 9.0e15) return std::nullopt;
        return (int64_t)v->n;
    }
    bool is_true(const std::string& key) const {
        auto v = get(key);
        return v && v->type == Type::boolean && v->b;
    }

    std::string dump() const {
        std::string out;
        write(out);
        return out;
    }

    void write(std::string& out) const {
        switch (type) {
        case Type::null: out += "null"; break;
        case Type::boolean: out += b ? "true" : "false"; break;
        case Type::number: {
            char buffer[32];
            if (!std::isfinite(n)) out += "0";
            else if (n == std::floor(n) && std::fabs(n) < 9.0e15) { std::snprintf(buffer, sizeof buffer, "%lld", (long long)n); out += buffer; }
            else { std::snprintf(buffer, sizeof buffer, "%.17g", n); out += buffer; }
            break;
        }
        case Type::string: quote(out, s); break;
        case Type::array:
            out += '[';
            for (size_t i = 0; i < a.size(); i++) { if (i) out += ','; a[i].write(out); }
            out += ']';
            break;
        case Type::object: {
            out += '{';
            bool first = true;
            for (auto const& [key, value] : o) {
                if (!first) out += ',';
                first = false;
                quote(out, key);
                out += ':';
                value.write(out);
            }
            out += '}';
            break;
        }
        }
    }

    static void quote(std::string& out, std::string_view text) {
        out += '"';
        for (unsigned char c : text) {
            switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) { char u[8]; std::snprintf(u, sizeof u, "\\u%04x", c); out += u; }
                else out += (char)c;
            }
        }
        out += '"';
    }

    static std::optional<Json> parse(std::string_view text) {
        Parser p{ text, 0 };
        Json value;
        if (!p.value(value, 0)) return std::nullopt;
        p.space();
        if (p.at != text.size()) return std::nullopt;
        return value;
    }

private:
    struct Parser {
        std::string_view t;
        size_t at;
        void space() { while (at < t.size() && (t[at] == ' ' || t[at] == '\t' || t[at] == '\n' || t[at] == '\r')) at++; }
        bool word(std::string_view w) {
            if (t.substr(at, w.size()) != w) return false;
            at += w.size();
            return true;
        }
        bool value(Json& out, int depth) {
            if (depth > 64) return false;
            space();
            if (at >= t.size()) return false;
            char c = t[at];
            if (c == '{') {
                at++;
                out = object();
                space();
                if (at < t.size() && t[at] == '}') { at++; return true; }
                for (;;) {
                    space();
                    std::string key;
                    if (at >= t.size() || t[at] != '"' || !string(key)) return false;
                    space();
                    if (at >= t.size() || t[at++] != ':') return false;
                    Json item;
                    if (!value(item, depth + 1)) return false;
                    out.o[key] = std::move(item);
                    space();
                    if (at >= t.size()) return false;
                    if (t[at] == ',') { at++; continue; }
                    if (t[at] == '}') { at++; return true; }
                    return false;
                }
            }
            if (c == '[') {
                at++;
                out = array();
                space();
                if (at < t.size() && t[at] == ']') { at++; return true; }
                for (;;) {
                    Json item;
                    if (!value(item, depth + 1)) return false;
                    out.a.push_back(std::move(item));
                    space();
                    if (at >= t.size()) return false;
                    if (t[at] == ',') { at++; continue; }
                    if (t[at] == ']') { at++; return true; }
                    return false;
                }
            }
            if (c == '"') { out = Json(std::string()); return string(out.s); }
            if (word("true")) { out = Json(true); return true; }
            if (word("false")) { out = Json(false); return true; }
            if (word("null")) { out = Json(); return true; }
            return number(out);
        }
        bool number(Json& out) {
            size_t start = at;
            if (at < t.size() && t[at] == '-') at++;
            if (at >= t.size() || !isdigit((unsigned char)t[at])) return false;
            while (at < t.size() && (isdigit((unsigned char)t[at]) || t[at] == '.' || t[at] == 'e' || t[at] == 'E' || t[at] == '+' || t[at] == '-')) at++;
            std::string piece(t.substr(start, at - start));
            char* end = nullptr;
            double v = std::strtod(piece.c_str(), &end);
            if (!end || *end != '\0') return false;
            out = Json(v);
            return true;
        }
        static void utf8(std::string& out, uint32_t cp) {
            if (cp < 0x80) out += (char)cp;
            else if (cp < 0x800) { out += (char)(0xC0 | (cp >> 6)); out += (char)(0x80 | (cp & 0x3F)); }
            else if (cp < 0x10000) { out += (char)(0xE0 | (cp >> 12)); out += (char)(0x80 | ((cp >> 6) & 0x3F)); out += (char)(0x80 | (cp & 0x3F)); }
            else { out += (char)(0xF0 | (cp >> 18)); out += (char)(0x80 | ((cp >> 12) & 0x3F)); out += (char)(0x80 | ((cp >> 6) & 0x3F)); out += (char)(0x80 | (cp & 0x3F)); }
        }
        bool hex4(uint32_t& v) {
            if (at + 4 > t.size()) return false;
            v = 0;
            for (int i = 0; i < 4; i++) {
                char h = t[at++];
                v <<= 4;
                if (h >= '0' && h <= '9') v |= h - '0';
                else if (h >= 'a' && h <= 'f') v |= h - 'a' + 10;
                else if (h >= 'A' && h <= 'F') v |= h - 'A' + 10;
                else return false;
            }
            return true;
        }
        bool string(std::string& out) {
            at++;
            while (at < t.size()) {
                unsigned char c = t[at++];
                if (c == '"') return true;
                if (c < 0x20) return false;
                if (c != '\\') { out += (char)c; continue; }
                if (at >= t.size()) return false;
                char e = t[at++];
                switch (e) {
                case '"': out += '"'; break;
                case '\\': out += '\\'; break;
                case '/': out += '/'; break;
                case 'b': out += '\b'; break;
                case 'f': out += '\f'; break;
                case 'n': out += '\n'; break;
                case 'r': out += '\r'; break;
                case 't': out += '\t'; break;
                case 'u': {
                    uint32_t cp;
                    if (!hex4(cp)) return false;
                    if (cp >= 0xD800 && cp < 0xDC00) {
                        uint32_t low;
                        if (at + 2 > t.size() || t[at] != '\\' || t[at + 1] != 'u') return false;
                        at += 2;
                        if (!hex4(low) || low < 0xDC00 || low > 0xDFFF) return false;
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                    } else if (cp >= 0xDC00 && cp < 0xE000) return false;
                    utf8(out, cp);
                    break;
                }
                default: return false;
                }
            }
            return false;
        }
    };
};

// MARK: Bytes

inline std::string base64(std::string_view data, bool url_safe) {
    static const char* plain = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    static const char* safe = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    const char* table = url_safe ? safe : plain;
    std::string out;
    size_t i = 0;
    for (; i + 2 < data.size(); i += 3) {
        uint32_t v = (uint8_t)data[i] << 16 | (uint8_t)data[i + 1] << 8 | (uint8_t)data[i + 2];
        out += table[v >> 18]; out += table[(v >> 12) & 63]; out += table[(v >> 6) & 63]; out += table[v & 63];
    }
    if (i + 1 == data.size()) {
        uint32_t v = (uint8_t)data[i] << 16;
        out += table[v >> 18]; out += table[(v >> 12) & 63];
        if (!url_safe) out += "==";
    } else if (i + 2 == data.size()) {
        uint32_t v = (uint8_t)data[i] << 16 | (uint8_t)data[i + 1] << 8;
        out += table[v >> 18]; out += table[(v >> 12) & 63]; out += table[(v >> 6) & 63];
        if (!url_safe) out += '=';
    }
    return out;
}

// URL-safe base64 without padding, as ControllerToken writes it; nil for anything else.
inline std::optional<std::string> unbase64url(std::string_view text) {
    std::string out;
    uint32_t v = 0;
    int bits = 0;
    for (char c : text) {
        int d;
        if (c >= 'A' && c <= 'Z') d = c - 'A';
        else if (c >= 'a' && c <= 'z') d = c - 'a' + 26;
        else if (c >= '0' && c <= '9') d = c - '0' + 52;
        else if (c == '-') d = 62;
        else if (c == '_') d = 63;
        else return std::nullopt;
        v = v << 6 | (uint32_t)d;
        bits += 6;
        if (bits >= 8) { bits -= 8; out += (char)((v >> bits) & 0xFF); }
    }
    if (bits >= 6) return std::nullopt;
    return out;
}

inline std::string random_text(size_t count) {
    std::string out(count, '\0');
    platform::random_bytes(reinterpret_cast<uint8_t*>(out.data()), count);
    return out;
}

inline bool same(std::string_view a, std::string_view b) {
    if (a.size() != b.size()) return false;
    unsigned char diff = 0;
    for (size_t i = 0; i < a.size(); i++) diff |= (unsigned char)(a[i] ^ b[i]);
    return diff == 0;
}

inline std::string lower(std::string text) {
    std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) { return (char)std::tolower(c); });
    return text;
}

inline std::string trim(std::string_view text) {
    size_t a = 0, b = text.size();
    while (a < b && (text[a] == ' ' || text[a] == '\t')) a++;
    while (b > a && (text[b - 1] == ' ' || text[b - 1] == '\t')) b--;
    return std::string(text.substr(a, b - a));
}

// Which device a connection is from, for the limits on how many it may hold: an IPv4 address as it is, and an IPv6 one
// by its first four groups (its network), however it's written, since a device can take many addresses there.
inline std::string source_of(std::string address) {
    address = lower(address.substr(0, address.find('%')));
    if (address.find(':') == std::string::npos) return address;
    std::vector<std::string> head, tail;
    auto split = [](std::string const& text, std::vector<std::string>& into) {
        size_t start = 0;
        if (text.empty()) return;
        for (;;) {
            size_t colon = text.find(':', start);
            into.push_back(text.substr(start, colon == std::string::npos ? std::string::npos : colon - start));
            if (colon == std::string::npos) break;
            start = colon + 1;
        }
    };
    auto gap = address.find("::");
    split(gap == std::string::npos ? address : address.substr(0, gap), head);
    if (gap != std::string::npos) split(address.substr(gap + 2), tail);
    // An IPv4 tail ("::ffff:1.2.3.4") counts as its two groups.
    if (!tail.empty() && tail.back().find('.') != std::string::npos) { tail.back() = "0"; tail.push_back("0"); }
    else if (tail.empty() && !head.empty() && head.back().find('.') != std::string::npos) { head.back() = "0"; head.push_back("0"); }
    std::vector<std::string> groups = head;
    while (groups.size() + tail.size() < 8) groups.push_back("0");
    groups.insert(groups.end(), tail.begin(), tail.end());
    std::string out;
    for (size_t i = 0; i < 4 && i < groups.size(); i++) {
        std::string g = groups[i];
        size_t lead = g.find_first_not_of('0');
        g = lead == std::string::npos ? "0" : g.substr(lead);
        out += (i ? ":" : "") + g;
    }
    return out;
}

// MARK: Credentials

// ControllerToken: a short signed credential for one kind of holder in this session, signed with a key that lives only
// in the host's memory for the session.
//   host        the game's page, over the host's own link, never the network.
//   join        what a phone's link carries after the #: fifteen minutes.
//   controller  a phone's place once it has joined: two minutes, renewed while it stays.
namespace token {
enum class Kind { host, join, controller };
inline const char* name(Kind k) { return k == Kind::host ? "host" : k == Kind::join ? "join" : "controller"; }
inline int64_t lifetime_s(Kind k) { return k == Kind::host ? 12 * 3600 : k == Kind::join ? 15 * 60 : 2 * 60; }

struct Claim {
    Kind kind;
    std::optional<int> player;
};

inline std::string issue(Kind kind, std::string const& app, std::string_view key, std::optional<int> player = std::nullopt,
                         int64_t now_s = wall_ms() / 1000) {
    Json payload = Json::object();
    payload["k"] = name(kind);
    payload["a"] = app;
    payload["g"] = 0;
    payload["e"] = now_s + lifetime_s(kind);
    payload["n"] = base64(random_text(9), true);
    if (player) payload["p"] = *player;
    std::string body = base64(payload.dump(), true);
    auto mac = platform::hmac_sha256(key, body);
    return body + "." + base64(std::string_view(reinterpret_cast<const char*>(mac.data()), mac.size()), true);
}

inline std::optional<Claim> check(std::optional<std::string> const& credential, std::set<Kind> const& kinds, std::string const& app,
                                  std::string_view key, int64_t now_s = wall_ms() / 1000) {
    if (!credential || credential->size() > 1024) return std::nullopt;
    auto dot = credential->find('.');
    if (dot == std::string::npos || credential->find('.', dot + 1) != std::string::npos) return std::nullopt;
    std::string body = credential->substr(0, dot);
    auto signature = unbase64url(std::string_view(*credential).substr(dot + 1));
    auto mac = platform::hmac_sha256(key, body);
    if (!signature || !same(*signature, std::string_view(reinterpret_cast<const char*>(mac.data()), mac.size()))) return std::nullopt;
    auto plain = unbase64url(body);
    if (!plain) return std::nullopt;
    auto payload = Json::parse(*plain);
    if (!payload) return std::nullopt;
    auto k = payload->str("k");
    std::optional<Kind> kind;
    for (Kind each : { Kind::host, Kind::join, Kind::controller }) if (k && *k == name(each)) kind = each;
    if (!kind || !kinds.count(*kind) || payload->str("a") != app || payload->integer("g") != 0) return std::nullopt;
    auto expires = payload->integer("e");
    if (!expires || *expires <= now_s) return std::nullopt;
    auto p = payload->integer("p");
    return Claim{ *kind, p ? std::optional<int>((int)*p) : std::nullopt };
}
}

// MARK: The phone page

// PhonePageServer's answers: plain GETs of the page's files, from the game's package, asked for by one of the console's
// names or addresses (so a page elsewhere that made its own name lead here reads nothing), and lamp-relay.json, where
// lamp-controller.js opens its socket.
namespace page {
constexpr size_t head_limit = 16 * 1024;
constexpr int64_t head_deadline_ms = 10000;
constexpr size_t connection_limit_all = 64, connection_limit_each = 16;
constexpr size_t file_limit = 64 << 20;

struct Answer {
    int status = 200;
    std::string type = "text/plain; charset=utf-8";
    std::string body;
    bool head = false;
    // What the phone's browser holds the page to (PhonePagePolicy), sent with every answer.
    std::string policy = "";
};

// PhonePagePolicy's rules for the page, in the same words: nothing but the page's own files, the game's relay on the
// console by the name the phone used, at the port it listens on now, and the sites the app may reach, from
// lamp-reach.json, which Lamp writes beside the page (none when it's missing).
inline const std::string reach_file = "lamp-reach.json";

inline bool plain_host(std::string const& host) {
    if (host.empty() || host.size() > 253 || host.front() == '.' || host.back() == '.' || host.find("..") != std::string::npos) return false;
    return std::all_of(host.begin(), host.end(), [](char c) { return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '.'; });
}

inline std::optional<std::string> policy_source(std::string text) {
    std::string site = lower(trim(text));
    auto split = site.find("://");
    if (split == std::string::npos) return plain_host(site) ? std::optional(site) : std::nullopt;
    std::string scheme = site.substr(0, split);
    if (scheme != "http" && scheme != "https" && scheme != "ws" && scheme != "wss") return std::nullopt;
    std::string rest = site.substr(split + 3);
    if (!rest.empty() && rest.back() == '/') rest.pop_back();
    std::string host = rest;
    if (auto colon = rest.find(':'); colon != std::string::npos) {
        std::string port = rest.substr(colon + 1);
        if (port.empty() || port.size() > 5 || !std::all_of(port.begin(), port.end(), [](char c) { return c >= '0' && c <= '9'; })) return std::nullopt;
        host = rest.substr(0, colon);
    }
    return plain_host(host) ? std::optional(scheme + "://" + rest) : std::nullopt;
}

// The reach file's sites: nullopt for any secure site (an app the person made), else only those named.
inline std::optional<std::vector<std::string>> reach(std::optional<std::string> const& file) {
    std::vector<std::string> only;
    auto json = file ? Json::parse(*file) : std::nullopt;
    if (!json) return only;
    if (json->is_true("secureSites")) return std::nullopt;
    if (auto list = json->get("only"); list && list->type == Json::Type::array)
        for (auto const& item : list->a) if (item.type == Json::Type::string) only.push_back(item.s);
    return only;
}

inline std::string policy(std::optional<std::string> const& host, std::optional<uint16_t> relay_port,
                          std::optional<std::vector<std::string>> const& named) {
    std::vector<std::string> sites;
    if (!named) sites = { "https:" };
    else for (auto const& site : *named) if (auto source = policy_source(site)) sites.push_back(*source);
    std::string connect = "'self'";
    if (host) {
        std::string name = lower(trim(*host));
        if (!name.empty() && name[0] != '[') {
            name = name.substr(0, name.find(':'));
            if (plain_host(name) && relay_port) connect += " ws://" + name + ":" + std::to_string(*relay_port);
        }
    }
    if (!named) connect += " wss:";
    auto list = [&](std::string base) { for (auto const& site : sites) base += " " + site; return base; };
    return "default-src 'none'; script-src " + list("'self' 'unsafe-inline'") + "; style-src " + list("'self' 'unsafe-inline'")
        + "; img-src " + list("'self' data: blob:") + "; media-src " + list("'self' data: blob:") + "; font-src " + list("'self' data:")
        + "; connect-src " + list(connect) + "; worker-src 'self' blob:; manifest-src 'self'; base-uri 'none'; form-action 'none'";
}

inline std::string type_for(std::string ext) {
    ext = lower(ext);
    static const std::map<std::string, std::string> types = {
        { "html", "text/html; charset=utf-8" }, { "htm", "text/html; charset=utf-8" }, { "js", "text/javascript; charset=utf-8" },
        { "mjs", "text/javascript; charset=utf-8" }, { "css", "text/css; charset=utf-8" }, { "json", "application/json" },
        { "webmanifest", "application/json" }, { "svg", "image/svg+xml" }, { "png", "image/png" }, { "jpg", "image/jpeg" },
        { "jpeg", "image/jpeg" }, { "gif", "image/gif" }, { "webp", "image/webp" }, { "ico", "image/x-icon" }, { "woff2", "font/woff2" },
        { "woff", "font/woff" }, { "mp3", "audio/mpeg" }, { "wav", "audio/wav" }, { "mp4", "video/mp4" }, { "txt", "text/plain; charset=utf-8" } };
    auto found = types.find(ext);
    return found == types.end() ? "application/octet-stream" : found->second;
}

// Whether a Host header names one of `hosts`, with at most a numeric port after it.
inline bool names(std::optional<std::string> const& header, std::set<std::string> const& hosts) {
    if (!header) return false;
    std::string host = lower(trim(*header));
    if (host.empty()) return false;
    auto digits = [](std::string_view s) { return !s.empty() && std::all_of(s.begin(), s.end(), [](char c) { return c >= '0' && c <= '9'; }); };
    if (host[0] == '[') {
        auto close = host.find(']');
        if (close == std::string::npos) return false;
        std::string port = host.substr(close + 1);
        if (!port.empty() && !(port[0] == ':' && digits(std::string_view(port).substr(1)))) return false;
        host = host.substr(1, close - 1);
    } else if (auto colon = host.find(':'); colon != std::string::npos) {
        if (!digits(std::string_view(host).substr(colon + 1))) return false;
        host = host.substr(0, colon);
    }
    return hosts.count(host) > 0;
}

// A step of a path a page may serve: ControllerSnapshot.isServed's rule (a name, not hidden, not empty), and nothing
// Windows reads as something other than a file's own name: a stream (":"), a name it trims (a trailing dot or space), a
// device, or a short name ("HIDDEN~1"), which could name a file the long rules turn away.
inline bool served_step(std::string const& step) {
    if (step.empty() || step[0] == '.' || step.size() > 255) return false;
    for (size_t i = 0; i + 1 < step.size(); i++) if (step[i] == '~' && step[i + 1] >= '0' && step[i + 1] <= '9') return false;
    if (step.find_first_of(std::string("\\:\0", 3)) != std::string::npos) return false;
    if (step.back() == '.' || step.back() == ' ') return false;
    for (unsigned char c : step) if (c < 0x20) return false;
    std::string stem = lower(step.substr(0, step.find('.')));
    static const std::set<std::string> devices = { "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7",
                                                   "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9" };
    return !devices.count(stem);
}

inline std::optional<std::string> percent_decoded(std::string_view text) {
    std::string out;
    for (size_t i = 0; i < text.size(); i++) {
        if (text[i] != '%') { out += text[i]; continue; }
        if (i + 2 >= text.size()) return std::nullopt;
        auto hex = [](char c) -> int { return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1; };
        int hi = hex(text[i + 1]), lo = hex(text[i + 2]);
        if (hi < 0 || lo < 0) return std::nullopt;
        out += (char)(hi << 4 | lo);
        i += 2;
    }
    return out;
}

// Reads a file of the page by its steps, each already checked; nil when there's no such plain file.
using Reader = std::function<std::optional<std::string>(std::vector<std::string> const& steps)>;

inline Answer answer_path(std::string const& full, std::optional<std::string> const& host, std::set<std::string> const& hosts,
                          std::optional<uint16_t> relay_port, std::string const& app, Reader const& read) {
    if (!names(host, hosts)) return { 403, "text/plain; charset=utf-8", "Not for this host." };
    Answer missing{ 404, "text/plain; charset=utf-8", "Nothing here. Open the game first." };
    std::string path = full.substr(0, full.find('?'));
    if (path.empty() || path[0] != '/') return missing;
    std::vector<std::string> steps;
    size_t start = 1;
    for (;;) {
        size_t slash = path.find('/', start);
        auto decoded = percent_decoded(std::string_view(path).substr(start, slash == std::string::npos ? std::string::npos : slash - start));
        if (!decoded || decoded->find('/') != std::string::npos) return missing;
        steps.push_back(*decoded);
        if (slash == std::string::npos) break;
        start = slash + 1;
    }
    if (steps.back().empty()) steps.back() = "index.html";
    if (steps.size() == 1 && steps[0] == "lamp-relay.json") {
        if (!relay_port) return { 503, "text/plain; charset=utf-8", "The link for controllers isn't open." };
        Json body = Json::object();
        body["port"] = (int)*relay_port;
        body["app"] = app;
        return { 200, type_for("json"), body.dump() };
    }
    size_t length = 0;
    for (auto const& step : steps) { length += step.size() + 1; if (!served_step(step)) return missing; }
    if (length > 1024) return missing;
    auto data = read(steps);
    if (!data || data->size() > file_limit) return missing;
    auto dot = steps.back().rfind('.');
    return { 200, type_for(dot == std::string::npos ? "" : steps.back().substr(dot + 1)), std::move(*data) };
}

inline std::optional<std::string> header(std::vector<std::string> const& lines, std::string const& name) {
    for (size_t i = 1; i < lines.size(); i++) {
        auto colon = lines[i].find(':');
        if (colon != std::string::npos && lower(lines[i].substr(0, colon)) == name) return trim(std::string_view(lines[i]).substr(colon + 1));
    }
    return std::nullopt;
}

inline std::vector<std::string> lines_of(std::string_view head) {
    std::vector<std::string> lines;
    size_t start = 0;
    for (;;) {
        size_t end = head.find("\r\n", start);
        lines.emplace_back(head.substr(start, end == std::string_view::npos ? std::string_view::npos : end - start));
        if (end == std::string_view::npos) break;
        start = end + 2;
    }
    return lines;
}

// The answer to a request's head (its request line and headers, without the blank line).
inline Answer answer(std::string_view head, std::set<std::string> const& hosts, std::optional<uint16_t> relay_port,
                     std::string const& app, Reader const& read) {
    auto lines = lines_of(head);
    std::string const& first = lines[0];
    auto space = first.find(' ');
    if (space == std::string::npos) return { 400, "text/plain; charset=utf-8", "Bad request" };
    std::string method = first.substr(0, space);
    auto end = first.find(' ', space + 1);
    std::string target = first.substr(space + 1, end == std::string::npos ? std::string::npos : end - space - 1);
    if (method != "GET" && method != "HEAD") return { 405, "text/plain; charset=utf-8", "Not allowed" };
    auto host = header(lines, "host");
    auto page = answer_path(target, host, hosts, relay_port, app, read);
    page.head = method == "HEAD";
    if (names(host, hosts)) page.policy = policy(host, relay_port, reach(read({ reach_file })));
    return page;
}

inline std::string response(Answer const& page) {
    const char* reason = page.status == 200 ? "OK" : page.status == 400 ? "Bad Request" : page.status == 403 ? "Forbidden"
        : page.status == 404 ? "Not Found" : page.status == 405 ? "Method Not Allowed" : "Service Unavailable";
    std::string out = "HTTP/1.1 " + std::to_string(page.status) + " " + reason + "\r\nContent-Type: " + page.type
        + "\r\nContent-Length: " + std::to_string(page.body.size())
        + (page.policy.empty() ? "" : "\r\nContent-Security-Policy: " + page.policy)
        + "\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n";
    if (!page.head) out += page.body;
    return out;
}
}

// MARK: WebSocket

namespace ws {
enum Op : uint8_t { continuation = 0, text = 1, binary = 2, close = 8, ping = 9, pong = 10 };

inline std::string accept_key(std::string const& key) {
    auto digest = platform::sha1(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    return base64(std::string_view(reinterpret_cast<const char*>(digest.data()), digest.size()), false);
}

// A server's frame: never masked, never split.
inline std::string frame(uint8_t op, std::string_view payload) {
    std::string out;
    out += (char)(0x80 | op);
    if (payload.size() < 126) out += (char)payload.size();
    else if (payload.size() < 65536) { out += (char)126; out += (char)(payload.size() >> 8); out += (char)(payload.size() & 0xFF); }
    else { out += (char)127; for (int i = 7; i >= 0; i--) out += (char)((uint64_t)payload.size() >> (i * 8) & 0xFF); }
    out += payload;
    return out;
}

inline std::string close_frame(int code) {
    std::string payload;
    payload += (char)((code >> 8) & 0xFF);
    payload += (char)(code & 0xFF);
    return frame(close, payload);
}

inline bool valid_utf8(std::string_view s) {
    size_t i = 0;
    while (i < s.size()) {
        unsigned char c = s[i];
        size_t n = c < 0x80 ? 0 : (c >> 5) == 6 ? 1 : (c >> 4) == 14 ? 2 : (c >> 3) == 30 ? 3 : 9;
        if (n == 9 || i + n >= s.size()) return false;
        uint32_t cp = n == 0 ? c : n == 1 ? c & 0x1F : n == 2 ? c & 0x0F : c & 0x07;
        for (size_t k = 1; k <= n; k++) {
            if (i + k >= s.size() || ((unsigned char)s[i + k] >> 6) != 2) return false;
            cp = cp << 6 | ((unsigned char)s[i + k] & 0x3F);
        }
        if ((n == 1 && cp < 0x80) || (n == 2 && cp < 0x800) || (n == 3 && cp < 0x10000) || cp > 0x10FFFF || (cp >= 0xD800 && cp < 0xE000)) return false;
        i += n + 1;
    }
    return true;
}

// Reads a client's frames: each must be masked, and a message held to `limit` bytes. What it read is a message, a
// ping, a close, or a reason to let the socket go (a close code).
struct Reader {
    struct Event {
        enum Kind { message, ping, closed, failed } kind;
        uint8_t op = 0;
        std::string data;
        int code = 0;
    };
    size_t limit = wire::message_limit;
    std::string buffer;
    std::string partial;
    uint8_t partial_op = 0;

    // Takes what arrived; the events it completes, in order. Nothing more is read after a close or a failure.
    std::vector<Event> feed(std::string_view bytes) {
        std::vector<Event> events;
        buffer.append(bytes.data(), bytes.size());
        for (;;) {
            if (buffer.size() < 2) break;
            uint8_t b0 = buffer[0], b1 = buffer[1];
            bool fin = b0 & 0x80;
            uint8_t op = b0 & 0x0F;
            if (b0 & 0x70) return fail(events, 1002);
            if (!(b1 & 0x80)) return fail(events, 1002);
            uint64_t length = b1 & 0x7F;
            size_t at = 2;
            if (length == 126) {
                if (buffer.size() < 4) break;
                length = (uint8_t)buffer[2] << 8 | (uint8_t)buffer[3];
                at = 4;
            } else if (length == 127) {
                if (buffer.size() < 10) break;
                length = 0;
                for (int i = 0; i < 8; i++) length = length << 8 | (uint8_t)buffer[2 + i];
                at = 10;
            }
            bool control = op & 0x08;
            if (control && (length > 125 || !fin)) return fail(events, 1002);
            // Checked before anything is added to it, so a length near 2^64 can't wrap past the limit.
            if (!control && (length > limit || partial.size() > limit - length)) return fail(events, 1009);
            if (buffer.size() < at + 4 + length) break;
            const char* mask = buffer.data() + at;
            std::string payload = buffer.substr(at + 4, (size_t)length);
            for (size_t i = 0; i < payload.size(); i++) payload[i] ^= mask[i % 4];
            buffer.erase(0, at + 4 + (size_t)length);
            if (op == close) {
                int code = payload.size() >= 2 ? ((uint8_t)payload[0] << 8 | (uint8_t)payload[1]) : 1005;
                events.push_back({ Event::closed, op, {}, code });
                buffer.clear();
                return events;
            }
            if (op == ping) { events.push_back({ Event::ping, op, std::move(payload) }); continue; }
            if (op == pong) continue;
            if (op == continuation) {
                if (!partial_op) return fail(events, 1002);
                partial += payload;
            } else if (op == text || op == binary) {
                if (partial_op) return fail(events, 1002);
                partial_op = op;
                partial = std::move(payload);
            } else return fail(events, 1002);
            if (!fin) continue;
            if (partial_op == text && !valid_utf8(partial)) return fail(events, 1007);
            events.push_back({ Event::message, partial_op, std::move(partial) });
            partial.clear();
            partial_op = 0;
        }
        return events;
    }

    std::vector<Event> fail(std::vector<Event>& events, int code) {
        events.push_back({ Event::failed, 0, {}, code });
        buffer.clear();
        return events;
    }
};

struct Upgrade {
    std::string key;
    std::optional<std::string> origin;
};

// A request's head that asks for a WebSocket, nil for anything else.
inline std::optional<Upgrade> upgrade(std::string_view head) {
    auto lines = page::lines_of(head);
    if (lines[0].rfind("GET ", 0) != 0) return std::nullopt;
    auto key = page::header(lines, "sec-websocket-key");
    auto version = page::header(lines, "sec-websocket-version");
    auto up = page::header(lines, "upgrade");
    if (!key || key->empty() || key->size() > 64 || version != std::string("13") || !up || lower(*up) != "websocket") return std::nullopt;
    return Upgrade{ *key, page::header(lines, "origin") };
}

inline std::string accepted(std::string const& key) {
    return "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept_key(key) + "\r\n\r\n";
}

inline std::string refused(int status) {
    return "HTTP/1.1 " + std::to_string(status) + (status == 403 ? " Forbidden" : " Bad Request")
        + "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
}
}

// MARK: Peers

// One end the relay talks to: a phone's WebSocket, or the game's page over the host's own link.
struct Peer {
    virtual ~Peer() = default;
    virtual void send_text(std::string const& text) = 0;
    // Queues a piece of a file; false when the peer already has more waiting than it could ever be owed.
    virtual bool send_piece(std::string piece) = 0;
    virtual void close(int code) = 0;
    virtual bool is_open() const = 0;
    // Text not yet handed on: how far behind the other end is.
    virtual size_t pending_text() const = 0;
    int64_t heard = wall_ms();
    std::function<void(std::string const&)> on_text = [](std::string const&) {};
    std::function<void(std::string const&)> on_binary = [](std::string const&) {};
    std::function<void()> on_close = [] {};
};

// What a WebSocket is carried on: writes go one at a time, `done` called once each has gone (or failed), on the
// relay's thread; `shutdown` lets the socket go now.
struct Transport {
    virtual ~Transport() = default;
    virtual void write(std::string bytes, std::function<void(bool ok)> done) = 0;
    virtual void shutdown() = 0;
};

// RelayPeer: a WebSocket past its handshake. Text goes before any file's piece waiting, so a button pressed meanwhile
// waits behind one piece at most.
struct SocketPeer : Peer, std::enable_shared_from_this<SocketPeer> {
    static constexpr size_t text_limit_messages = 256, text_limit_bytes = 2 * 1024 * 1024;
    static constexpr size_t piece_limit = wire::players * wire::transfers * (wire::window + wire::chunk + wire::header);

    std::unique_ptr<Transport> transport;
    ws::Reader reader;
    bool open = true;
    bool writing = false;
    // Closing: the close frame is on its way, after which the socket goes; or since when, to let it go anyway.
    int64_t closing_since = 0;
    std::deque<std::string> texts;
    size_t text_bytes = 0;
    std::deque<std::string> pieces;
    size_t piece_bytes = 0;
    std::optional<int> closing_code;

    explicit SocketPeer(std::unique_ptr<Transport> t) : transport(std::move(t)) {}

    bool is_open() const override { return open; }
    size_t pending_text() const override { return texts.size(); }

    void send_text(std::string const& text) override { queue_text(ws::frame(ws::text, text)); }

    void queue_text(std::string framed) {
        if (!open) return;
        if (texts.size() >= text_limit_messages || text_bytes + framed.size() > text_limit_bytes) return close(4002);
        text_bytes += framed.size();
        texts.push_back(std::move(framed));
        pump();
    }

    bool send_piece(std::string piece) override {
        if (!open || piece_bytes + piece.size() > piece_limit) return false;
        piece_bytes += piece.size();
        pieces.push_back(std::move(piece));
        pump();
        return true;
    }

    void pump() {
        if (writing || !transport) return;
        std::string next;
        bool is_text = false;
        if (!texts.empty()) { next = std::move(texts.front()); texts.pop_front(); is_text = true; }
        else if (open && !pieces.empty()) { next = ws::frame(ws::binary, pieces.front()); piece_bytes -= pieces.front().size(); pieces.pop_front(); }
        else if (!open && closing_code) {
            std::string frame = ws::close_frame(*closing_code);
            closing_code.reset();
            writing = true;
            auto self = shared_from_this();
            transport->write(frame, [self](bool) { self->writing = false; self->finish(); });
            return;
        } else return;
        size_t size = next.size();
        writing = true;
        auto self = shared_from_this();
        transport->write(std::move(next), [self, is_text, size](bool ok) {
            self->writing = false;
            if (is_text) self->text_bytes -= std::min(self->text_bytes, size);
            if (!ok) return self->lost();
            self->pump();
        });
    }

    // Says why, and lets the socket go once that has gone (or, for a peer that has stopped reading, soon after: `tick`).
    void close(int code) override {
        if (!open) return;
        open = false;
        texts.clear();
        text_bytes = 0;
        pieces.clear();
        piece_bytes = 0;
        closing_code = code;
        closing_since = wall_ms();
        pump();
        on_close();
    }

    void finish() {
        if (transport) transport->shutdown();
        transport.reset();
    }

    // The socket went away under it.
    void lost() {
        bool was = open;
        open = false;
        texts.clear();
        pieces.clear();
        closing_code.reset();
        finish();
        if (was) on_close();
    }

    // A close that hasn't gone after two seconds lets the socket go anyway.
    void tick(int64_t now) {
        if (!open && transport && closing_since && now - closing_since > 2000) finish();
    }

    void received(std::string_view bytes) {
        if (!open) return;
        for (auto& event : reader.feed(bytes)) {
            if (!open) return;
            heard = wall_ms();
            switch (event.kind) {
            case ws::Reader::Event::message:
                if (event.op == ws::text) {
                    if (event.data.size() > wire::message) return close(1009);
                    on_text(event.data);
                } else on_binary(event.data);
                break;
            case ws::Reader::Event::ping:
                queue_text(ws::frame(ws::pong, event.data));
                break;
            case ws::Reader::Event::closed:
                return close(1000);
            case ws::Reader::Event::failed:
                return close(event.code);
            }
        }
    }
};

// MARK: The relay

// Relay's game part, for the one game this host runs: its page (the host, over the host's own link) and up to eight
// phones, each at a place 1…8. Phones send buttons, sticks and messages to the page, and files both ways in pieces with
// their own flow control; nothing is kept once it's passed on.
class Relay {
public:
    struct Transfer {
        int64_t size;
        int64_t passed = 0, acknowledged = 0, unacknowledged = 0;
        explicit Transfer(int64_t s) : size(s) {}
        bool acknowledge(int64_t got) {
            if (size == 0 && got == 0 && acknowledged == 0 && unacknowledged == 0) { unacknowledged = -1; return true; }
            if (got <= acknowledged || got > passed || unacknowledged <= 0) return false;
            acknowledged = got;
            unacknowledged -= 1;
            return true;
        }
    };

    // About as often as a screen draws; past that messages are dropped, and a peer that goes on for ten seconds goes.
    struct Rate {
        double tokens = wire::per_second;
        int64_t refilled;
        int64_t over = 0, last_dropped = 0;
        explicit Rate(int64_t now) : refilled(now) {}
        bool allowed(Peer* peer, int64_t now) {
            tokens = std::min(wire::per_second, tokens + (double)(now - refilled) / 1000.0 * wire::per_second);
            refilled = now;
            if (now - last_dropped > 2000) over = 0;
            if (tokens >= 1) { tokens -= 1; return true; }
            last_dropped = now;
            if (!over) over = now;
            if (now - over > 10000 && peer) peer->close(4008);
            return false;
        }
    };

    struct Player {
        std::shared_ptr<Peer> peer;
        int64_t held_until = 0;
        Rate rate;
        std::map<uint32_t, Transfer> to_host, to_phone;
        Player(std::shared_ptr<Peer> p, int64_t now) : peer(std::move(p)), rate(now) {}
    };

    static constexpr size_t greeting_all = 64, greeting_each = 8;
    static constexpr int64_t greeting_ms = 5000;
    static inline size_t host_behind = 128;

    std::function<int64_t()> now = [] { return wall_ms(); };

    Relay(std::string app, std::string key) : app_(std::move(app)), key_(std::move(key)) {}

    std::string const& app() const { return app_; }

    // Where the page is now: the address phones open, its port, and the console's names and addresses. A page that moved
    // is told its new link.
    void configure(std::optional<std::string> page, std::optional<uint16_t> page_port, std::set<std::string> hosts) {
        bool moved = page != page_;
        page_ = std::move(page);
        page_port_ = page_port;
        hosts_ = std::move(hosts);
        if (moved && host_) send_link();
    }

    // A browser always says which page opened a socket: only the game's own phone page, at its port, by one of the
    // console's names. A client that isn't a browser could say anything, so its credential is what lets it in.
    bool admits(std::optional<std::string> const& origin) const {
        if (!origin) return true;
        std::string o = lower(*origin);
        if (o.rfind("http://", 0) != 0) return false;
        std::string rest = o.substr(7);
        if (rest.find('/') != std::string::npos || rest.find('@') != std::string::npos) return false;
        size_t colon = rest.rfind(':');
        if (colon == std::string::npos || (rest[0] == '[' && colon < rest.find(']'))) return false;
        std::string port = rest.substr(colon + 1), host = rest.substr(0, colon);
        if (port.empty() || port.size() > 5 || !std::all_of(port.begin(), port.end(), [](char c) { return c >= '0' && c <= '9'; })) return false;
        if (host.size() > 2 && host.front() == '[' && host.back() == ']') host = host.substr(1, host.size() - 2);
        return page_port_ && std::stoi(port) == *page_port_ && hosts_.count(host);
    }

    std::string host_credential() const { return token::issue(token::Kind::host, app_, key_); }

    // A socket to hear from: false when too many wait to say hello, in all or from `from`. `trusted`: the page's own link
    // through the host, the only one that may be the game's host.
    bool accept(std::shared_ptr<Peer> peer, std::string const& from, bool trusted) {
        if (stopped_) return false;
        size_t mine = 0;
        for (auto const& g : greeting_) if (g.second.from == from) mine++;
        if (greeting_.size() >= greeting_all || mine >= greeting_each) return false;
        Peer* id = peer.get();
        greeting_[id] = { peer, from, now() };
        std::weak_ptr<Peer> weak = peer;
        peer->on_close = [this, id] { greeting_.erase(id); };
        peer->on_binary = [weak](std::string const&) { if (auto p = weak.lock()) p->close(4003); };
        peer->on_text = [this, id, weak, trusted](std::string const& text) {
            auto p = weak.lock();
            if (!p || !greeting_.count(id)) return;
            greeting_.erase(id);
            hello(p, text, trusted);
        };
        return true;
    }

    // Every second: hellos that never came, and every five seconds a beat on every socket (with the relay's time), fresh
    // credentials for the phones each minute, and sockets gone quiet let go.
    void tick() {
        int64_t t = now();
        std::vector<std::shared_ptr<Peer>> late;
        for (auto const& g : greeting_) if (t - g.second.since > greeting_ms) late.push_back(g.second.peer);
        for (auto& p : late) { greeting_.erase(p.get()); p->close(4001); }
        if (t - last_beat_ < wire::beat_ms) return;
        last_beat_ = t;
        Json b = Json::object();
        b["t"] = "beat";
        b["now"] = t;
        std::string beat = b.dump();
        bool renew = t - renewed_ >= 60000;
        if (renew) renewed_ = t;
        std::vector<int> gone;
        for (auto& [number, player] : players_) {
            if (!player.peer) { if (player.held_until < t) gone.push_back(number); continue; }
            auto peer = player.peer;
            if (t - peer->heard > wire::silence_ms) { peer->close(4002); continue; }
            peer->send_text(beat);
            if (renew) {
                Json c = Json::object();
                c["t"] = "credential";
                c["credential"] = token::issue(token::Kind::controller, app_, key_, number, t / 1000);
                peer->send_text(c.dump());
            }
        }
        for (int n : gone) players_.erase(n);
        if (host_) {
            if (t - host_->heard > wire::silence_ms) host_->close(4002);
            else host_->send_text(beat);
        }
    }

    // The session is over: every phone and the page are let go, and nothing more is taken.
    void stop() {
        stopped_ = true;
        std::vector<std::shared_ptr<Peer>> all;
        for (auto& [n, player] : players_) if (player.peer) all.push_back(player.peer);
        players_.clear();
        if (host_) all.push_back(host_);
        host_.reset();
        for (auto& p : all) { p->on_close = [] {}; p->close(4005); }
        std::vector<std::shared_ptr<Peer>> waiting;
        for (auto& g : greeting_) waiting.push_back(g.second.peer);
        greeting_.clear();
        for (auto& p : waiting) { p->on_close = [] {}; p->close(1001); }
    }

    // For tests and the log.
    std::vector<int> connected() const {
        std::vector<int> list;
        for (auto const& [n, player] : players_) if (player.peer) list.push_back(n);
        return list;
    }
    bool has_host() const { return host_ != nullptr; }

private:
    struct Waiting {
        std::shared_ptr<Peer> peer;
        std::string from;
        int64_t since;
    };

    std::string app_, key_;
    std::optional<std::string> page_;
    std::optional<uint16_t> page_port_;
    std::set<std::string> hosts_;
    std::map<Peer*, Waiting> greeting_;
    std::map<int, Player> players_;
    std::shared_ptr<Peer> host_;
    int64_t renewed_ = wall_ms(), last_beat_ = wall_ms();
    bool stopped_ = false;

    static std::optional<Json> parse(std::string const& text) {
        if (text.size() > wire::message) return std::nullopt;
        auto j = Json::parse(text);
        if (!j || j->type != Json::Type::object) return std::nullopt;
        return j;
    }
    static std::string shorter(Json const& m, std::string const& key, size_t limit) {
        auto s = m.str(key).value_or("");
        // Cut at a character's start, as Swift's prefix counts characters, so what's passed on stays UTF-8.
        if (s.size() <= limit) return s;
        size_t cut = limit;
        while (cut > 0 && ((unsigned char)s[cut] & 0xC0) == 0x80) cut--;
        return s.substr(0, cut);
    }
    static std::optional<uint32_t> id_of(Json const& m) {
        auto n = m.integer("id");
        if (!n || *n <= 0 || *n >= (int64_t(1) << 31)) return std::nullopt;
        return (uint32_t)*n;
    }
    static std::optional<std::pair<uint8_t, uint32_t>> chunk_header(std::string const& data) {
        if (data.size() < wire::header || (uint8_t)data[0] != 1) return std::nullopt;
        uint32_t id = 0;
        for (int i = 4; i < 8; i++) id = id << 8 | (uint8_t)data[i];
        return std::make_pair((uint8_t)data[1], id);
    }
    static std::string readdressed(std::string data, uint8_t player) {
        data[1] = (char)player;
        return data;
    }
    static Json msg(const char* t) {
        Json m = Json::object();
        m["t"] = t;
        return m;
    }

    void hello(std::shared_ptr<Peer> const& peer, std::string const& text, bool trusted) {
        auto m = parse(text);
        if (!m || m->str("t") != std::string("hello") || m->str("app") != app_) return peer->close(4003);
        std::set<token::Kind> kinds = { token::Kind::join, token::Kind::controller };
        if (trusted) kinds.insert(token::Kind::host);
        auto credential = m->get("credential");
        auto claim = token::check(credential && credential->type == Json::Type::string ? std::optional<std::string>(credential->s) : std::nullopt,
                                  kinds, app_, key_, now() / 1000);
        if (!claim) return peer->close(4003);
        if (claim->kind == token::Kind::host) return join_as_host(peer);
        join_as_player(peer, claim->kind == token::Kind::controller ? claim->player : std::nullopt);
    }

    void join_as_host(std::shared_ptr<Peer> const& peer) {
        if (auto old = host_) {
            old->on_close = [] {};
            old->close(4000);
            drop_transfers();
            for (auto& [n, player] : players_) if (player.peer) player.peer->send_text(R"({"host":false,"t":"state"})");
        }
        host_ = peer;
        Peer* raw = peer.get();
        peer->on_text = [this](std::string const& text) { if (auto m = parse(text)) from_host(*m); };
        peer->on_binary = [this](std::string const& data) { piece_from_host(data); };
        peer->on_close = [this, raw] {
            if (host_.get() != raw) return;
            host_.reset();
            drop_transfers();
            for (auto& [n, player] : players_) if (player.peer) player.peer->send_text(R"({"host":false,"t":"state"})");
        };
        Json welcome = msg("welcome");
        welcome["role"] = "host";
        Json list = Json::array();
        for (int n : connected()) list.a.push_back(n);
        welcome["players"] = list;
        welcome["now"] = now();
        peer->send_text(welcome.dump());
        for (auto& [n, player] : players_) if (player.peer) player.peer->send_text(R"({"host":true,"t":"state"})");
    }

    void join_as_player(std::shared_ptr<Peer> const& peer, std::optional<int> resuming) {
        int64_t t = now();
        std::optional<int> number = resuming;
        if (resuming && (*resuming < 1 || *resuming > wire::players)) return peer->close(4003);
        if (resuming) {
            auto found = players_.find(*resuming);
            if (found != players_.end() && found->second.peer) {
                auto old = found->second.peer;
                old->on_close = [] {};
                old->close(4000);
                if (host_) { Json left = msg("left"); left["player"] = *resuming; host_->send_text(left.dump()); }
            }
        }
        if (!number) {
            for (int n = 1; n <= wire::players; n++) {
                auto found = players_.find(n);
                if (found == players_.end() || (!found->second.peer && found->second.held_until < t)) { number = n; break; }
            }
        }
        if (!number) {
            peer->send_text(R"({"t":"full"})");
            return peer->close(4004);
        }
        int place = *number;
        players_.erase(place);
        auto& player = players_.emplace(place, Player(peer, t)).first->second;
        (void)player;
        Json welcome = msg("welcome");
        welcome["role"] = "controller";
        welcome["place"] = place;
        welcome["host"] = host_ != nullptr;
        welcome["credential"] = token::issue(token::Kind::controller, app_, key_, place, t / 1000);
        peer->send_text(welcome.dump());
        if (host_) { Json joined = msg("joined"); joined["player"] = place; host_->send_text(joined.dump()); }
        Peer* raw = peer.get();
        peer->on_text = [this, place, raw](std::string const& text) {
            auto found = players_.find(place);
            if (found != players_.end() && found->second.peer.get() == raw) from_player(place, found->second, text);
        };
        peer->on_binary = [this, place, raw](std::string const& data) {
            auto found = players_.find(place);
            if (found != players_.end() && found->second.peer.get() == raw) piece_from_player(place, found->second, data);
        };
        peer->on_close = [this, place, raw] {
            auto found = players_.find(place);
            if (found == players_.end() || found->second.peer.get() != raw) return;
            found->second.peer.reset();
            found->second.held_until = now() + token::lifetime_s(token::Kind::controller) * 1000;
            found->second.to_host.clear();
            found->second.to_phone.clear();
            if (host_) { Json left = msg("left"); left["player"] = place; host_->send_text(left.dump()); }
        };
    }

    void refuse(Player& player, uint32_t id, std::string const& reason) {
        if (!player.peer) return;
        Json r = msg("file-refuse");
        r["id"] = (int64_t)id;
        r["reason"] = reason;
        player.peer->send_text(r.dump());
    }

    void from_player(int number, Player& player, std::string const& text) {
        auto parsed = parse(text);
        if (!parsed) return;
        Json const& m = *parsed;
        std::string kind = m.str("t").value_or("");
        bool flow = kind == "file-ack" || kind == "file-cancel" || kind == "file-refuse";
        int64_t t = now();
        if (!flow && !player.rate.allowed(player.peer.get(), t)) return;
        if (!player.peer) return;
        if (!host_) {
            if (kind == "file") if (auto id = id_of(m)) refuse(player, *id, "The TV app isn't there.");
            return;
        }
        if (host_->pending_text() > host_behind && !flow && kind != "button") {
            if (kind == "file") if (auto id = id_of(m)) refuse(player, *id, "The TV app is busy; try again.");
            return;
        }
        auto seq = m.integer("seq").value_or(0);
        auto name = m.str("name");
        bool named = name && !name->empty() && name->size() <= 32
            && std::all_of(name->begin(), name->end(), [](char c) { return isalnum((unsigned char)c) || c == '_' || c == '-'; });
        if (kind == "button") {
            if (!named) return;
            Json out = msg("button");
            out["player"] = number; out["name"] = *name; out["down"] = m.is_true("down"); out["seq"] = seq; out["at"] = t;
            host_->send_text(out.dump());
        } else if (kind == "axis") {
            if (!named || host_->pending_text() > wire::backlog) return;
            auto clamp = [&](const char* key) {
                auto v = m.get(key);
                if (!v || v->type != Json::Type::number || !std::isfinite(v->n)) return 0.0;
                return std::max(-1.0, std::min(1.0, v->n));
            };
            Json out = msg("axis");
            out["player"] = number; out["name"] = *name; out["x"] = clamp("x"); out["y"] = clamp("y"); out["seq"] = seq; out["at"] = t;
            host_->send_text(out.dump());
        } else if (kind == "message") {
            auto data = m.get("data");
            if (!data) return;
            Json out = msg("message");
            out["player"] = number; out["data"] = *data; out["at"] = t;
            host_->send_text(out.dump());
        } else if (kind == "too-big") {
            auto bytes = m.integer("bytes");
            if (!bytes) return;
            Json out = msg("too-big");
            out["player"] = number; out["bytes"] = *bytes;
            host_->send_text(out.dump());
        } else if (kind == "file") {
            auto id = id_of(m);
            if (!id) return;
            auto size = m.integer("size");
            if (!size || *size < 0 || *size > wire::file) return refuse(player, *id, "The file is too big to send.");
            if (player.to_host.count(*id) || player.to_host.size() >= wire::transfers) return refuse(player, *id, "Another file is still on its way.");
            player.to_host.emplace(*id, Transfer(*size));
            Json out = msg("file");
            out["player"] = number; out["id"] = (int64_t)*id; out["name"] = shorter(m, "name", 200); out["type"] = shorter(m, "type", 100);
            out["size"] = *size; out["at"] = t;
            host_->send_text(out.dump());
        } else if (kind == "file-cancel") {
            auto id = id_of(m);
            if (!id || !player.to_host.erase(*id)) return;
            Json out = msg("file-cancel");
            out["player"] = number; out["id"] = (int64_t)*id;
            host_->send_text(out.dump());
        } else if (kind == "file-ack") {
            auto id = id_of(m);
            auto got = m.integer("got");
            if (!id || !got) return;
            auto found = player.to_phone.find(*id);
            if (found == player.to_phone.end() || !found->second.acknowledge(*got)) return;
            if (*got == found->second.size) player.to_phone.erase(found);
            Json out = msg("file-ack");
            out["player"] = number; out["id"] = (int64_t)*id; out["got"] = *got;
            host_->send_text(out.dump());
        } else if (kind == "file-refuse") {
            auto id = id_of(m);
            if (!id || !player.to_phone.erase(*id)) return;
            Json out = msg("file-refuse");
            out["player"] = number; out["id"] = (int64_t)*id; out["reason"] = shorter(m, "reason", 200);
            host_->send_text(out.dump());
        }
    }

    void piece_from_player(int number, Player& player, std::string const& data) {
        auto head = chunk_header(data);
        if (!head) return;
        auto found = player.to_host.find(head->second);
        if (found == player.to_host.end()) return;
        Transfer& transfer = found->second;
        int64_t bytes = (int64_t)data.size() - (int64_t)wire::header;
        if (!host_ || bytes <= 0 || transfer.passed + bytes > transfer.size
            || transfer.passed + bytes - transfer.acknowledged > wire::window + (int64_t)wire::chunk
            || !host_->send_piece(readdressed(data, (uint8_t)number))) {
            uint32_t id = head->second;
            player.to_host.erase(found);
            if (host_) { Json out = msg("file-cancel"); out["player"] = number; out["id"] = (int64_t)id; host_->send_text(out.dump()); }
            return refuse(player, id, "The file didn't keep to its size.");
        }
        transfer.passed += bytes;
        transfer.unacknowledged += 1;
    }

    void from_host(Json const& m) {
        int number = (int)m.integer("player").value_or(0);
        auto found = players_.find(number);
        Player* player = found == players_.end() ? nullptr : &found->second;
        std::string kind = m.str("t").value_or("");
        auto refuse_host = [&](uint32_t id, std::string const& reason) {
            if (!host_) return;
            Json out = msg("file-refuse");
            out["player"] = number; out["id"] = (int64_t)id; out["reason"] = reason;
            host_->send_text(out.dump());
        };
        if (kind == "link") {
            send_link();
        } else if (kind == "send") {
            auto data = m.get("data");
            if (!data) return;
            Json out = msg("message");
            out["data"] = *data;
            std::string text = out.dump();
            for (auto& [place, each] : players_) if ((number == 0 || number == place) && each.peer) each.peer->send_text(text);
        } else if (kind == "player") {
            auto shown = m.integer("number");
            if (!player || !player->peer || !shown || *shown <= 0 || *shown >= 1000) return;
            Json out = msg("player");
            out["number"] = *shown;
            player->peer->send_text(out.dump());
        } else if (kind == "file") {
            auto id = id_of(m);
            if (!id) return;
            auto size = m.integer("size");
            if (!player || !player->peer || !size || *size < 0 || *size > wire::file || player->to_phone.count(*id)
                || player->to_phone.size() >= wire::transfers) return refuse_host(*id, "The phone can't take it now.");
            player->to_phone.emplace(*id, Transfer(*size));
            Json out = msg("file");
            out["id"] = (int64_t)*id; out["name"] = shorter(m, "name", 200); out["type"] = shorter(m, "type", 100); out["size"] = *size;
            player->peer->send_text(out.dump());
        } else if (kind == "file-cancel") {
            auto id = id_of(m);
            if (!id || !player || !player->to_phone.erase(*id)) return;
            if (player->peer) { Json out = msg("file-cancel"); out["id"] = (int64_t)*id; player->peer->send_text(out.dump()); }
        } else if (kind == "file-ack") {
            auto id = id_of(m);
            auto got = m.integer("got");
            if (!id || !got || !player) return;
            auto transfer = player->to_host.find(*id);
            if (transfer == player->to_host.end() || !transfer->second.acknowledge(*got)) return;
            if (*got == transfer->second.size) player->to_host.erase(transfer);
            if (player->peer) { Json out = msg("file-ack"); out["id"] = (int64_t)*id; out["got"] = *got; player->peer->send_text(out.dump()); }
        } else if (kind == "file-refuse") {
            auto id = id_of(m);
            if (!id || !player || !player->to_host.erase(*id)) return;
            if (player->peer) { Json out = msg("file-refuse"); out["id"] = (int64_t)*id; out["reason"] = shorter(m, "reason", 200); player->peer->send_text(out.dump()); }
        }
    }

    void piece_from_host(std::string const& data) {
        auto head = chunk_header(data);
        if (!head) return;
        int number = head->first;
        auto found = players_.find(number);
        if (found == players_.end()) return;
        Player& player = found->second;
        auto transfer = player.to_phone.find(head->second);
        if (transfer == player.to_phone.end()) return;
        int64_t bytes = (int64_t)data.size() - (int64_t)wire::header;
        if (!player.peer || bytes <= 0 || transfer->second.passed + bytes > transfer->second.size
            || transfer->second.passed + bytes - transfer->second.acknowledged > wire::window + (int64_t)wire::chunk
            || !player.peer->send_piece(readdressed(data, 0))) {
            uint32_t id = head->second;
            player.to_phone.erase(transfer);
            if (player.peer) { Json out = msg("file-cancel"); out["id"] = (int64_t)id; player.peer->send_text(out.dump()); }
            if (host_) {
                Json out = msg("file-refuse");
                out["player"] = number; out["id"] = (int64_t)id; out["reason"] = "The file didn't keep to its size.";
                host_->send_text(out.dump());
            }
            return;
        }
        transfer->second.passed += bytes;
        transfer->second.unacknowledged += 1;
    }

    void drop_transfers() {
        for (auto& [n, player] : players_) { player.to_host.clear(); player.to_phone.clear(); }
    }

    // A link for phones: the page's address with a fresh join credential after the #.
    void send_link() {
        if (!page_ || !host_) return;
        Json out = msg("link");
        out["url"] = *page_ + "#" + token::issue(token::Kind::join, app_, key_, std::nullopt, now() / 1000);
        host_->send_text(out.dump());
    }
};

}  // namespace lampc
