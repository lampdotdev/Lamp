// Lamp's web host on the Xbox: the same program for every web app, beside the app's Web/ folder in its package.
//
// A full-screen CoreWindow holding a WebView2 (Chromium, which the console keeps up to date) that shows Web/index.html
// from the package, served at https://lamp.example/ by WebView2's own mapping of a host name to a folder, so pages load
// their files with fetch as they would from a site. No XAML: the page is drawn into a composition visual, as WinUI's
// control does it. The page's console, its uncaught errors, text it posts with chrome.webview.postMessage and what the
// host itself has to say go to log.txt in the app's own folder, which Device Portal reads back.
//
// lamp.js reaches Lamp on the Mac through the host (`http` messages): the page is https and Lamp's gateway plain http
// on the home network, which Chromium won't let the page call itself. Only the app's own page may ask, only Lamp's own
// paths are passed on, and an answer goes only to the page that asked: the app's token and its AI's answers are in
// them. A link to anywhere else opens in the console's browser, never in this web view.
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
#include <winrt/Microsoft.Web.WebView2.Core.h>
#include <cstdio>
#include <string>

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

struct View : implements<View, IFrameworkViewSource, IFrameworkView> {
    CoreWindow window{ nullptr };
    CoreWebView2Controller controller{ nullptr };
    CoreWebView2 web{ nullptr };
    CoreWebView2DevToolsProtocolEventReceiver consoleCalls{ nullptr }, uncaught{ nullptr };
    // The page is drawn into this visual, the window's only content: WebView2 on the Xbox is hosted the way WinUI's
    // control hosts it, through composition, since a controller given the CoreWindow itself ends the app.
    Windows::UI::Composition::Compositor compositor{ nullptr };
    Windows::UI::Composition::CompositionTarget target{ nullptr };
    Windows::UI::Composition::ContainerVisual root{ nullptr };
    std::wstring installed;
    // Counts the page's top-level navigations, so an answer to a page that has since gone is dropped.
    uint64_t page = 0;

    IFrameworkView CreateView() { return *this; }

    void Initialize(CoreApplicationView const&) {
        installed = std::wstring(Windows::ApplicationModel::Package::Current().InstalledLocation().Path());
        CoreApplication::Suspending([](auto const&, auto const&) { say_line(L"Lamp: the console set the app aside."); });
        CoreApplication::Resuming([](auto const&, auto const&) { say_line(L"Lamp: the app came back."); });
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
        window.VisibilityChanged([this](auto const&, VisibilityChangedEventArgs const& args) {
            if (controller) controller.IsVisible(args.Visible());
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
            auto env = co_await CoreWebView2Environment::CreateAsync();
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
            web.SetVirtualHostNameToFolderMapping(L"lamp.example", hstring(installed + L"\\Web"), CoreWebView2HostResourceAccessKind::Allow);
            web.WebMessageReceived([this](auto const&, CoreWebView2WebMessageReceivedEventArgs const& args) {
                JsonObject message{ nullptr };
                if (JsonObject::TryParse(args.WebMessageAsJson(), message) && message.GetNamedString(L"lamp", L"") == L"http") {
                    if (is_app_page(args.Source())) relay(message);
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
                if (is_app_page(uri) || uri == L"about:blank") { page++; return; }
                args.Cancel(true);
                elsewhere(uri);
            });
            web.NewWindowRequested([this](auto const& sender, CoreWebView2NewWindowRequestedEventArgs const& args) {
                args.Handled(true);
                std::wstring uri(args.Uri());
                if (is_app_page(uri)) sender.Navigate(args.Uri()); else elsewhere(uri);
            });
            co_await fit_page();
            web.Navigate(L"https://lamp.example/index.html");
            controller.MoveFocus(CoreWebView2MoveFocusReason::Programmatic);
        } catch (hresult_error const& e) {
            say(L"Lamp: WebView2 couldn't start (0x%08x): %ls", (unsigned)e.code(), e.message().c_str());
        }
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
        try {
            Windows::Foundation::Uri url(message.GetNamedString(L"url", L""));
            std::wstring path(url.Path());
            bool lamps = path.rfind(L"/ai", 0) == 0 || path.rfind(L"/app/", 0) == 0;
            if (url.SchemeName() != L"http" || !lamps || !url.UserName().empty()) throw hresult_invalid_argument(L"not one of Lamp's paths");
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
        } catch (hresult_error const& e) {
            say(L"Lamp: a call to Lamp on the Mac failed (0x%08x): %ls", (unsigned)e.code(), e.message().c_str());
            answer.SetNamedValue(L"error", JsonValue::CreateStringValue(e.message()));
        }
        co_await resume_foreground(dispatcher);
        if (web && page == asked && is_app_page(web.Source())) web.PostWebMessageAsJson(answer.Stringify());
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
