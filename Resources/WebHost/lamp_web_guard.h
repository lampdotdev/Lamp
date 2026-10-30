// What a web app shared with the person may reach on the Xbox, decided in the app's own host (lamp_web_host.cpp) so it
// holds with Lamp closed: the app's own files at https://lamp.example/, and the exact sites (scheme, host and port) Lamp
// named on its safety sheet when the app was imported. Lamp writes those into the package as network-policy.json, beside
// the host and outside Web/, where the app's own files can't reach or change it (`WebHost.policy`).
//
// No policy file is an app the person made, which runs as it always has. A file that's there but can't be read, or
// that isn't one this host knows, guards the app with nothing listed.
//
// The host keeps to it in five places, all asking here: every request the page, its frames and its workers make (the
// host serves the app's files itself, each with the policy below as its Content-Security-Policy, and answers anything
// else not listed with a refusal), each navigation and new window, the web view's own connections (started so it
// connects only to listed sites), the http bridge to Lamp (only to Lamp's own addresses), and the ws bridge (only to
// listed sites, or to a relay Lamp's own answer named).
//
// Plain C++ with nothing of Windows in it, so the same rules run on a Mac too (scripts/check-web-host-guard.sh).
#pragma once
#include "lamp_controllers.h"

namespace lampg {

using lampc::Json;

constexpr const char* policy_file = "network-policy.json";
constexpr const char* own_origin = "https://lamp.example";
// The format of network-policy.json this host reads; WebHost.Policy.format on the Mac.
constexpr int64_t policy_format = 1;
// The most of a file one answer to a range carries: a video asked for from its start comes in pieces this size.
constexpr uint64_t range_piece = 8ull << 20;

// MARK: Origins

// A web address's origin as the policy lists it ("https://api.example.com", "http://192.168.1.5:7777"): http, https, ws
// or wss, the host lowercased, the port only when it isn't the scheme's own. Nil for anything else, and for an address
// written so that two readers could take it for different hosts (a name and password before it, a backslash, an escaped
// or unusual character in the host), which is never one the policy lists.
inline std::optional<std::string> origin_of(std::string_view url) {
    auto colon = url.find(':');
    if (colon == std::string_view::npos) return std::nullopt;
    std::string scheme = lampc::lower(std::string(url.substr(0, colon)));
    int standard = scheme == "http" || scheme == "ws" ? 80 : scheme == "https" || scheme == "wss" ? 443 : 0;
    if (!standard || url.substr(colon + 1, 2) != "//") return std::nullopt;
    std::string_view rest = url.substr(colon + 3);
    std::string_view authority = rest.substr(0, rest.find_first_of("/?#"));
    if (authority.find_first_of("@\\") != std::string_view::npos) return std::nullopt;
    std::string host;
    std::string_view port;
    if (!authority.empty() && authority[0] == '[') {
        auto close = authority.find(']');
        if (close == std::string_view::npos) return std::nullopt;
        host = lampc::lower(std::string(authority.substr(0, close + 1)));
        if (host.size() < 4 || host.find_first_not_of("[]0123456789abcdef:.") != std::string::npos) return std::nullopt;
        std::string_view after = authority.substr(close + 1);
        if (!after.empty() && after[0] != ':') return std::nullopt;
        if (!after.empty()) port = after.substr(1);
    } else {
        auto at = authority.find(':');
        host = lampc::lower(std::string(authority.substr(0, at)));
        if (host.empty() || host.find_first_not_of("abcdefghijklmnopqrstuvwxyz0123456789.-") != std::string::npos) return std::nullopt;
        if (at != std::string_view::npos) port = authority.substr(at + 1);
    }
    std::string out = scheme + "://" + host;
    if (!port.empty()) {
        if (port.size() > 5 || port.find_first_not_of("0123456789") != std::string_view::npos) return std::nullopt;
        int number = std::atoi(std::string(port).c_str());
        if (number < 1 || number > 65535) return std::nullopt;
        if (number != standard) out += ":" + std::to_string(number);
    }
    return out;
}

inline bool scheme_is(std::string_view url, std::string_view scheme) {
    return url.size() > scheme.size() && url[scheme.size()] == ':' && lampc::lower(std::string(url.substr(0, scheme.size()))) == scheme;
}

// MARK: The policy

struct Policy {
    bool guarded = false;
    // The sites the safety sheet named, as origins.
    std::set<std::string> origins;
    // Where Lamp on the Mac is (its gateway's addresses), the only places the http bridge goes for a guarded app.
    std::set<std::string> lamp;
    std::string own = own_origin;

    // From network-policy.json's text, or nil when the package has none.
    static Policy read(std::optional<std::string> const& file) {
        Policy policy;
        if (!file) return policy;
        policy.guarded = true;
        auto json = Json::parse(*file);
        if (!json || json->integer("format") != policy_format) return policy;
        // Only origins as this host writes them: anything else in a list is left out, never widened.
        auto take = [&](const char* key, std::set<std::string>& into, bool web_only) {
            auto list = json->get(key);
            if (!list || list->type != Json::Type::array) return;
            for (auto const& item : list->a) {
                if (item.type != Json::Type::string) continue;
                auto origin = origin_of(item.s);
                if (!origin || *origin != item.s || *origin == own_origin) continue;
                if (web_only && !scheme_is(*origin, "http")) continue;
                into.insert(*origin);
            }
        };
        take("origins", policy.origins, false);
        take("lamp", policy.lamp, true);
        return policy;
    }

    bool is_own(std::string_view url) const { auto o = origin_of(url); return o && *o == own; }
    bool listed(std::string_view url) const { auto o = origin_of(url); return o && origins.count(*o); }
};

// MARK: Requests

enum class Request { local, allowed, blocked };

// A request the page, a frame or a worker makes: the app's own files are the host's to serve, a listed site goes to the
// network, and so does what never leaves the page (data:, blob:, about:). Everything else is refused.
inline Request request(Policy const& policy, std::string_view url) {
    if (policy.is_own(url)) return Request::local;
    if (!policy.guarded) return Request::allowed;
    if (scheme_is(url, "data") || scheme_is(url, "blob") || scheme_is(url, "about")) return Request::allowed;
    return policy.listed(url) ? Request::allowed : Request::blocked;
}

enum class Navigation { stay, browser, refuse };

// Where a top-level navigation or a new window goes: the app's own pages stay in the web view, a website opens in the
// console's browser, and for a guarded app only a listed one does: opening any other is a request to it, its address
// carrying whatever the page put there.
inline Navigation navigation(Policy const& policy, std::string_view url) {
    if (policy.is_own(url) || url == "about:blank") return Navigation::stay;
    bool web = scheme_is(url, "http") || scheme_is(url, "https");
    if (!web) return Navigation::refuse;
    return !policy.guarded || policy.listed(url) ? Navigation::browser : Navigation::refuse;
}

// Whether a frame in the page may open this: its own pages, and what it makes for itself (blob:, about:), as
// NetworkPolicy.allowsFrame has it. A site the page may fetch from is never a frame of it: a page from there would run
// with none of these rules.
inline bool frame_may_open(Policy const& policy, std::string_view url) {
    if (!policy.guarded) return true;
    if (url == "about:blank" || url == "about:srcdoc" || scheme_is(url, "blob")) return true;
    return policy.is_own(url);
}

// MARK: The bridges

// The http bridge (lamp.js's calls to Lamp on the Mac): for a guarded app, only to Lamp's own addresses.
inline bool http_bridge(Policy const& policy, std::string_view url) {
    if (!policy.guarded) return true;
    auto origin = origin_of(url);
    return origin && policy.lamp.count(*origin);
}

// The ws bridge: for a guarded app, only to a listed site, or to a relay Lamp's own answer over the http bridge named
// (`sockets_in`), which is where a wish's room and phones held by Lamp are.
inline bool ws_bridge(Policy const& policy, std::string_view url, std::set<std::string> const& told) {
    if (!policy.guarded) return true;
    auto origin = origin_of(url);
    return origin && (policy.origins.count(*origin) || told.count(*origin));
}

// The relays an answer from Lamp names (/app/controller's links, /app/wish's socket), as origins. Only those two answers
// name one: any other (an AI's, which the page can steer) names nothing, whatever it holds.
inline std::set<std::string> sockets_in(std::string_view path, std::string_view body) {
    std::set<std::string> found;
    if (path != "/app/controller" && path != "/app/wish") return found;
    auto json = Json::parse(body);
    if (!json) return found;
    auto add = [&](Json const& j) {
        if (auto socket = j.str("socket"); socket && scheme_is(*socket, "ws")) if (auto o = origin_of(*socket)) found.insert(*o);
    };
    add(*json);
    if (auto links = json->get("links"); links && links->type == Json::Type::array) for (auto const& link : links->a) add(link);
    return found;
}

// MARK: What the page is told

// The page's Content-Security-Policy: its own files and the listed sites, nothing else, for every kind of request. The
// page's own scripts may run inline and as text (the safety sheet says so when they do); where they reach is what's held.
inline std::string csp(Policy const& policy) {
    std::string sites = "'self'";
    for (auto const& origin : policy.origins) sites += " " + origin;
    return "default-src " + sites + "; script-src " + sites + " 'unsafe-inline' 'unsafe-eval' blob:; style-src " + sites
        + " 'unsafe-inline'; img-src " + sites + " data: blob:; media-src " + sites + " data: blob:; font-src " + sites
        + " data:; connect-src " + sites + " data: blob:; worker-src 'self' blob:; frame-src 'self' blob:; child-src 'self' blob:;"
        + " object-src 'none'; base-uri 'self'; form-action 'self'; manifest-src 'self'";
}

// What the web view itself is started with for a guarded app, under the policy and the host's look at each request:
// a preconnect, or the warm-up of a navigation the host then refuses, opens a connection (and looks up its name) with no
// request either sees. Every connection but those to a listed site goes to a proxy that isn't there, so it goes
// nowhere, and its name is never looked up; loopback is no exception, as it is by default. WebRTC is held to that
// proxy too, which leaves it nothing.
inline std::string browser_arguments(Policy const& policy) {
    // Loopback's own exception goes first: after another entry Chromium keeps it.
    std::string direct = "<-loopback>";
    for (auto const& origin : policy.origins) {
        std::string authority = origin.substr(origin.find("//") + 2);
        bool bracketed = !authority.empty() && authority[0] == '[';
        bool ported = bracketed ? authority.find("]:") != std::string::npos : authority.find(':') != std::string::npos;
        if (!ported) authority += scheme_is(origin, "http") || scheme_is(origin, "ws") ? ":80" : ":443";
        direct += ";" + authority;
    }
    return "--proxy-server=http://127.0.0.1:9 --proxy-bypass-list=" + direct + " --force-webrtc-ip-handling-policy=disable_non_proxied_udp";
}

// Run in every frame before the page's own scripts: WebRTC reaches whatever server it's given, past both the policy and
// the host's look at each request, so a guarded page has none.
inline const char* no_webrtc_script() {
    return "(function(){for(var n of ['RTCPeerConnection','webkitRTCPeerConnection','RTCDataChannel','RTCIceCandidate',"
           "'RTCSessionDescription','RTCRtpSender','RTCRtpReceiver','RTCRtpTransceiver']){try{Object.defineProperty(window,n,"
           "{value:undefined,writable:false,configurable:false});}catch(e){}}})();";
}

// MARK: The app's own files

// The steps of one of the app's files under Web/ from its address, each a plain name Windows reads as itself
// (`lampc::page::served_step`); a folder's address is its index.html. Nil for anything else.
inline std::optional<std::vector<std::string>> steps(Policy const& policy, std::string_view url) {
    if (!policy.is_own(url)) return std::nullopt;
    std::string_view rest = url.substr(url.find("//") + 2);
    auto slash = rest.find('/');
    std::string_view path = slash == std::string_view::npos ? std::string_view("/") : rest.substr(slash);
    path = path.substr(0, path.find_first_of("?#"));
    std::vector<std::string> out;
    size_t start = 1;
    for (;;) {
        size_t next = path.find('/', start);
        auto decoded = lampc::page::percent_decoded(path.substr(start, next == std::string_view::npos ? std::string_view::npos : next - start));
        if (!decoded || decoded->find_first_of("/\\") != std::string::npos) return std::nullopt;
        out.push_back(*decoded);
        if (next == std::string_view::npos) break;
        start = next + 1;
    }
    if (out.back().empty()) out.back() = "index.html";
    for (auto const& step : out) {
        if (!lampc::page::served_step(step)) return std::nullopt;
        // Devices Windows also opens by name, beyond the ones served_step knows: the console's, the clock, and the ports
        // written with a superscript digit.
        std::string stem = lampc::lower(step.substr(0, step.find('.')));
        if (stem == "conin$" || stem == "conout$" || stem == "clock$") return std::nullopt;
        if (stem.size() == 5 && (stem.rfind("com", 0) == 0 || stem.rfind("lpt", 0) == 0) && (unsigned char)stem[3] == 0xC2
            && ((unsigned char)stem[4] == 0xB9 || (unsigned char)stem[4] == 0xB2 || (unsigned char)stem[4] == 0xB3)) return std::nullopt;
    }
    return out;
}

inline std::string type_for(std::string const& name) {
    auto dot = name.rfind('.');
    std::string ext = dot == std::string::npos ? "" : lampc::lower(name.substr(dot + 1));
    static const std::map<std::string, std::string> more = {
        { "wasm", "application/wasm" }, { "glb", "model/gltf-binary" }, { "gltf", "model/gltf+json" }, { "bin", "application/octet-stream" },
        { "ogg", "audio/ogg" }, { "oga", "audio/ogg" }, { "m4a", "audio/mp4" }, { "aac", "audio/aac" }, { "flac", "audio/flac" },
        { "webm", "video/webm" }, { "m4v", "video/mp4" }, { "ttf", "font/ttf" }, { "otf", "font/otf" }, { "xml", "application/xml" },
        { "csv", "text/csv; charset=utf-8" }, { "md", "text/markdown; charset=utf-8" }, { "avif", "image/avif" }, { "vtt", "text/vtt" } };
    auto found = more.find(ext);
    return found != more.end() ? found->second : lampc::page::type_for(ext);
}

struct Range {
    uint64_t offset = 0, length = 0;
    bool partial = false;
};

// The part of a file of `size` bytes a request asks for with its Range header ("bytes=a-b", "bytes=a-", "bytes=-n"): all
// of it when it asks for none or for several parts, and nil when the part is past the end.
inline std::optional<Range> range(std::optional<std::string> const& header, uint64_t size) {
    Range all{ 0, size, false };
    if (!header) return all;
    std::string text = lampc::trim(*header);
    if (lampc::lower(text.substr(0, 6)) != "bytes=" || text.find(',') != std::string::npos) return all;
    text = lampc::trim(text.substr(6));
    auto dash = text.find('-');
    if (dash == std::string::npos) return all;
    std::string first = lampc::trim(text.substr(0, dash)), last = lampc::trim(text.substr(dash + 1));
    auto digits = [](std::string const& s) { return !s.empty() && s.size() <= 19 && s.find_first_not_of("0123456789") == std::string::npos; };
    if ((!first.empty() && !digits(first)) || (!last.empty() && !digits(last)) || (first.empty() && last.empty())) return all;
    uint64_t start, end;
    if (first.empty()) {
        uint64_t tail = std::stoull(last);
        if (tail == 0) return std::nullopt;
        start = tail >= size ? 0 : size - tail;
        end = size;
    } else {
        start = std::stoull(first);
        if (start >= size) return std::nullopt;
        end = last.empty() ? size : std::min<uint64_t>(std::stoull(last) + 1, size);
        if (end <= start) return std::nullopt;
    }
    end = std::min<uint64_t>(end, start + range_piece);
    return Range{ start, end - start, true };
}

struct Head {
    int status = 200;
    std::string reason = "OK";
    std::vector<std::pair<std::string, std::string>> headers;
};

// The head of the answer with one of the app's files, or a part of it: a guarded app's carries the policy on every one.
inline Head local_head(Policy const& policy, std::string const& name, uint64_t size, Range const& part) {
    Head head;
    if (part.partial) { head.status = 206; head.reason = "Partial Content"; }
    head.headers = { { "Content-Type", type_for(name) }, { "Content-Length", std::to_string(part.length) },
                     { "Accept-Ranges", "bytes" }, { "Cache-Control", "no-cache" } };
    if (policy.guarded) head.headers.insert(head.headers.end(), { { "Content-Security-Policy", csp(policy) }, { "X-DNS-Prefetch-Control", "off" } });
    if (part.partial)
        head.headers.push_back({ "Content-Range", "bytes " + std::to_string(part.offset) + "-" + std::to_string(part.offset + part.length - 1) + "/" + std::to_string(size) });
    return head;
}

inline Head refusal(Policy const& policy, int status, std::string reason) {
    Head head;
    head.status = status;
    head.reason = std::move(reason);
    head.headers = { { "Content-Type", "text/plain; charset=utf-8" }, { "Content-Length", "0" } };
    if (policy.guarded) head.headers.push_back({ "Content-Security-Policy", csp(policy) });
    return head;
}

// A request to a site the policy doesn't list.
inline Head blocked(Policy const& policy) { return refusal(policy, 403, "Not one of this app's sites"); }

}
