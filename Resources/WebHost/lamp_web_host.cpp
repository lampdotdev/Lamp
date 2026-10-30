// Lamp's web host on the Xbox: the same program for every web app, beside the app's Web/ folder in its package.
//
// A full-screen CoreWindow holding a WebView2 (Chromium, which the console keeps up to date) that shows Web/index.html
// from the package, served at https://lamp.example/ by WebView2's own mapping of a host name to a folder (by the host
// itself for a shared app, below), so pages load their files with fetch as they would from a site. No XAML: the page
// is drawn into a composition visual, as WinUI's control does it. The page's console, its uncaught errors, text it
// posts with chrome.webview.postMessage and what the host itself has to say go to log.txt in the app's own folder,
// which Device Portal reads back.
//
// lamp.js reaches Lamp on the Mac through the host (`http` messages): the page is https and Lamp's gateway plain http
// on the home network, which Chromium won't let the page call itself. Only the app's own page may ask, only Lamp's own
// paths are passed on, and an answer goes only to the page that asked: the app's token and its AI's answers are in
// them. A link to anywhere else opens in the console's browser (for a shared app, only one to a site it was shared
// with), never in this web view.
//
// A game's or a screen's page that's one of a wish's apps talks to the others over plain ws:// links (to Lamp's relay
// room, and straight to the apps that listen), which an https page may not open. The host opens them for the page and
// passes each frame both ways as it is (`ws` messages), while the page keeps the wish's handshake and seals: the host
// never holds the wish's key and can't read what goes. Only the app's own page may ask, and only for a ws:// link to
// this network (a private or link-local address, or a .local name), never to the console itself or the internet.
//
// Chromium's web view never shakes the controller, so lamp.js sends a page's vibrationActuator calls here (`rumble`
// messages), and the host plays them with Windows.Gaming.Input, as a native game's lamp_rumble does.
//
// A game that chose its own host for its phones (`Lamp.controllers.start({ host: 'game' })`) plays with no Lamp
// (lamp_controllers.h): the host serves the game's phone page from the package's Phone folder and runs the relay its
// phones join, each on a port the system gives it, with a key made for that session and kept only in memory. The page
// asks the host for its session (`controllers` messages), and its own link to the relay is carried over the host's
// pipe straight into the relay, never over the network, so only the page can be the game's host. Stopping, the console setting the app aside, the page going
// away, and no ask from it for 45 s end the session: listeners close, players are let go and the key is forgotten;
// the page's next ask opens a new one.
//
// An app shared with the person carries network-policy.json beside the host, written by Lamp from the sites its safety
// sheet named (lamp_web_guard.h). Its page then reaches only its own files and those sites, with or without Lamp: the
// host serves the app's files itself rather than through WebView2's mapping of a folder, each answer carrying the policy
// as its Content-Security-Policy; every request of the page, its frames and its workers is put to the policy, and one to
// a site it doesn't list is refused; navigations and new windows go only to its pages or a listed site; the web view is
// started so it opens no connection but to a listed site, which holds a preconnect too; WebRTC is taken out of every
// frame; the http bridge goes only to Lamp on the Mac, and the ws bridge only to a listed site or a relay Lamp's own
// answer named. An app with no policy file runs as it always has.
//
// The page is laid out at 1920x1080 CSS pixels, as in Lamp's preview on the Mac and as the rules say: the console's
// web view would otherwise lay it out at 1280x720 and scale it up, so the host zooms it out to match.
//
// Built by scripts/build-web-host.sh; Lamp ships the program it makes (Resources/WebHost/App.exe).
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.ApplicationModel.Core.h>
#include <winrt/Windows.UI.Core.h>
#include <winrt/Windows.UI.ViewManagement.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.UI.Composition.h>
#include <winrt/Windows.Data.Json.h>
#include <winrt/Windows.Web.Http.h>
#include <winrt/Windows.Web.Http.Filters.h>
#include <winrt/Windows.Web.Http.Headers.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.System.Threading.h>
#include <winrt/Windows.Gaming.Input.h>
#include <winrt/Windows.Networking.h>
#include <winrt/Windows.Networking.Sockets.h>
#include <winrt/Windows.Networking.Connectivity.h>
#include <winrt/Windows.Security.Cryptography.h>
#include <winrt/Windows.Security.Cryptography.Core.h>
#include <winrt/Microsoft.Web.WebView2.Core.h>
#include <algorithm>
#include <atomic>
#include <mutex>
#include <cstdio>
#include <deque>
#include <map>
#include <memory>
#include <string>
#include "lamp_controllers.h"
#include "lamp_web_guard.h"

using namespace winrt;
using namespace Windows::ApplicationModel::Core;
using namespace Windows::UI::Core;
using namespace Microsoft::Web::WebView2::Core;
using Windows::Data::Json::JsonObject;
using Windows::Data::Json::JsonValue;

static FILE* g_log = nullptr;
static const wchar_t* g_origin = L"https://lamp.example/";

static bool is_app_page(std::wstring_view url) { return url.rfind(g_origin, 0) == 0; }

static void say_line(std::wstring_view text);

// network-policy.json beside the host: nil when the package has none, and empty text when it's there but can't be read,
// which guards the app with nothing listed.
static std::optional<std::string> read_policy(std::wstring const& path) {
    WIN32_FILE_ATTRIBUTE_DATA data{};
    if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) {
        DWORD error = GetLastError();
        if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) return std::nullopt;
        return std::string();
    }
    if (data.nFileSizeHigh || data.nFileSizeLow > 1024 * 1024) return std::string();
    FILE* file = _wfopen(path.c_str(), L"rb");
    if (!file) return std::string();
    std::string text(data.nFileSizeLow, '\0');
    size_t read = text.empty() ? 0 : fread(text.data(), 1, text.size(), file);
    fclose(file);
    return read == text.size() ? text : std::string();
}

// What the log says of where a refused request went: its site, never the whole address, which may carry what the page sent.
static std::wstring site_of(std::string const& url) {
    auto origin = lampg::origin_of(url);
    return origin ? std::wstring(to_hstring(*origin)) : std::wstring(L"an address that isn't a website's");
}

// An IPv4 address on a home network: private (10/8, 172.16/12, 192.168/16) or link-local (169.254/16).
static bool is_private_v4(std::wstring_view host) {
    unsigned a, b, c, d;
    wchar_t rest;
    if (swscanf_s(std::wstring(host).c_str(), L"%u.%u.%u.%u%lc", &a, &b, &c, &d, &rest, 1) != 4 || a > 255 || b > 255 || c > 255 || d > 255) return false;
    return a == 10 || (a == 172 && b >= 16 && b < 32) || (a == 192 && b == 168) || (a == 169 && b == 254);
}

// Where the page may open a link to: ws:// on this network, at a port of a program's own, with nothing but a host and a
// port. The wish's apps meet at Lamp's relay on the Mac and at each other's listeners, all on the home network; the
// console's own services (its loopback) and anywhere beyond the network are never reached through the host.
static bool may_dial(Windows::Foundation::Uri const& url) {
    if (url.SchemeName() != L"ws" || !url.UserName().empty() || !url.Password().empty() || url.Port() < 1024 || url.Port() > 65535) return false;
    std::wstring host(url.Host());
    std::transform(host.begin(), host.end(), host.begin(), ::towlower);
    if (is_private_v4(host)) return true;
    // An IPv6 link-local or unique local address.
    if (host.size() > 2 && host.front() == L'[' && host.back() == L']')
        return host.rfind(L"[fe8", 0) == 0 || host.rfind(L"[fe9", 0) == 0 || host.rfind(L"[fea", 0) == 0 || host.rfind(L"[feb", 0) == 0
            || host.rfind(L"[fc", 0) == 0 || host.rfind(L"[fd", 0) == 0;
    // A Mac's Bonjour name, which only this network answers.
    bool plain = !host.empty() && std::all_of(host.begin(), host.end(), [](wchar_t ch) { return iswalnum(ch) || ch == L'-' || ch == L'.'; });
    return plain && host.size() > 6 && host.compare(host.size() - 6, 6, L".local") == 0;
}

static void say(const wchar_t* format, ...) {
    wchar_t line[1024];
    va_list args;
    va_start(args, format);
    _vsnwprintf_s(line, _TRUNCATE, format, args);
    va_end(args);
    say_line(line);
}

static void say_line(std::wstring_view text) {
    if (!g_log) return;
    // UTF-8 in the file, so Device Portal hands back plain text whatever the page wrote.
    int n = WideCharToMultiByte(CP_UTF8, 0, text.data(), (int)text.size(), nullptr, 0, nullptr, nullptr);
    std::string out(n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, text.data(), (int)text.size(), out.data(), n, nullptr, nullptr);
    fwrite(out.data(), 1, out.size(), g_log);
    fputc('\n', g_log);
    fflush(g_log);
}

// MARK: Phones as controllers: the console's side of lamp_controllers.h

namespace lampc::platform {
using Windows::Security::Cryptography::CryptographicBuffer;

static Windows::Storage::Streams::IBuffer buffer_of(std::string_view data) {
    return CryptographicBuffer::CreateFromByteArray({ reinterpret_cast<uint8_t const*>(data.data()), reinterpret_cast<uint8_t const*>(data.data()) + data.size() });
}

void random_bytes(uint8_t* out, size_t count) {
    auto random = CryptographicBuffer::GenerateRandom((uint32_t)count);
    memcpy(out, random.data(), count);
}

std::array<uint8_t, 32> hmac_sha256(std::string_view key, std::string_view data) {
    using namespace Windows::Security::Cryptography::Core;
    static auto provider = MacAlgorithmProvider::OpenAlgorithm(MacAlgorithmNames::HmacSha256());
    auto signature = CryptographicEngine::Sign(provider.CreateKey(buffer_of(key)), buffer_of(data));
    std::array<uint8_t, 32> out{};
    memcpy(out.data(), signature.data(), std::min<size_t>(out.size(), signature.Length()));
    return out;
}

std::array<uint8_t, 20> sha1(std::string_view data) {
    using namespace Windows::Security::Cryptography::Core;
    static auto provider = HashAlgorithmProvider::OpenAlgorithm(HashAlgorithmNames::Sha1());
    auto digest = provider.HashData(buffer_of(data));
    std::array<uint8_t, 20> out{};
    memcpy(out.data(), digest.data(), std::min<size_t>(out.size(), digest.Length()));
    return out;
}
}

// Where a phone's page goes: the page-only link the host carries into its relay (`pipe`), never dialed.
static const wchar_t* g_relay_link = L"ws://lamp-controllers.invalid/";

// The console's address a phone's link carries: one on the home network, the one the console reaches the internet by
// when it has several; nil on none, so a phone is never given a link to itself.
static std::optional<std::wstring> link_host() {
    using namespace Windows::Networking::Connectivity;
    std::optional<std::wstring> any, internet;
    try {
        hstring adapter;
        if (auto profile = NetworkInformation::GetInternetConnectionProfile(); profile && profile.NetworkAdapter())
            adapter = to_hstring(profile.NetworkAdapter().NetworkAdapterId());
        for (auto const& name : NetworkInformation::GetHostNames()) {
            if (name.Type() != Windows::Networking::HostNameType::Ipv4 || !is_private_v4(name.CanonicalName())) continue;
            std::wstring address(name.CanonicalName());
            if (!any) any = address;
            auto info = name.IPInformation();
            if (!internet && info && info.NetworkAdapter() && !adapter.empty() && to_hstring(info.NetworkAdapter().NetworkAdapterId()) == adapter) internet = address;
        }
    } catch (...) {}
    return internet ? internet : any;
}

// The console's names and addresses, lowercased: the only ones a phone's page is served as.
static std::set<std::string> host_names() {
    std::set<std::string> names;
    try {
        for (auto const& name : Windows::Networking::Connectivity::NetworkInformation::GetHostNames()) {
            std::string text = lampc::lower(to_string(name.CanonicalName()));
            if (auto zone = text.find('%'); zone != std::string::npos) text = text.substr(0, zone);
            if (!text.empty()) names.insert(text);
        }
    } catch (...) {}
    return names;
}

// Which phone a connection is from, for the limits on how many it may hold (`lampc::source_of`).
static std::string remote_of(Windows::Networking::Sockets::StreamSocket const& socket) {
    try { return lampc::source_of(to_string(socket.Information().RemoteAddress().CanonicalName())); }
    catch (...) { return "?"; }
}

// A StreamSocket under one of lampc's WebSockets: each write handed to the network, and `done` on the window's thread.
struct StreamTransport : lampc::Transport {
    Windows::Networking::Sockets::StreamSocket socket;
    Windows::Storage::Streams::DataWriter writer;
    CoreDispatcher dispatcher;
    StreamTransport(Windows::Networking::Sockets::StreamSocket s, Windows::Storage::Streams::DataWriter w, CoreDispatcher d)
        : socket(std::move(s)), writer(std::move(w)), dispatcher(std::move(d)) {}
    void write(std::string bytes, std::function<void(bool)> done) override { send(writer, dispatcher, std::move(bytes), std::move(done)); }
    void shutdown() override { try { socket.Close(); } catch (...) {} }

    // Touches nothing of the transport after it waits, which may be gone by then.
    static fire_and_forget send(Windows::Storage::Streams::DataWriter writer, CoreDispatcher dispatcher, std::string bytes, std::function<void(bool)> done) {
        bool ok = true;
        try {
            writer.WriteBytes({ reinterpret_cast<uint8_t const*>(bytes.data()), reinterpret_cast<uint8_t const*>(bytes.data()) + bytes.size() });
            co_await writer.StoreAsync();
        } catch (...) { ok = false; }
        co_await resume_foreground(dispatcher);
        done(ok);
    }
};

struct View : implements<View, IFrameworkViewSource, IFrameworkView> {
    CoreWindow window{ nullptr };
    CoreWebView2Environment env{ nullptr };
    CoreWebView2Controller controller{ nullptr };
    CoreWebView2 web{ nullptr };
    CoreWebView2DevToolsProtocolEventReceiver consoleCalls{ nullptr }, uncaught{ nullptr };
    // The page is drawn into this visual, the window's only content: WebView2 on the Xbox is hosted the way WinUI's
    // control hosts it, through composition, since a controller given the CoreWindow itself ends the app.
    Windows::UI::Composition::Compositor compositor{ nullptr };
    Windows::UI::Composition::CompositionTarget target{ nullptr };
    Windows::UI::Composition::ContainerVisual root{ nullptr };
    std::wstring installed;
    // A shared app's policy (lamp_web_guard.h), read once as the app opens, and the relays Lamp's own answers named.
    lampg::Policy policy;
    std::set<std::string> lamp_sockets;
    // One effect at a time on each controller: a new one, or a reset, takes the place of what was playing.
    // Each of the page's gamepads by its index: the controller it was found to be, and what's playing on it.
    struct Rumble {
        Windows::Gaming::Input::Gamepad pad{ nullptr };
        std::atomic<uint64_t> effect{ 0 };
        Windows::System::Threading::ThreadPoolTimer start{ nullptr }, stop{ nullptr };
    };
    Rumble rumbles[4];
    // Held over each check of an effect's generation and the write that follows it, from the timers and from `still`, so
    // a timer can't write an effect's strength after a reset has stilled the controller.
    std::mutex shaking;
    // Counts the page's top-level navigations, so an answer to a page that has since gone is dropped.
    uint64_t page = 0;
    struct PagePeer;
    // The page's links to the wish's other apps, by the page's number for each; touched only on the window's thread.
    struct Pipe {
        Windows::Networking::Sockets::MessageWebSocket socket{ nullptr };
        Windows::Storage::Streams::DataWriter writer{ nullptr };
        // What the page sent while the link opened or a frame before it was still going: text, or bytes in base64.
        std::deque<std::pair<bool, hstring>> queue;
        bool open = false, writing = false, over = false;
        uint64_t page = 0;
        // The page's link to the game's own relay, carried in the host rather than dialed.
        std::shared_ptr<PagePeer> local;
    };
    std::map<double, std::shared_ptr<Pipe>> pipes;

    IFrameworkView CreateView() { return *this; }

    void Initialize(CoreApplicationView const&) {
        installed = std::wstring(Windows::ApplicationModel::Package::Current().InstalledLocation().Path());
        policy = lampg::Policy::read(read_policy(installed + L"\\" + std::wstring(to_hstring(lampg::policy_file))));
        CoreApplication::Suspending([this](auto const&, Windows::ApplicationModel::SuspendingEventArgs const& args) {
            say_line(L"Lamp: the console set the app aside.");
            for (int i = 0; i < 4; i++) still(i);
            // Phones' session ends with it: nothing listens while the app is set aside, and coming back opens a new one.
            if (!window) return;
            auto deferral = args.SuspendingOperation().GetDeferral();
            window.Dispatcher().RunAsync(CoreDispatcherPriority::High, [this, deferral] {
                phones_close(L"the console set the app aside");
                deferral.Complete();
            });
        });
        CoreApplication::Resuming([this](auto const&, auto const&) {
            say_line(L"Lamp: the app came back.");
            // Links held over a suspension may be gone without a word: the page is told they're closed, and opens them
            // again as it does any link lost.
            if (window) window.Dispatcher().RunAsync(CoreDispatcherPriority::Normal, [this] { end_pipes(1001); });
        });
    }

    void Load(hstring const&) {}
    void Uninitialize() {}

    void SetWindow(CoreWindow const& w) {
        window = w;
        // The whole screen is the page's: no border kept for the TV's edges, as a web app would expect.
        Windows::UI::ViewManagement::ApplicationView::GetForCurrentView().SetDesiredBoundsMode(
            Windows::UI::ViewManagement::ApplicationViewBoundsMode::UseCoreWindow);
        // B on the controller is the page's (Escape for its menus, a game's own use): without this the console takes it
        // as Back and leaves the app.
        SystemNavigationManager::GetForCurrentView().BackRequested([](auto const&, BackRequestedEventArgs const& args) { args.Handled(true); });
        window.SizeChanged([this](auto const&, auto const&) { fit(); });
        // Windows lists controllers only once something listens for them: listening from the start, the first effect
        // finds them there.
        Windows::Gaming::Input::Gamepad::GamepadAdded([](auto const&, auto const&) {
            say(L"Lamp: %u controllers connected.", Windows::Gaming::Input::Gamepad::Gamepads().Size());
        });
        window.VisibilityChanged([this](auto const&, VisibilityChangedEventArgs const& args) {
            if (controller) controller.IsVisible(args.Visible());
            // A game set aside mid-effect doesn't leave the controller shaking in the person's hands.
            if (!args.Visible()) for (int i = 0; i < 4; i++) still(i);
        });
    }

    void fit() {
        if (!controller || !window) return;
        auto b = window.Bounds();
        controller.Bounds({ 0, 0, b.Width, b.Height });
    }

    fire_and_forget start() {
        auto lifetime = get_strong();
        try {
            // A console app plays its sound as it opens, as a game's title music does: WebView2, like Chrome, would hold
            // a page's sound back until the first press of a button, so that rule is turned off for the app's own page.
            CoreWebView2EnvironmentOptions options;
            std::wstring arguments = L"--autoplay-policy=no-user-gesture-required";
            // A shared app's web view connects only to its listed sites, below the page (lamp_web_guard.h).
            if (policy.guarded) arguments += L" " + std::wstring(to_hstring(lampg::browser_arguments(policy)));
            options.AdditionalBrowserArguments(arguments);
            env = co_await CoreWebView2Environment::CreateWithOptionsAsync(L"", L"", options);
            say(L"Lamp: WebView2 %ls.", env.BrowserVersionString().c_str());
            compositor = Windows::UI::Composition::Compositor();
            target = compositor.CreateTargetForCurrentView();
            root = compositor.CreateContainerVisual();
            root.RelativeSizeAdjustment({ 1, 1 });
            target.Root(root);
            auto composed = co_await env.CreateCoreWebView2CompositionControllerAsync(CoreWebView2ControllerWindowReference::CreateFromCoreWindow(window));
            composed.RootVisualTarget(root);
            controller = composed;
            controller.DefaultBackgroundColor(Windows::UI::Color{ 255, 0, 0, 0 });
            fit();
            controller.IsVisible(true);
            auto b = window.Bounds();
            say(L"Lamp: the window is %.0f by %.0f, the page drawn at %.2f.", b.Width, b.Height, controller.RasterizationScale());
            // Focus stays in the page: leaving it would leave nothing on screen to take the controller.
            controller.MoveFocusRequested([](auto const&, CoreWebView2MoveFocusRequestedEventArgs const& args) { args.Handled(true); });

            // Kept for the app's life: WebView2's WinRT objects drop the handlers added to them once they're let go.
            web = controller.CoreWebView2();
            auto settings = web.Settings();
            settings.AreDefaultContextMenusEnabled(false);
            settings.IsStatusBarEnabled(false);
            settings.IsGeneralAutofillEnabled(false);
            settings.IsPasswordAutosaveEnabled(false);
            settings.IsZoomControlEnabled(false);
            settings.IsPinchZoomEnabled(false);
            // The page is the app's own, from its package, so nothing it opens needs SmartScreen's look first.
            settings.IsReputationCheckingRequired(false);
            if (policy.guarded) co_await guard();
            else web.SetVirtualHostNameToFolderMapping(L"lamp.example", hstring(installed + L"\\Web"), CoreWebView2HostResourceAccessKind::Allow);
            web.WebMessageReceived([this](auto const&, CoreWebView2WebMessageReceivedEventArgs const& args) {
                JsonObject message{ nullptr };
                if (JsonObject::TryParse(args.WebMessageAsJson(), message) && message.GetNamedString(L"lamp", L"") == L"http") {
                    if (is_app_page(args.Source())) relay(message);
                    return;
                }
                if (message && message.GetNamedString(L"lamp", L"") == L"rumble") {
                    if (is_app_page(args.Source())) rumble(message);
                    return;
                }
                if (message && message.GetNamedString(L"lamp", L"") == L"ws") {
                    if (is_app_page(args.Source())) pipe(message);
                    return;
                }
                if (message && message.GetNamedString(L"lamp", L"") == L"controllers") {
                    if (is_app_page(args.Source()))
                        phone_ask({ message.GetNamedString(L"op", L"") == L"stop", message.GetNamedNumber(L"id", 0), page });
                    return;
                }
                try { say_line(std::wstring(L"page: ") + std::wstring(args.TryGetWebMessageAsString())); }
                catch (...) { say_line(std::wstring(L"page: ") + std::wstring(args.WebMessageAsJson()).substr(0, 2000)); }
            });
            listen_to_console();
            web.NavigationCompleted([](auto const&, CoreWebView2NavigationCompletedEventArgs const& args) {
                if (args.IsSuccess()) say_line(L"Lamp: the page opened.");
                else say(L"Lamp: the page didn't open (%d).", (int)args.WebErrorStatus());
            });
            web.ProcessFailed([](auto const&, CoreWebView2ProcessFailedEventArgs const& args) {
                say(L"Lamp: a WebView2 process stopped (kind %d, reason %d, exit %d).", (int)args.ProcessFailedKind(), (int)args.Reason(), args.ExitCode());
            });
            // The app's pages stay in this window; anything else opens in the console's browser, so no other site's page
            // is ever where the app's answers go.
            web.NavigationStarting([this](auto const&, CoreWebView2NavigationStartingEventArgs const& args) {
                std::wstring uri(args.Uri());
                // A shared app's page leaves only for a site it was shared with: going anywhere else is a request there.
                if (policy.guarded) {
                    auto where = lampg::navigation(policy, to_string(uri));
                    if (where == lampg::Navigation::stay) { page++; end_pipes(0); phones_close(L"the page went away"); return; }
                    args.Cancel(true);
                    if (where == lampg::Navigation::browser) elsewhere(uri);
                    else say(L"Lamp: the page's link to %ls wasn't opened: it isn't one of the sites the app was shared with.", site_of(to_string(uri)).c_str());
                    return;
                }
                if (is_app_page(uri) || uri == L"about:blank") { page++; end_pipes(0); phones_close(L"the page went away"); return; }
                args.Cancel(true);
                elsewhere(uri);
            });
            web.NewWindowRequested([this](auto const& sender, CoreWebView2NewWindowRequestedEventArgs const& args) {
                args.Handled(true);
                std::wstring uri(args.Uri());
                if (policy.guarded) {
                    auto where = lampg::navigation(policy, to_string(uri));
                    if (where == lampg::Navigation::stay) sender.Navigate(args.Uri());
                    else if (where == lampg::Navigation::browser) elsewhere(uri);
                    else say(L"Lamp: the page's window for %ls wasn't opened: it isn't one of the sites the app was shared with.", site_of(to_string(uri)).c_str());
                    return;
                }
                if (is_app_page(uri)) sender.Navigate(args.Uri()); else elsewhere(uri);
            });
            co_await fit_page();
            web.Navigate(L"https://lamp.example/index.html");
            controller.MoveFocus(CoreWebView2MoveFocusReason::Programmatic);
        } catch (hresult_error const& e) {
            say(L"Lamp: WebView2 couldn't start (0x%08x): %ls", (unsigned)e.code(), e.message().c_str());
        }
    }

    // MARK: A shared app's sites

    // Every request of the page, its frames and its workers (dedicated, shared and service) comes to `requested`; with no
    // folder mapped, the app's own files are served there or not at all.
    Windows::Foundation::IAsyncAction guard() {
        auto lifetime = get_strong();
        say(L"Lamp: this app was shared: it reaches its own files and the %u sites it was shared with, nothing else.", (unsigned)policy.origins.size());
        try {
            web.AddWebResourceRequestedFilter(L"*", CoreWebView2WebResourceContext::All, CoreWebView2WebResourceRequestSourceKinds::All);
        } catch (hresult_error const&) {
            // A WebView2 older than the one Lamp builds with: its workers' requests aren't shown to the host, and are held
            // by the policy their own answers carry.
            web.AddWebResourceRequestedFilter(L"*", CoreWebView2WebResourceContext::All);
            say_line(L"Lamp: this WebView2 doesn't show the host its workers' requests; the policy still holds them.");
        }
        web.WebResourceRequested([this](auto const&, CoreWebView2WebResourceRequestedEventArgs const& args) { requested(args); });
        web.FrameNavigationStarting([this](auto const&, CoreWebView2NavigationStartingEventArgs const& args) {
            std::string uri = to_string(args.Uri());
            if (lampg::frame_may_open(policy, uri)) return;
            args.Cancel(true);
            say(L"Lamp: a frame of the page wasn't let open %ls: it isn't one of the sites the app was shared with.", site_of(uri).c_str());
        });
        co_await web.AddScriptToExecuteOnDocumentCreatedAsync(to_hstring(lampg::no_webrtc_script()));
    }

    void requested(CoreWebView2WebResourceRequestedEventArgs const& args) {
        std::string url = to_string(args.Request().Uri());
        switch (lampg::request(policy, url)) {
        case lampg::Request::allowed: return;
        case lampg::Request::local: serve(args, url); return;
        case lampg::Request::blocked:
            say(L"Lamp: the page's request to %ls was refused: it isn't one of the sites the app was shared with.", site_of(url).c_str());
            args.Response(respond(lampg::blocked(policy), nullptr));
            return;
        }
    }

    CoreWebView2WebResourceResponse respond(lampg::Head const& head, Windows::Storage::Streams::IRandomAccessStream const& body) {
        std::wstring headers;
        for (auto const& [name, value] : head.headers) headers += std::wstring(to_hstring(name)) + L": " + std::wstring(to_hstring(value)) + L"\r\n";
        return env.CreateWebResourceResponse(body, head.status, to_hstring(head.reason), hstring(headers));
    }

    // One of the app's files under Web/ by its address: its path, name and size, a plain file reached through no link.
    struct WebFile {
        std::wstring path;
        std::string name;
        uint64_t size = 0;
    };
    std::optional<WebFile> web_file(std::string const& url) {
        auto steps = lampg::steps(policy, url);
        if (!steps) return std::nullopt;
        std::wstring path = installed + L"\\Web";
        WIN32_FILE_ATTRIBUTE_DATA data{};
        for (auto const& step : *steps) {
            path += L"\\" + std::wstring(to_hstring(step));
            if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)
                || (data.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM))) return std::nullopt;
        }
        if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) return std::nullopt;
        return WebFile{ path, steps->back(), (uint64_t)data.nFileSizeHigh << 32 | data.nFileSizeLow };
    }

    // The file, or the part of it asked for: a whole one read as WebView2 takes it, a part (a video's, as it plays) read
    // into memory, at most `lampg::range_piece`.
    static Windows::Foundation::IAsyncOperation<Windows::Storage::Streams::IRandomAccessStream> open_part(std::wstring path, lampg::Range part) {
        co_await resume_background();
        auto file = co_await Windows::Storage::StorageFile::GetFileFromPathAsync(path);
        Windows::Storage::Streams::IRandomAccessStream stream = co_await file.OpenReadAsync();
        if (!part.partial) co_return stream;
        stream.Seek(part.offset);
        Windows::Storage::Streams::Buffer buffer((uint32_t)part.length);
        auto read = co_await stream.ReadAsync(buffer, (uint32_t)part.length, Windows::Storage::Streams::InputStreamOptions::None);
        Windows::Storage::Streams::InMemoryRandomAccessStream piece;
        co_await piece.WriteAsync(read);
        piece.Seek(0);
        co_return piece;
    }

    // Answers a request for one of the app's files, the policy on the answer.
    fire_and_forget serve(CoreWebView2WebResourceRequestedEventArgs args, std::string url) {
        auto lifetime = get_strong();
        auto dispatcher = window.Dispatcher();
        auto deferral = args.GetDeferral();
        auto request = args.Request();
        std::wstring method(request.Method());
        std::optional<std::string> asked;
        lampg::Head head = lampg::refusal(policy, 404, "Not Found");
        Windows::Storage::Streams::IRandomAccessStream body{ nullptr };
        try {
            if (request.Headers().Contains(L"Range")) asked = to_string(request.Headers().GetHeader(L"Range"));
            if (method != L"GET" && method != L"HEAD") head = lampg::refusal(policy, 405, "Method Not Allowed");
            else if (auto file = web_file(url)) {
                if (auto part = lampg::range(asked, file->size)) {
                    head = lampg::local_head(policy, file->name, file->size, *part);
                    if (method == L"GET") body = co_await open_part(file->path, *part);
                } else head = lampg::refusal(policy, 416, "Range Not Satisfiable");
            }
        } catch (...) {
            head = lampg::refusal(policy, 404, "Not Found");
            body = nullptr;
        }
        co_await resume_foreground(dispatcher);
        try { args.Response(respond(head, body)); } catch (...) {}
        deferral.Complete();
    }

    // The page's console and uncaught errors, through the DevTools protocol, so the log says what went wrong in it.
    fire_and_forget listen_to_console() {
        auto lifetime = get_strong();
        auto line = [](JsonObject const& o) {
            std::wstring text;
            for (auto const& value : o.GetNamedArray(L"args", Windows::Data::Json::JsonArray())) {
                auto arg = value.GetObject();
                if (!text.empty()) text += L" ";
                if (arg.HasKey(L"value")) {
                    auto v = arg.GetNamedValue(L"value");
                    text += v.ValueType() == Windows::Data::Json::JsonValueType::String ? std::wstring(v.GetString()) : std::wstring(v.Stringify());
                } else text += std::wstring(arg.GetNamedString(L"description", arg.GetNamedString(L"type", L"")));
            }
            return text.substr(0, 2000);
        };
        consoleCalls = web.GetDevToolsProtocolEventReceiver(L"Runtime.consoleAPICalled");
        consoleCalls.DevToolsProtocolEventReceived(
            [line](auto const&, CoreWebView2DevToolsProtocolEventReceivedEventArgs const& args) {
                JsonObject o{ nullptr };
                if (!JsonObject::TryParse(args.ParameterObjectAsJson(), o)) return;
                say_line(L"console." + std::wstring(o.GetNamedString(L"type", L"log")) + L": " + line(o));
            });
        uncaught = web.GetDevToolsProtocolEventReceiver(L"Runtime.exceptionThrown");
        uncaught.DevToolsProtocolEventReceived(
            [](auto const&, CoreWebView2DevToolsProtocolEventReceivedEventArgs const& args) {
                JsonObject o{ nullptr };
                if (!JsonObject::TryParse(args.ParameterObjectAsJson(), o)) return;
                auto details = o.GetNamedObject(L"exceptionDetails", JsonObject());
                auto exception = details.GetNamedObject(L"exception", JsonObject());
                std::wstring text(exception.GetNamedString(L"description", details.GetNamedString(L"text", L"")));
                say_line(L"error: " + text.substr(0, 2000) + L" (line " + std::to_wstring((int)details.GetNamedNumber(L"lineNumber", 0) + 1) + L")");
            });
        try { co_await web.CallDevToolsProtocolMethodAsync(L"Runtime.enable", L"{}"); }
        catch (hresult_error const& e) { say(L"Lamp: the page's console can't be read (0x%08x).", (unsigned)e.code()); }
    }

    // One of lamp.js's calls to Lamp on the Mac: a POST with JSON to Lamp's own paths over plain http, answered with
    // the status and body, or with an error the page reads as "unreachable".
    fire_and_forget relay(JsonObject message) {
        auto lifetime = get_strong();
        auto dispatcher = window.Dispatcher();
        uint64_t asked = page;
        double id = message.GetNamedNumber(L"id", 0);
        JsonObject answer;
        answer.SetNamedValue(L"lamp", JsonValue::CreateStringValue(L"http"));
        answer.SetNamedValue(L"id", JsonValue::CreateNumberValue(id));
        // What a shared app's answer from Lamp says, for the relays it names.
        std::string told_path, told;
        try {
            Windows::Foundation::Uri url(message.GetNamedString(L"url", L""));
            std::wstring path(url.Path());
            bool lamps = path.rfind(L"/ai", 0) == 0 || path.rfind(L"/app/", 0) == 0;
            if (url.SchemeName() != L"http" || !lamps || !url.UserName().empty()) throw hresult_invalid_argument(L"not one of Lamp's paths");
            if (!lampg::http_bridge(policy, to_string(url.AbsoluteUri()))) throw hresult_invalid_argument(L"not Lamp on the Mac");
            auto body = message.GetNamedString(L"body", L"");
            if (body.size() > 8 * 1024 * 1024) throw hresult_invalid_argument(L"too big");
            double timeout = message.GetNamedNumber(L"timeout", 240000);
            co_await resume_background();
            Windows::Web::Http::Filters::HttpBaseProtocolFilter filter;
            filter.AllowAutoRedirect(false);
            filter.CacheControl().ReadBehavior(Windows::Web::Http::Filters::HttpCacheReadBehavior::NoCache);
            Windows::Web::Http::HttpClient client(filter);
            Windows::Web::Http::HttpRequestMessage request(Windows::Web::Http::HttpMethod::Post(), url);
            request.Content(Windows::Web::Http::HttpStringContent(body, Windows::Storage::Streams::UnicodeEncoding::Utf8, L"application/json"));
            auto token = message.GetNamedString(L"token", L"");
            if (!token.empty()) request.Headers().Authorization(Windows::Web::Http::Headers::HttpCredentialsHeaderValue(L"Bearer", token));
            auto sending = client.SendRequestAsync(request);
            if (sending.wait_for(std::chrono::milliseconds((int64_t)timeout)) != Windows::Foundation::AsyncStatus::Completed) {
                sending.Cancel();
                throw hresult_error(E_ABORT, L"no answer");
            }
            auto response = sending.GetResults();
            auto text = response.Content().ReadAsStringAsync().get();
            answer.SetNamedValue(L"status", JsonValue::CreateNumberValue((double)(int)response.StatusCode()));
            say(L"Lamp: %ls%ls answered %d.", url.Host().c_str(), path.c_str(), (int)response.StatusCode());
            answer.SetNamedValue(L"body", JsonValue::CreateStringValue(text));
            if (policy.guarded) { told_path = to_string(path); told = to_string(text); }
        } catch (hresult_error const& e) {
            say(L"Lamp: a call to Lamp on the Mac failed (0x%08x): %ls", (unsigned)e.code(), e.message().c_str());
            answer.SetNamedValue(L"error", JsonValue::CreateStringValue(e.message()));
        }
        co_await resume_foreground(dispatcher);
        // A relay Lamp named (its phones, a wish's room) is one the ws bridge may open for a shared app.
        for (auto const& origin : lampg::sockets_in(told_path, told)) lamp_sockets.insert(origin);
        if (web && page == asked && is_app_page(web.Source())) web.PostWebMessageAsJson(answer.Stringify());
    }

    // What the page asks of its links: open one, send a frame on it, close it, or say this console's addresses.
    void pipe(JsonObject const& m) {
        auto op = m.GetNamedString(L"op", L"");
        double id = m.GetNamedNumber(L"id", 0);
        if (op == L"here") return here();
        if (op == L"open") {
            if (m.GetNamedString(L"url", L"") == g_relay_link) return open_local(id);
            std::shared_ptr<Pipe> p;
            try {
                Windows::Foundation::Uri url(m.GetNamedString(L"url", L""));
                // A sweep of the network opens a few dozen at once; more than that is something gone wrong in the page.
                if (pipes.count(id) || pipes.size() >= 64) throw hresult_invalid_argument(L"too many links");
                if (!may_dial(url)) throw hresult_invalid_argument(L"not a link to this network");
                if (!lampg::ws_bridge(policy, to_string(url.AbsoluteUri()), lamp_sockets)) throw hresult_invalid_argument(L"not one of the sites the app was shared with");
                p = std::make_shared<Pipe>();
                p->page = page;
                pipes[id] = p;
                dial(id, p, url);
            } catch (hresult_error const& e) {
                say(L"Lamp: the page's link wasn't opened: %ls", e.message().c_str());
                if (p) pipes.erase(id);
                tell(id, page, L"close", 1006);
            }
            return;
        }
        auto found = pipes.find(id);
        if (found == pipes.end()) return;
        auto p = found->second;
        if (op == L"close") return end_pipe(id, p, 0, false);
        if (op != L"send") return;
        bool binary = m.HasKey(L"data");
        // Held to what a file's piece takes, sealed, in base64, and to a queue the page's own flow keeps short.
        auto payload = binary ? m.GetNamedString(L"data", L"") : m.GetNamedString(L"text", L"");
        if (payload.size() > 128 * 1024 || p->queue.size() >= 256) return end_pipe(id, p, 1009, true);
        if (p->local) return to_local(id, p, binary, payload);
        p->queue.emplace_back(binary, payload);
        pump(id, p);
    }

    // Opens one link, and passes what comes on it to the page, in order.
    fire_and_forget dial(double id, std::shared_ptr<Pipe> p, Windows::Foundation::Uri url) {
        auto lifetime = get_strong();
        auto dispatcher = window.Dispatcher();
        using namespace Windows::Networking::Sockets;
        std::weak_ptr<Pipe> weak = p;
        bool failed = false;
        try {
            MessageWebSocket socket;
            socket.Control().MessageType(SocketMessageType::Utf8);
            p->socket = socket;
            socket.MessageReceived([this, id, weak, dispatcher](auto const&, MessageWebSocketMessageReceivedEventArgs const& args) {
                JsonObject out;
                out.SetNamedValue(L"lamp", JsonValue::CreateStringValue(L"ws"));
                out.SetNamedValue(L"id", JsonValue::CreateNumberValue(id));
                out.SetNamedValue(L"ev", JsonValue::CreateStringValue(L"message"));
                bool lost = false;
                try {
                    auto reader = args.GetDataReader();
                    uint32_t n = reader.UnconsumedBufferLength();
                    if (args.MessageType() == SocketMessageType::Utf8) {
                        reader.UnicodeEncoding(Windows::Storage::Streams::UnicodeEncoding::Utf8);
                        out.SetNamedValue(L"text", JsonValue::CreateStringValue(n ? reader.ReadString(n) : hstring()));
                    } else {
                        out.SetNamedValue(L"data", JsonValue::CreateStringValue(Windows::Security::Cryptography::CryptographicBuffer::EncodeToBase64String(reader.ReadBuffer(n))));
                    }
                } catch (...) { lost = true; }
                auto text = out.Stringify();
                dispatcher.RunAsync(CoreDispatcherPriority::Normal, [this, id, weak, lost, text] {
                    auto p = weak.lock();
                    if (!p || p->over) return;
                    if (lost) return end_pipe(id, p, 1006, true);
                    if (web && p->page == page && is_app_page(web.Source())) web.PostWebMessageAsJson(text);
                });
            });
            socket.Closed([this, id, weak, dispatcher](auto const&, WebSocketClosedEventArgs const& args) {
                int code = args.Code();
                dispatcher.RunAsync(CoreDispatcherPriority::Normal, [this, id, weak, code] {
                    if (auto p = weak.lock()) end_pipe(id, p, code ? code : 1006, true);
                });
            });
            co_await socket.ConnectAsync(url);
        } catch (...) { failed = true; }
        co_await resume_foreground(dispatcher);
        if (p->over) co_return;
        if (failed) co_return end_pipe(id, p, 1006, true);
        p->writer = Windows::Storage::Streams::DataWriter(p->socket.OutputStream());
        p->open = true;
        tell(id, p->page, L"open", 0);
        pump(id, p);
    }

    // Sends what the page queued on a link, one frame at a time, telling the page as each has gone so its count of
    // what's still to go (a file's flow) stays right.
    fire_and_forget pump(double id, std::shared_ptr<Pipe> p) {
        if (!p->open || p->writing) co_return;
        auto lifetime = get_strong();
        auto dispatcher = window.Dispatcher();
        using namespace Windows::Networking::Sockets;
        p->writing = true;
        while (!p->over && !p->queue.empty()) {
            auto [binary, payload] = p->queue.front();
            p->queue.pop_front();
            bool failed = false;
            try {
                p->socket.Control().MessageType(binary ? SocketMessageType::Binary : SocketMessageType::Utf8);
                if (binary) p->writer.WriteBuffer(Windows::Security::Cryptography::CryptographicBuffer::DecodeFromBase64String(payload));
                else p->writer.WriteString(payload);
                co_await p->writer.StoreAsync();
            } catch (...) { failed = true; }
            co_await resume_foreground(dispatcher);
            if (p->over) break;
            if (failed) { end_pipe(id, p, 1006, true); break; }
            tell(id, p->page, L"sent", 0);
        }
        p->writing = false;
    }

    // Ends a link: closed by the page (nothing said back), or lost or closed by the other side (the page is told).
    void end_pipe(double id, std::shared_ptr<Pipe> const& p, int code, bool say_so) {
        if (p->over) return;
        p->over = true;
        auto found = pipes.find(id);
        if (found != pipes.end() && found->second == p) pipes.erase(found);
        if (auto local = p->local) { p->local = nullptr; local->lost(); }
        try { if (p->socket) p->socket.Close(1000, L""); } catch (...) {}
        p->socket = nullptr;
        p->writer = nullptr;
        p->queue.clear();
        if (say_so) tell(id, p->page, L"close", code);
    }

    // Every link ends: the page that opened them has gone (code 0, nothing said), or they may have (said).
    void end_pipes(int code) {
        auto all = pipes;
        for (auto const& [id, p] : all) end_pipe(id, p, code, code != 0);
    }

    void tell(double id, uint64_t asked, const wchar_t* ev, int code) {
        if (!web || asked != page || !is_app_page(web.Source())) return;
        JsonObject out;
        out.SetNamedValue(L"lamp", JsonValue::CreateStringValue(L"ws"));
        out.SetNamedValue(L"id", JsonValue::CreateNumberValue(id));
        out.SetNamedValue(L"ev", JsonValue::CreateStringValue(ev));
        if (code) out.SetNamedValue(L"code", JsonValue::CreateNumberValue(code));
        web.PostWebMessageAsJson(out.Stringify());
    }

    // This console's addresses on the home network, so a page that remembers nothing looks for the others on it.
    void here() {
        Windows::Data::Json::JsonArray list;
        try {
            for (auto const& name : Windows::Networking::Connectivity::NetworkInformation::GetHostNames())
                if (name.Type() == Windows::Networking::HostNameType::Ipv4 && is_private_v4(name.CanonicalName()))
                    list.Append(JsonValue::CreateStringValue(name.CanonicalName()));
        } catch (...) {}
        if (!web || !is_app_page(web.Source())) return;
        JsonObject out;
        out.SetNamedValue(L"lamp", JsonValue::CreateStringValue(L"ws"));
        out.SetNamedValue(L"ev", JsonValue::CreateStringValue(L"here"));
        out.SetNamedValue(L"addresses", list);
        web.PostWebMessageAsJson(out.Stringify());
    }

    // MARK: Phones as controllers

    // The page's own link to the relay, over the pipe: what the relay says goes to the page as the link's messages.
    struct PagePeer : lampc::Peer {
        View* view = nullptr;
        double id = 0;
        uint64_t page = 0;
        bool open = true;
        bool is_open() const override { return open; }
        size_t pending_text() const override { return 0; }
        void send_text(std::string const& text) override { if (open) view->tell_link(id, page, &text, nullptr); }
        bool send_piece(std::string piece) override {
            if (!open) return false;
            view->tell_link(id, page, nullptr, &piece);
            return true;
        }
        void close(int code) override {
            if (!open) return;
            open = false;
            view->end_local(id, code);
            on_close();
        }
        // The page closed it, or went away.
        void lost() {
            if (!open) return;
            open = false;
            on_close();
        }
    };

    // A connection to the page or the relay: its request's head until it's answered, then the WebSocket it became.
    struct Conn {
        Windows::Networking::Sockets::StreamSocket socket{ nullptr };
        Windows::Storage::Streams::DataWriter writer{ nullptr };
        std::string from, buffer;
        int64_t since = lampc::wall_ms();
        bool relay = false, answered = false;
        std::shared_ptr<lampc::SocketPeer> peer;
    };
    // How long an answered page request may take to go: a phone on a slow network gets the page, one that stops reading
    // doesn't keep its connection (and the file held for it) for good.
    static constexpr int64_t phone_send_deadline_ms = 60000;

    struct PhoneAsk {
        bool stop = false;
        double id = 0;
        uint64_t page = 0;
    };

    // All of it touched only on the window's thread. A session is the key, the relay and both listeners; its number
    // changes as it closes, so what an earlier one had started is dropped.
    std::unique_ptr<lampc::Relay> phones;
    std::string phone_key, phone_app;
    std::set<std::string> phone_hosts;
    Windows::Networking::Sockets::StreamSocketListener relay_listener{ nullptr }, page_listener{ nullptr };
    std::optional<uint16_t> relay_port, page_port;
    std::vector<std::shared_ptr<Conn>> conns;
    Windows::System::Threading::ThreadPoolTimer phone_ticks{ nullptr };
    uint64_t phone_session = 0;
    // The page's asks, one at a time, so a stop and the start after it happen in the order they were asked.
    std::deque<PhoneAsk> phone_asks;
    bool phone_busy = false;
    // When the page last asked for its session (every 15 s while it plays): a session no page asks for any more is
    // ended, even if it never had a host, so a page gone without stopping leaves nothing listening.
    int64_t phone_asked_at = 0;
    static constexpr int64_t phone_unasked_ms = 45000;

    void phone_ask(PhoneAsk ask) {
        phone_asks.push_back(ask);
        if (!phone_busy) phone_run();
    }

    fire_and_forget phone_run() {
        auto lifetime = get_strong();
        phone_busy = true;
        while (!phone_asks.empty()) {
            auto ask = phone_asks.front();
            phone_asks.pop_front();
            // An ask from a page that has gone since opens nothing.
            if (ask.page != page) continue;
            if (ask.stop) {
                phones_close(L"the game stopped its controllers");
                answer_phones(ask, 200, JsonObject());
            } else {
                co_await phones_open(ask);
                co_await resume_foreground(window.Dispatcher());
            }
        }
        phone_busy = false;
    }

    void answer_phones(PhoneAsk const& ask, int status, JsonObject const& body) {
        if (!web || ask.page != page || !is_app_page(web.Source())) return;
        JsonObject out;
        out.SetNamedValue(L"lamp", JsonValue::CreateStringValue(L"controllers"));
        out.SetNamedValue(L"id", JsonValue::CreateNumberValue(ask.id));
        out.SetNamedValue(L"status", JsonValue::CreateNumberValue(status));
        out.SetNamedValue(L"body", body);
        web.PostWebMessageAsJson(out.Stringify());
    }

    void refuse_phones(PhoneAsk const& ask, int status, const wchar_t* error) {
        JsonObject body;
        body.SetNamedValue(L"error", JsonValue::CreateStringValue(error));
        answer_phones(ask, status, body);
    }

    // The game's session, opened if it isn't: where its page's link goes, with a host's credential. Asked as
    // Lamp.controllers starts and every few seconds after, which also tells the relay where the page is now.
    Windows::Foundation::IAsyncAction phones_open(PhoneAsk ask) {
        auto lifetime = get_strong();
        auto dispatcher = window.Dispatcher();
        WIN32_FILE_ATTRIBUTE_DATA index{};
        if (!GetFileAttributesExW((installed + L"\\Phone\\index.html").c_str(), GetFileExInfoStandard, &index)) {
            refuse_phones(ask, 409, L"The game has no phone page yet: put one in Phone/index.html.");
            co_return;
        }
        // Never a link to the console itself: a phone opening it would reach itself.
        auto link = link_host();
        if (!link) {
            phones_close(L"the console isn't on a network");
            refuse_phones(ask, 503, L"This console isn't on a network phones can join. Join one, and phones can play again.");
            co_return;
        }
        uint64_t session = phone_session;
        phone_asked_at = lampc::wall_ms();
        if (!phones) {
            if (phone_app.empty()) phone_app = to_string(Windows::ApplicationModel::Package::Current().Id().Name());
            phone_key = lampc::random_text(32);
            phones = std::make_unique<lampc::Relay>(phone_app, phone_key);
            say_line(L"Lamp: phones' session opened.");
        }
        for (bool relay : { true, false }) {
            auto& listener = relay ? relay_listener : page_listener;
            if (listener) continue;
            Windows::Networking::Sockets::StreamSocketListener made;
            made.ConnectionReceived([this, relay, session, dispatcher](auto const&, Windows::Networking::Sockets::StreamSocketListenerConnectionReceivedEventArgs const& args) {
                auto socket = args.Socket();
                dispatcher.RunAsync(CoreDispatcherPriority::Normal, [this, socket, relay, session] { phone_connected(socket, relay, session); });
            });
            bool bound = true;
            try { co_await made.BindServiceNameAsync(L""); } catch (hresult_error const& e) {
                say(L"Lamp: the %ls for phones couldn't listen (0x%08x).", relay ? L"relay" : L"page", (unsigned)e.code());
                bound = false;
            }
            co_await resume_foreground(dispatcher);
            if (session != phone_session || !bound) {
                try { made.Close(); } catch (...) {}
                if (session == phone_session) phones_close(L"a listener couldn't open");
                refuse_phones(ask, 503, relay ? L"The link for phones couldn't open on this console." : L"The phone page couldn't open on this console.");
                co_return;
            }
            uint16_t port = (uint16_t)_wtoi(made.Information().LocalPort().c_str());
            (relay ? relay_port : page_port) = port;
            listener = made;
            say(L"Lamp: the %ls for phones listens at port %u.", relay ? L"relay" : L"page", (unsigned)port);
        }
        if (!phone_ticks) {
            phone_ticks = Windows::System::Threading::ThreadPoolTimer::CreatePeriodicTimer([this, session, dispatcher](auto const&) {
                dispatcher.RunAsync(CoreDispatcherPriority::Normal, [this, session] { phone_tick(session); });
            }, std::chrono::seconds(1));
        }
        phone_hosts = host_names();
        std::string address = "http://" + to_string(*link) + ":" + std::to_string(*page_port) + "/";
        phones->configure(address, page_port, phone_hosts);
        JsonObject relay;
        relay.SetNamedValue(L"kind", JsonValue::CreateStringValue(L"relay"));
        relay.SetNamedValue(L"socket", JsonValue::CreateStringValue(g_relay_link));
        relay.SetNamedValue(L"app", JsonValue::CreateStringValue(to_hstring(phone_app)));
        relay.SetNamedValue(L"credential", JsonValue::CreateStringValue(to_hstring(phones->host_credential())));
        Windows::Data::Json::JsonArray links;
        links.Append(relay);
        JsonObject body;
        body.SetNamedValue(L"links", links);
        body.SetNamedValue(L"renew", JsonValue::CreateNumberValue(15));
        answer_phones(ask, 200, body);
    }

    // Ends the session: every phone and the page's link let go, both listeners closed and the key forgotten.
    void phones_close(const wchar_t* why) {
        bool was = phones != nullptr;
        phone_session++;
        if (phone_ticks) { phone_ticks.Cancel(); phone_ticks = nullptr; }
        if (phones) { phones->stop(); phones.reset(); }
        for (auto* listener : { &relay_listener, &page_listener }) {
            if (*listener) { try { listener->Close(); } catch (...) {} *listener = nullptr; }
        }
        relay_port.reset();
        page_port.reset();
        std::fill(phone_key.begin(), phone_key.end(), '\0');
        phone_key.clear();
        // A phone's socket saying why it closes gets a moment for it to go; everything else goes now.
        auto left = std::move(conns);
        conns.clear();
        std::vector<Windows::Networking::Sockets::StreamSocket> closing;
        for (auto& conn : left) {
            if (conn->peer && conn->peer->transport) closing.push_back(conn->socket);
            else try { conn->socket.Close(); } catch (...) {}
        }
        if (!closing.empty()) Windows::System::Threading::ThreadPoolTimer::CreateTimer([closing](auto const&) {
            for (auto const& socket : closing) try { socket.Close(); } catch (...) {}
        }, std::chrono::seconds(2));
        if (was) say(L"Lamp: phones' session ended: %ls.", why);
    }

    void phone_tick(uint64_t session) {
        if (session != phone_session || !phones) return;
        int64_t now = lampc::wall_ms();
        if (now - phone_asked_at > phone_unasked_ms) return phones_close(L"the page stopped asking for it");
        phones->tick();
        for (auto const& conn : std::vector<std::shared_ptr<Conn>>(conns)) {
            if (conn->peer) conn->peer->tick(now);
            // A request never finished, or an answer never taken, is let go before it can use up what the game needs for phones.
            else if (now - conn->since > (conn->answered ? phone_send_deadline_ms : lampc::page::head_deadline_ms)) { try { conn->socket.Close(); } catch (...) {} }
        }
    }

    void phone_connected(Windows::Networking::Sockets::StreamSocket const& socket, bool relay, uint64_t session) {
        if (session != phone_session || !phones) { try { socket.Close(); } catch (...) {} return; }
        auto conn = std::make_shared<Conn>();
        conn->socket = socket;
        conn->writer = Windows::Storage::Streams::DataWriter(socket.OutputStream());
        conn->from = remote_of(socket);
        conn->relay = relay;
        size_t mine = std::count_if(conns.begin(), conns.end(), [&](auto const& c) { return c->from == conn->from; });
        if (conns.size() >= lampc::page::connection_limit_all || mine >= lampc::page::connection_limit_each) { try { socket.Close(); } catch (...) {} return; }
        conns.push_back(conn);
        phone_read(conn, session);
    }

    fire_and_forget phone_read(std::shared_ptr<Conn> conn, uint64_t session) {
        auto lifetime = get_strong();
        auto dispatcher = window.Dispatcher();
        Windows::Storage::Streams::Buffer buffer(16384);
        try {
            for (;;) {
                auto got = co_await conn->socket.InputStream().ReadAsync(buffer, buffer.Capacity(), Windows::Storage::Streams::InputStreamOptions::Partial);
                co_await resume_foreground(dispatcher);
                if (got.Length() == 0) break;
                phone_heard(conn, std::string_view(reinterpret_cast<const char*>(got.data()), got.Length()), session);
            }
        } catch (...) {}
        co_await resume_foreground(dispatcher);
        conns.erase(std::remove(conns.begin(), conns.end(), conn), conns.end());
        if (conn->peer) conn->peer->lost();
    }

    void phone_write_then_close(std::shared_ptr<Conn> const& conn, std::string bytes) {
        StreamTransport::send(conn->writer, window.Dispatcher(), std::move(bytes), [conn](bool) { try { conn->socket.Close(); } catch (...) {} });
    }

    void phone_heard(std::shared_ptr<Conn> const& conn, std::string_view bytes, uint64_t session) {
        if (conn->peer) return conn->peer->received(bytes);
        if (conn->answered) return;
        conn->buffer.append(bytes.data(), bytes.size());
        auto end = conn->buffer.find("\r\n\r\n");
        if (end == std::string::npos) {
            if (conn->buffer.size() > lampc::page::head_limit) { try { conn->socket.Close(); } catch (...) {} }
            return;
        }
        std::string head = conn->buffer.substr(0, end), rest = conn->buffer.substr(end + 4);
        conn->buffer.clear();
        conn->answered = true;
        if (session != phone_session || !phones) { try { conn->socket.Close(); } catch (...) {} return; }
        if (!conn->relay) {
            auto answer = lampc::page::answer(head, phone_hosts, relay_port, phone_app, [this](auto const& steps) { return phone_file(steps); });
            return phone_write_then_close(conn, lampc::page::response(answer));
        }
        auto upgrade = lampc::ws::upgrade(head);
        if (!upgrade) return phone_write_then_close(conn, lampc::ws::refused(400));
        if (!phones->admits(upgrade->origin)) return phone_write_then_close(conn, lampc::ws::refused(403));
        auto peer = std::make_shared<lampc::SocketPeer>(std::make_unique<StreamTransport>(conn->socket, conn->writer, window.Dispatcher()));
        if (!phones->accept(peer, conn->from, false)) { try { conn->socket.Close(); } catch (...) {} return; }
        conn->peer = peer;
        peer->queue_text(lampc::ws::accepted(upgrade->key));
        if (!rest.empty()) peer->received(rest);
    }

    // A file of the phone page in the package, by its checked steps: a plain file, reached through no link.
    std::optional<std::string> phone_file(std::vector<std::string> const& steps) {
        std::wstring path = installed + L"\\Phone";
        WIN32_FILE_ATTRIBUTE_DATA data{};
        for (auto const& step : steps) {
            path += L"\\" + std::wstring(to_hstring(step));
            if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)
                || (data.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM))) return std::nullopt;
        }
        if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) return std::nullopt;
        uint64_t size = (uint64_t)data.nFileSizeHigh << 32 | data.nFileSizeLow;
        if (size > lampc::page::file_limit) return std::nullopt;
        FILE* file = _wfopen(path.c_str(), L"rb");
        if (!file) return std::nullopt;
        std::string out((size_t)size, '\0');
        size_t read = size ? fread(out.data(), 1, out.size(), file) : 0;
        fclose(file);
        if (read != out.size()) return std::nullopt;
        return out;
    }

    // The page opening its link to the relay: the link goes into the relay here, as the one peer that may be the game's host.
    void open_local(double id) {
        if (pipes.count(id) || pipes.size() >= 64 || !phones) return tell(id, page, L"close", 1006);
        auto p = std::make_shared<Pipe>();
        p->page = page;
        p->open = true;
        auto peer = std::make_shared<PagePeer>();
        peer->view = this;
        peer->id = id;
        peer->page = page;
        p->local = peer;
        pipes[id] = p;
        if (!phones->accept(peer, "page", true)) {
            pipes.erase(id);
            return tell(id, page, L"close", 1006);
        }
        tell(id, page, L"open", 0);
    }

    // What the page sent on its link to the relay.
    void to_local(double id, std::shared_ptr<Pipe> const& p, bool binary, hstring const& payload) {
        auto peer = p->local;
        if (!peer->open) return;
        peer->heard = lampc::wall_ms();
        if (binary) {
            std::string bytes;
            try {
                auto decoded = Windows::Security::Cryptography::CryptographicBuffer::DecodeFromBase64String(payload);
                bytes.assign(reinterpret_cast<const char*>(decoded.data()), decoded.Length());
            } catch (...) { return end_pipe(id, p, 1007, true); }
            peer->on_binary(bytes);
        } else {
            std::string text = to_string(payload);
            if (text.size() > lampc::wire::message) return peer->close(1009);
            peer->on_text(text);
        }
        tell(id, p->page, L"sent", 0);
    }

    // The relay closing the page's link: the page is told, with the relay's reason.
    void end_local(double id, int code) {
        auto found = pipes.find(id);
        if (found == pipes.end() || !found->second->local) return;
        auto p = found->second;
        p->local = nullptr;
        end_pipe(id, p, code, true);
    }

    void tell_link(double id, uint64_t asked, std::string const* text, std::string const* piece) {
        if (!web || asked != page || !is_app_page(web.Source())) return;
        JsonObject out;
        out.SetNamedValue(L"lamp", JsonValue::CreateStringValue(L"ws"));
        out.SetNamedValue(L"id", JsonValue::CreateNumberValue(id));
        out.SetNamedValue(L"ev", JsonValue::CreateStringValue(L"message"));
        if (text) out.SetNamedValue(L"text", JsonValue::CreateStringValue(to_hstring(*text)));
        else out.SetNamedValue(L"data", JsonValue::CreateStringValue(to_hstring(lampc::base64(*piece, false))));
        web.PostWebMessageAsJson(out.Stringify());
    }

    // How far a controller's reading is from what the page showed on its gamepad, in the standard mapping: the sum of
    // the differences of its buttons and sticks.
    static double distance(Windows::Gaming::Input::GamepadReading const& r, JsonObject const& m) {
        using Windows::Gaming::Input::GamepadButtons;
        static const GamepadButtons order[] = { GamepadButtons::A, GamepadButtons::B, GamepadButtons::X, GamepadButtons::Y,
            GamepadButtons::LeftShoulder, GamepadButtons::RightShoulder, GamepadButtons::None, GamepadButtons::None,
            GamepadButtons::View, GamepadButtons::Menu, GamepadButtons::LeftThumbstick, GamepadButtons::RightThumbstick,
            GamepadButtons::DPadUp, GamepadButtons::DPadDown, GamepadButtons::DPadLeft, GamepadButtons::DPadRight };
        auto buttons = m.GetNamedArray(L"buttons", Windows::Data::Json::JsonArray());
        auto axes = m.GetNamedArray(L"axes", Windows::Data::Json::JsonArray());
        double sum = 0;
        for (uint32_t i = 0; i < buttons.Size() && i < 16; i++) {
            double mine = i == 6 ? r.LeftTrigger : i == 7 ? r.RightTrigger : (r.Buttons & order[i]) == order[i] ? 1.0 : 0.0;
            sum += std::abs(buttons.GetNumberAt(i) - mine);
        }
        // The page's sticks point down where the controller's point up.
        const double sticks[] = { r.LeftThumbstickX, -r.LeftThumbstickY, r.RightThumbstickX, -r.RightThumbstickY };
        for (uint32_t i = 0; i < axes.Size() && i < 4; i++) sum += std::abs(axes.GetNumberAt(i) - sticks[i]);
        return sum;
    }

    // The controller the page knows by this index. The page's web view numbers controllers in its own order, so the one
    // whose reading matches what the page showed is it, kept for later effects asked while nothing tells two apart (no
    // button held, sticks at rest). Until one is found: the only controller, or the same place in the console's list.
    Windows::Gaming::Input::Gamepad pad(int index, JsonObject const& m) {
        auto list = Windows::Gaming::Input::Gamepad::Gamepads();
        auto& known = rumbles[index].pad;
        bool there = false;
        for (auto const& p : list) there = there || p == known;
        if (!there) known = nullptr;
        if (list.Size() > 1) {
            double best = 1e9, next = 1e9;
            Windows::Gaming::Input::Gamepad found{ nullptr };
            for (auto const& p : list) {
                double d = distance(p.GetCurrentReading(), m);
                if (d < best) { next = best; best = d; found = p; } else if (d < next) next = d;
            }
            if (found && best < 0.5 && next - best > 0.5) {
                uint32_t at = 0;
                if (found != known && list.IndexOf(found, at)) say(L"Lamp: the page's controller %d is the console's %u.", index, at);
                known = found;
                // Another of the page's gamepads that was taken for this controller ends what it played there first, so its
                // timers neither stop this effect early nor are left with no controller to still.
                for (int i = 0; i < 4; i++) if (i != index && rumbles[i].pad == found) { still(i); rumbles[i].pad = nullptr; }
            }
        }
        if (known) return known;
        if (list.Size() == 1) return list.GetAt(0);
        return (uint32_t)index < list.Size() ? list.GetAt(index) : nullptr;
    }

    // Ends what's playing for the page's controller, now.
    void still(int index) {
        auto& r = rumbles[index];
        if (r.start) r.start.Cancel();
        if (r.stop) r.stop.Cancel();
        std::lock_guard held(shaking);
        r.effect++;
        if (r.pad) r.pad.Vibration({});
    }

    // One of the page's effects: its motors and triggers at the strengths asked, after its delay, for its duration.
    void rumble(JsonObject const& m) {
        int index = (int)m.GetNamedNumber(L"pad", 0);
        if (index < 0 || index > 3) return;
        auto amount = [&](const wchar_t* key) { return (double)std::clamp(m.GetNamedNumber(key, 0), 0.0, 1.0); };
        auto ms = [&](const wchar_t* key) { return std::chrono::milliseconds((int64_t)std::clamp(m.GetNamedNumber(key, 0), 0.0, 5000.0)); };
        Windows::Gaming::Input::GamepadVibration shake{};
        shake.LeftMotor = amount(L"strong");
        shake.RightMotor = amount(L"weak");
        shake.LeftTrigger = amount(L"leftTrigger");
        shake.RightTrigger = amount(L"rightTrigger");
        auto delay = ms(L"delay"), duration = ms(L"duration");
        still(index);
        auto& r = rumbles[index];
        auto target = pad(index, m);
        // Kept as the one playing even before it's matched, so a reset stops what was started on it.
        if (!r.pad) r.pad = target;
        if (duration.count() == 0) return;
        if (!target) { say(L"Lamp: the page asked to shake controller %d, and none is connected.", index); return; }
        uint64_t effect = r.effect;
        using Windows::System::Threading::ThreadPoolTimer;
        // The timers' work is skipped once another effect has taken this one's place.
        auto set = [this, index, effect, target](Windows::Gaming::Input::GamepadVibration v) {
            std::lock_guard held(shaking);
            if (rumbles[index].effect == effect) target.Vibration(v);
        };
        if (delay.count() == 0) set(shake);
        else r.start = ThreadPoolTimer::CreateTimer([set, shake](auto const&) { set(shake); }, delay);
        r.stop = ThreadPoolTimer::CreateTimer([set](auto const&) { set({}); }, delay + duration);
    }

    // A link out of the app, in the console's own browser.
    fire_and_forget elsewhere(std::wstring uri) {
        try {
            Windows::Foundation::Uri target(uri);
            if (target.SchemeName() != L"https" && target.SchemeName() != L"http") co_return;
            co_await Windows::System::Launcher::LaunchUriAsync(target);
        } catch (...) {}
    }

    // Opens a blank page first to learn the CSS width the web view gives the window, then zooms so the app's page
    // is 1920 CSS pixels wide, before the app's page opens.
    Windows::Foundation::IAsyncAction fit_page() {
        auto lifetime = get_strong();
        try {
            winrt::handle opened{ CreateEventW(nullptr, TRUE, FALSE, nullptr) };
            auto token = web.NavigationCompleted([&](auto const&, auto const&) { SetEvent(opened.get()); });
            web.Navigate(L"about:blank");
            co_await resume_on_signal(opened.get(), std::chrono::seconds(5));
            co_await resume_foreground(window.Dispatcher());
            web.NavigationCompleted(token);
            auto width = co_await web.ExecuteScriptAsync(L"window.innerWidth");
            double css = _wtof(width.c_str());
            if (css > 0) {
                double zoom = controller.ZoomFactor() * css / 1920.0;
                controller.ZoomFactor(zoom);
                say(L"Lamp: the page is 1920 CSS pixels wide (the web view gave %.0f, zoomed to %.3f).", css, zoom);
            }
        } catch (hresult_error const& e) {
            say(L"Lamp: the page's size couldn't be set (0x%08x).", (unsigned)e.code());
        }
    }

    void Run() {
        window.Activate();
        start();
        window.Dispatcher().ProcessEvents(CoreProcessEventsOption::ProcessUntilQuit);
    }
};

// Anything that stops the host before or outside WinRT's own error handling goes to the log too.
static LONG WINAPI last_words(EXCEPTION_POINTERS* info) {
    say(L"Lamp: the app stopped on exception 0x%08x.", (unsigned)info->ExceptionRecord->ExceptionCode);
    return EXCEPTION_CONTINUE_SEARCH;
}

int __stdcall wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    init_apartment();
    try {
        std::wstring local(Windows::Storage::ApplicationData::Current().LocalFolder().Path());
        g_log = _wfopen((local + L"\\log.txt").c_str(), L"wb");
    } catch (...) {}
    say_line(L"Lamp: the app started.");
    SetUnhandledExceptionFilter(last_words);
    try {
        CoreApplication::Run(make<View>());
    } catch (hresult_error const& e) {
        say(L"Lamp: the app couldn't run (0x%08x): %ls", (unsigned)e.code(), e.message().c_str());
    }
    return 0;
}
