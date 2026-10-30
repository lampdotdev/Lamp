// The Xbox host's network guard (lamp_web_guard.h) on a Mac, for scripts/check-web-host-guard.sh: each question the
// host asks of it, over stdin and stdout (one JSON line each way) in place of WebView2's events, with the app's files
// read from a folder in place of the package's Web/. Only a check of the rules: what runs on a console is the host.
//
// argv: the Web folder, and network-policy.json's path ("-" for a package with none).
// stdin:  {"id":…,"op":"request","url":…,"range":…} {"op":"navigate","url":…} {"op":"frame","url":…}
//         {"op":"http","url":…} {"op":"ws","url":…} {"op":"told","path":…,"body":…} {"op":"script"} (with the web view's arguments)
// stdout: {"id":…,"verdict":…,"status":…,"headers":{…},"body":base64} and the like, one per line.
#include "../../Resources/WebHost/lamp_web_guard.h"
#include <sys/stat.h>
#include <iostream>

namespace lampc::platform {
void random_bytes(uint8_t* out, size_t count) { arc4random_buf(out, count); }
std::array<uint8_t, 32> hmac_sha256(std::string_view, std::string_view) { return {}; }
std::array<uint8_t, 20> sha1(std::string_view) { return {}; }
}

using lampc::Json;

static std::optional<std::string> slurp(std::string const& path) {
    FILE* file = fopen(path.c_str(), "rb");
    if (!file) return std::nullopt;
    std::string out;
    char buffer[65536];
    size_t n;
    while ((n = fread(buffer, 1, sizeof buffer, file)) > 0) out.append(buffer, n);
    fclose(file);
    return out;
}

static Json head_json(lampg::Head const& head) {
    Json out = Json::object();
    out["status"] = head.status;
    Json headers = Json::object();
    for (auto const& [name, value] : head.headers) headers[name] = value;
    out["headers"] = headers;
    return out;
}

int main(int argc, char** argv) {
    if (argc < 3) { std::cerr << "usage: guard_host WEB POLICY|-\n"; return 2; }
    std::string web = argv[1];
    std::string policy_path = argv[2];
    auto policy = lampg::Policy::read(policy_path == "-" ? std::nullopt : std::optional<std::string>(slurp(policy_path).value_or("")));
    std::set<std::string> told;
    std::string line;
    while (std::getline(std::cin, line)) {
        auto m = Json::parse(line);
        if (!m) continue;
        std::string op = m->str("op").value_or(""), url = m->str("url").value_or("");
        Json out = Json::object();
        if (auto id = m->get("id")) out["id"] = *id;
        if (op == "request") {
            auto verdict = lampg::request(policy, url);
            out["verdict"] = verdict == lampg::Request::local ? "local" : verdict == lampg::Request::allowed ? "allowed" : "blocked";
            if (verdict == lampg::Request::blocked) {
                Json head = head_json(lampg::blocked(policy));
                head["verdict"] = "blocked";
                out = head;
                if (auto id = m->get("id")) out["id"] = *id;
            } else if (verdict == lampg::Request::local) {
                // What the host does with one of the app's files: its steps, the file, the part asked for, the policy.
                auto steps = lampg::steps(policy, url);
                std::optional<std::string> data;
                std::string path = web;
                if (steps) {
                    for (auto const& step : *steps) path += "/" + step;
                    struct stat info{};
                    if (stat(path.c_str(), &info) == 0 && S_ISREG(info.st_mode)) data = slurp(path);
                }
                lampg::Head head;
                std::string body;
                if (!data) head = lampg::refusal(policy, 404, "Not Found");
                else if (auto part = lampg::range(m->str("range"), data->size())) {
                    head = lampg::local_head(policy, steps->back(), data->size(), *part);
                    body = data->substr(part->offset, part->length);
                } else head = lampg::refusal(policy, 416, "Range Not Satisfiable");
                Json answer = head_json(head);
                answer["verdict"] = "local";
                answer["body"] = lampc::base64(body, false);
                if (auto id = m->get("id")) answer["id"] = *id;
                out = answer;
            }
        } else if (op == "navigate") {
            auto where = lampg::navigation(policy, url);
            out["where"] = where == lampg::Navigation::stay ? "stay" : where == lampg::Navigation::browser ? "browser" : "refuse";
        } else if (op == "frame") {
            out["ok"] = lampg::frame_may_open(policy, url);
        } else if (op == "http") {
            out["ok"] = lampg::http_bridge(policy, url);
        } else if (op == "ws") {
            out["ok"] = lampg::ws_bridge(policy, url, told);
        } else if (op == "told") {
            for (auto const& origin : lampg::sockets_in(m->str("path").value_or(""), m->str("body").value_or(""))) told.insert(origin);
            out["told"] = (int)told.size();
        } else if (op == "script") {
            out["script"] = policy.guarded ? lampg::no_webrtc_script() : "";
            out["arguments"] = policy.guarded ? lampg::browser_arguments(policy) : "";
        } else if (op == "origin") {
            auto origin = lampg::origin_of(url);
            out["origin"] = origin ? Json(*origin) : Json();
        } else if (op == "policy") {
            out["guarded"] = policy.guarded;
            Json list = Json::array();
            for (auto const& o : policy.origins) list.a.push_back(o);
            out["origins"] = list;
            out["csp"] = lampg::csp(policy);
        }
        std::cout << out.dump() << "\n" << std::flush;
    }
    return 0;
}
