// The Xbox host's phones (lamp_controllers.h) on a Mac, for scripts/check-web-host-controllers.sh: the same protocol
// over POSIX sockets in place of the console's StreamSocketListener, with the page's link over stdin and stdout (one
// JSON line each way) in place of WebView2's pipe. Only a check of the protocol: what runs on a console is the host.
//
// stdin:  {"op":"start"} {"op":"stop"} {"op":"open"} {"op":"send","text":…} {"op":"send","data":base64} {"op":"close"}
// stdout: {"ev":"session","status":…,"body":…} {"ev":"open"} {"ev":"message","text"|"data":…} {"ev":"close","code":…}
#include "../../Resources/WebHost/lamp_controllers.h"
#include <CommonCrypto/CommonDigest.h>
#include <CommonCrypto/CommonHMAC.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>
#include <iostream>

namespace lampc::platform {
void random_bytes(uint8_t* out, size_t count) { arc4random_buf(out, count); }
std::array<uint8_t, 32> hmac_sha256(std::string_view key, std::string_view data) {
    std::array<uint8_t, 32> out{};
    CCHmac(kCCHmacAlgSHA256, key.data(), key.size(), data.data(), data.size(), out.data());
    return out;
}
std::array<uint8_t, 20> sha1(std::string_view data) {
    std::array<uint8_t, 20> out{};
    CC_SHA1(data.data(), (CC_LONG)data.size(), out.data());
    return out;
}
}

using namespace lampc;

static void emit(Json const& j) { std::cout << j.dump() << "\n" << std::flush; }

struct Conn;
static std::vector<std::shared_ptr<Conn>> conns;

struct FdTransport : Transport {
    int fd;
    std::deque<std::pair<std::string, std::function<void(bool)>>> out;
    size_t at = 0;
    explicit FdTransport(int f) : fd(f) {}
    void write(std::string bytes, std::function<void(bool)> done) override { out.emplace_back(std::move(bytes), std::move(done)); }
    void shutdown() override { if (fd >= 0) { ::shutdown(fd, SHUT_RDWR); } }
};

struct Conn {
    int fd = -1;
    bool relay = false, answered = false, close_after = false, dead = false;
    std::string buffer, out;
    int64_t since = wall_ms();
    std::shared_ptr<SocketPeer> peer;
    FdTransport* transport = nullptr;
};

struct LinkPeer : Peer {
    bool open = true;
    bool is_open() const override { return open; }
    size_t pending_text() const override { return 0; }
    void send_text(std::string const& text) override { if (!open) return; Json e = Json::object(); e["ev"] = "message"; e["text"] = text; emit(e); }
    bool send_piece(std::string piece) override {
        if (!open) return false;
        Json e = Json::object(); e["ev"] = "message"; e["data"] = base64(piece, false); emit(e);
        return true;
    }
    void close(int code) override {
        if (!open) return;
        open = false;
        Json e = Json::object(); e["ev"] = "close"; e["code"] = code; emit(e);
        on_close();
    }
};

static std::unique_ptr<Relay> phones;
static std::string key, root;
static int relay_fd = -1, page_fd = -1;
static uint16_t relay_port = 0, page_port = 0;
static std::shared_ptr<LinkPeer> page_link;
static const std::set<std::string> hosts = { "127.0.0.1", "localhost" };

static int listen_any(uint16_t& port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    sockaddr_in a{};
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind(fd, (sockaddr*)&a, sizeof a);
    listen(fd, 64);
    socklen_t n = sizeof a;
    getsockname(fd, (sockaddr*)&a, &n);
    port = ntohs(a.sin_port);
    fcntl(fd, F_SETFL, O_NONBLOCK);
    return fd;
}

static void stop() {
    if (phones) { phones->stop(); phones.reset(); }
    page_link.reset();
    if (relay_fd >= 0) close(relay_fd);
    if (page_fd >= 0) close(page_fd);
    relay_fd = page_fd = -1;
    key.clear();
}

static void start() {
    Json e = Json::object();
    e["ev"] = "session";
    struct stat st;
    if (stat((root + "/index.html").c_str(), &st) != 0) { e["status"] = 409; emit(e); return; }
    if (!phones) {
        key = random_text(32);
        phones = std::make_unique<Relay>("game.test", key);
        relay_fd = listen_any(relay_port);
        page_fd = listen_any(page_port);
    }
    phones->configure("http://127.0.0.1:" + std::to_string(page_port) + "/", page_port, hosts);
    Json body = Json::object();
    Json relay = Json::object();
    relay["kind"] = "relay"; relay["socket"] = "ws://lamp-controllers.invalid/"; relay["app"] = "game.test"; relay["credential"] = phones->host_credential();
    body["links"] = Json::array();
    body["links"].a.push_back(relay);
    body["renew"] = 15;
    e["status"] = 200;
    e["body"] = body;
    e["relayPort"] = (int)relay_port;
    e["pagePort"] = (int)page_port;
    emit(e);
}

static std::optional<std::string> file(std::vector<std::string> const& steps) {
    std::string path = root;
    for (auto const& s : steps) path += "/" + s;
    struct stat st;
    if (lstat(path.c_str(), &st) != 0 || !S_ISREG(st.st_mode)) return std::nullopt;
    FILE* f = fopen(path.c_str(), "rb");
    std::string out(st.st_size, '\0');
    fread(out.data(), 1, out.size(), f);
    fclose(f);
    return out;
}

static void heard(std::shared_ptr<Conn> const& c, std::string_view bytes) {
    if (c->peer) return c->peer->received(bytes);
    if (c->answered) return;
    c->buffer.append(bytes);
    auto end = c->buffer.find("\r\n\r\n");
    if (end == std::string::npos) return;
    std::string head = c->buffer.substr(0, end), rest = c->buffer.substr(end + 4);
    c->answered = true;
    if (!phones) { c->dead = true; return; }
    if (!c->relay) { c->out += page::response(page::answer(head, hosts, relay_port, "game.test", file)); c->close_after = true; return; }
    auto up = ws::upgrade(head);
    if (!up) { c->out += ws::refused(400); c->close_after = true; return; }
    if (!phones->admits(up->origin)) { c->out += ws::refused(403); c->close_after = true; return; }
    auto t = std::make_unique<FdTransport>(c->fd);
    c->transport = t.get();
    c->peer = std::make_shared<SocketPeer>(std::move(t));
    if (!phones->accept(c->peer, source_of("127.0.0.1"), false)) { c->dead = true; return; }
    c->peer->queue_text(ws::accepted(up->key));
    if (!rest.empty()) c->peer->received(rest);
}

static void command(std::string const& line) {
    auto m = Json::parse(line);
    if (!m) return;
    auto op = m->str("op").value_or("");
    if (op == "start") return start();
    if (op == "stop") { stop(); Json e = Json::object(); e["ev"] = "stopped"; return emit(e); }
    if (op == "open") {
        if (!phones || page_link) { Json e = Json::object(); e["ev"] = "close"; e["code"] = 1006; return emit(e); }
        page_link = std::make_shared<LinkPeer>();
        if (!phones->accept(page_link, "page", true)) { page_link.reset(); Json e = Json::object(); e["ev"] = "close"; e["code"] = 1006; return emit(e); }
        Json e = Json::object(); e["ev"] = "open"; return emit(e);
    }
    if (op == "close") { if (page_link) { auto l = page_link; page_link.reset(); l->open = false; l->on_close(); } return; }
    if (op == "send" && page_link) {
        auto l = page_link;
        l->heard = wall_ms();
        if (auto t = m->str("text")) l->on_text(*t);
        if (auto d = m->str("data")) {
            // Plain base64 back to bytes.
            std::string s = *d;
            for (auto& ch : s) { if (ch == '+') ch = '-'; else if (ch == '/') ch = '_'; }
            while (!s.empty() && s.back() == '=') s.pop_back();
            if (auto bytes = unbase64url(s)) l->on_binary(*bytes);
        }
    }
}

int main(int argc, char** argv) {
    if (argc < 2) return 2;
    root = argv[1];
    signal(SIGPIPE, SIG_IGN);
    fcntl(0, F_SETFL, O_NONBLOCK);
    std::string input;
    int64_t last_tick = wall_ms();
    for (;;) {
        std::vector<pollfd> fds = { { 0, POLLIN, 0 } };
        if (relay_fd >= 0) fds.push_back({ relay_fd, POLLIN, 0 });
        if (page_fd >= 0) fds.push_back({ page_fd, POLLIN, 0 });
        size_t first = fds.size();
        for (auto& c : conns) {
            short want = POLLIN;
            if (!c->out.empty() || (c->transport && !c->transport->out.empty())) want |= POLLOUT;
            fds.push_back({ c->fd, want, 0 });
        }
        poll(fds.data(), fds.size(), 100);
        if (fds[0].revents & (POLLIN | POLLHUP)) {
            char b[65536];
            ssize_t n = read(0, b, sizeof b);
            if (n == 0) return 0;
            if (n > 0) input.append(b, n);
            size_t nl;
            while ((nl = input.find('\n')) != std::string::npos) { std::string line = input.substr(0, nl); input.erase(0, nl + 1); command(line); }
        }
        for (size_t i = 1; i < first; i++) {
            if (!(fds[i].revents & POLLIN)) continue;
            int fd = accept(fds[i].fd, nullptr, nullptr);
            if (fd < 0) continue;
            fcntl(fd, F_SETFL, O_NONBLOCK);
            auto c = std::make_shared<Conn>();
            c->fd = fd;
            c->relay = fds[i].fd == relay_fd;
            conns.push_back(c);
        }
        for (size_t i = first; i < fds.size(); i++) {
            auto c = conns[i - first];
            if (fds[i].revents & POLLOUT) {
                if (!c->out.empty()) { ssize_t n = write(c->fd, c->out.data(), c->out.size()); if (n > 0) c->out.erase(0, n); }
                else if (c->transport && !c->transport->out.empty()) {
                    auto& front = c->transport->out.front();
                    ssize_t n = write(c->fd, front.first.data() + c->transport->at, front.first.size() - c->transport->at);
                    if (n > 0) c->transport->at += n;
                    if (n < 0 && errno != EAGAIN) { auto done = front.second; c->transport->out.clear(); done(false); }
                    else if (c->transport->at == front.first.size()) { auto done = front.second; c->transport->out.pop_front(); c->transport->at = 0; done(true); }
                }
                if (c->close_after && c->out.empty()) c->dead = true;
            }
            if (fds[i].revents & (POLLIN | POLLHUP | POLLERR)) {
                char b[16384];
                ssize_t n = read(c->fd, b, sizeof b);
                if (n <= 0) c->dead = true;
                else heard(c, std::string_view(b, n));
            }
            if (c->peer && !c->peer->transport) c->dead = true;
        }
        for (auto& c : std::vector<std::shared_ptr<Conn>>(conns)) {
            if (!c->dead) continue;
            if (c->peer) { c->transport = nullptr; c->peer->lost(); }
            close(c->fd);
            conns.erase(std::find(conns.begin(), conns.end(), c));
        }
        if (wall_ms() - last_tick >= 1000) {
            last_tick = wall_ms();
            if (phones) phones->tick();
            for (auto& c : conns) if (c->peer) c->peer->tick(last_tick);
        }
    }
}
