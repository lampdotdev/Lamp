// Lamp's game kit: the host on the Xbox. Lamp writes this file before every build.
//
// A full-screen app with its own CoreWindow: a Direct3D 11 device and a flip swap chain at 1920x1080 with a depth
// buffer, the controllers through Windows.Gaming.Input, the game's assets read from the package and its saves and
// log kept in the app's own folder, which Device Portal reads back. Presented with vsync every frame: without it the
// console ends the app after its first frame.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11_1.h>
#include <dxgi1_3.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.ApplicationModel.Core.h>
#include <winrt/Windows.UI.Core.h>
#include <winrt/Windows.Gaming.Input.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.System.h>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <string>
#include "lamp_game.h"
#include "lamp_host.h"

using namespace winrt;
using namespace Windows::ApplicationModel::Core;
using namespace Windows::UI::Core;
using namespace Windows::Gaming::Input;

static FILE* g_log = nullptr;
static std::wstring g_local;     // the app's own folder, where its log and saves are
static std::wstring g_installed; // where the package is, with Assets\ in it
static Gamepad g_rumble[4] = { nullptr, nullptr, nullptr, nullptr };

extern "C" void lamp_log(const char* format, ...) {
    if (!g_log) return;
    va_list args;
    va_start(args, format);
    vfprintf(g_log, format, args);
    va_end(args);
    fputc('\n', g_log);
    fflush(g_log);
}

// A path inside a folder, from a game's relative one: no drive, no "..", forward slashes made Windows'.
static bool inside(const std::wstring& folder, const char* path, std::wstring& out) {
    if (!path || !*path || path[0] == '/' || strchr(path, '\\') || strchr(path, ':')) return false;
    std::string p(path);
    if (("/" + p + "/").find("/../") != std::string::npos) return false;
    out = folder + L"\\";
    for (char c : p) out += (c == '/') ? L'\\' : (wchar_t)(unsigned char)c;
    return true;
}

static LampFile read_whole(const std::wstring& path) {
    LampFile file = { nullptr, 0 };
    FILE* f = _wfopen(path.c_str(), L"rb");
    if (!f) return file;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size >= 0) {
        file.data = malloc((size_t)size + 1);
        if (file.data && fread(file.data, 1, (size_t)size, f) == (size_t)size) {
            ((char*)file.data)[size] = 0;   // a text file can be read as a C string
            file.size = (size_t)size;
        } else { free(file.data); file.data = nullptr; }
    }
    fclose(f);
    return file;
}

extern "C" LampFile lamp_asset(const char* path) {
    std::wstring full;
    if (!inside(g_installed + L"\\Assets", path, full)) { lamp_log("lamp_asset: \"%s\" isn't a path inside Assets/", path ? path : ""); return { nullptr, 0 }; }
    LampFile file = read_whole(full);
    if (!file.data) lamp_log("lamp_asset: no Assets/%s in the package", path);
    return file;
}

static bool save_path(const char* name, std::wstring& out) {
    if (!name || !*name) return false;
    for (const char* c = name; *c; c++) if (!isalnum((unsigned char)*c) && *c != '-' && *c != '_' && *c != '.') return false;
    std::string n(name);
    if (n.find("..") != std::string::npos) return false;
    return inside(g_local, ("save-" + n).c_str(), out);
}

extern "C" LampFile lamp_load(const char* name) {
    std::wstring path;
    if (!save_path(name, path)) return { nullptr, 0 };
    return read_whole(path);
}

extern "C" bool lamp_save(const char* name, const void* data, size_t size) {
    std::wstring path, temp;
    if (!save_path(name, path)) { lamp_log("lamp_save: \"%s\" isn't a name (letters, digits, - _ .)", name ? name : ""); return false; }
    temp = path + L".new";
    FILE* f = _wfopen(temp.c_str(), L"wb");
    if (!f) return false;
    bool ok = fwrite(data, 1, size, f) == size;
    ok = fclose(f) == 0 && ok;
    // Written whole beside it, then put in its place, so a save cut short never leaves half a file.
    return ok && MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING);
}

extern "C" void lamp_rumble(int pad, float low, float high) {
    if (pad < 0 || pad > 3 || !g_rumble[pad]) return;
    GamepadVibration v{};
    v.LeftMotor = low; v.RightMotor = high;
    g_rumble[pad].Vibration(v);
}

static const int W = 1920, H = 1080;

struct View : implements<View, IFrameworkViewSource, IFrameworkView> {
    com_ptr<ID3D11Device> device;
    com_ptr<ID3D11DeviceContext> context;
    com_ptr<IDXGISwapChain1> swap;
    com_ptr<ID3D11RenderTargetView> rtv;
    com_ptr<ID3D11DepthStencilView> dsv;
    bool ready = false;
    uint32_t before[4] = {};

    IFrameworkView CreateView() { return *this; }

    void Initialize(CoreApplicationView const&) {
        g_local = std::wstring(Windows::Storage::ApplicationData::Current().LocalFolder().Path());
        g_installed = std::wstring(Windows::ApplicationModel::Package::Current().InstalledLocation().Path());
        g_log = _wfopen((g_local + L"\\log.txt").c_str(), L"w");
        lamp_log("Lamp: the game started.");
        // An Xbox gives a package installed as a game about 5 GB and one installed as an app 1 GB: which it got.
        lamp_log("Lamp: the console lets the game use %llu MB of memory.",
                 (unsigned long long)(Windows::System::MemoryManager::AppMemoryUsageLimit() >> 20));
        std::set_terminate([] { lamp_log("Lamp: the game stopped on an exception it didn't catch."); abort(); });
        // A game that's set aside gives back what memory it can, as the console asks.
        CoreApplication::Suspending([this](auto const&, auto const&) {
            lamp_log("Lamp: the console set the game aside.");
            if (device) if (auto dxgi = device.try_as<IDXGIDevice3>()) dxgi->Trim();
        });
        CoreApplication::Resuming([](auto const&, auto const&) { lamp_log("Lamp: the game came back."); });
    }

    void Load(hstring const&) {}
    void Uninitialize() {}

    void SetWindow(CoreWindow const& window) {
        // B on the controller is the game's: without this the console takes it as Back and leaves the game.
        Windows::UI::Core::SystemNavigationManager::GetForCurrentView().BackRequested([](auto const&, BackRequestedEventArgs const& args) { args.Handled(true); });
        D3D_FEATURE_LEVEL levels[] = { D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0 };
        D3D_FEATURE_LEVEL got{};
        HRESULT hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                                       levels, 2, D3D11_SDK_VERSION, device.put(), &got, context.put());
        if (FAILED(hr)) { lamp_log("Lamp: Direct3D 11 couldn't start (0x%08x).", (unsigned)hr); return; }
        com_ptr<IDXGIDevice1> dxgi = device.as<IDXGIDevice1>();
        com_ptr<IDXGIAdapter> adapter;
        dxgi->GetAdapter(adapter.put());
        com_ptr<IDXGIFactory2> factory;
        adapter->GetParent(IID_PPV_ARGS(factory.put()));
        DXGI_ADAPTER_DESC ad{};
        adapter->GetDesc(&ad);
        char name[128];
        WideCharToMultiByte(CP_UTF8, 0, ad.Description, -1, name, sizeof name, nullptr, nullptr);
        lamp_log("Lamp: drawing with %s, Direct3D feature level %x.", name, (unsigned)got);
        DXGI_SWAP_CHAIN_DESC1 d{};
        d.Width = W; d.Height = H;
        d.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
        d.SampleDesc.Count = 1;
        d.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
        d.BufferCount = 2;
        d.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
        d.Scaling = DXGI_SCALING_STRETCH;
        hr = factory->CreateSwapChainForCoreWindow(device.get(), static_cast<::IUnknown*>(get_abi(window)), &d, nullptr, swap.put());
        if (FAILED(hr)) { lamp_log("Lamp: the swap chain couldn't be made (0x%08x).", (unsigned)hr); return; }
        com_ptr<ID3D11Texture2D> back;
        swap->GetBuffer(0, IID_PPV_ARGS(back.put()));
        if (FAILED(device->CreateRenderTargetView(back.get(), nullptr, rtv.put()))) return;
        D3D11_TEXTURE2D_DESC dd{};
        dd.Width = W; dd.Height = H; dd.MipLevels = 1; dd.ArraySize = 1;
        dd.Format = DXGI_FORMAT_D24_UNORM_S8_UINT; dd.SampleDesc.Count = 1;
        dd.Usage = D3D11_USAGE_DEFAULT; dd.BindFlags = D3D11_BIND_DEPTH_STENCIL;
        com_ptr<ID3D11Texture2D> depth;
        if (FAILED(device->CreateTexture2D(&dd, nullptr, depth.put()))) return;
        if (FAILED(device->CreateDepthStencilView(depth.get(), nullptr, dsv.put()))) return;

        sg_desc sd = {};
        sd.environment.defaults.color_format = SG_PIXELFORMAT_BGRA8;
        sd.environment.defaults.depth_format = SG_PIXELFORMAT_DEPTH_STENCIL;
        sd.environment.defaults.sample_count = 1;
        sd.environment.d3d11.device = device.get();
        sd.environment.d3d11.device_context = context.get();
        sd.logger.func = lamp_host_sokol_log;
        sg_setup(&sd);
        LARGE_INTEGER now;
        QueryPerformanceCounter(&now);
        lamp_host_seed((uint64_t)now.QuadPart);
        LampSetup setup = { W, H, SG_PIXELFORMAT_BGRA8, SG_PIXELFORMAT_DEPTH_STENCIL, 1 };
        game_init(&setup);
        lamp_log("Lamp: game_init done.");
        ready = true;
    }

    void read_pads(LampPad pads[4]) {
        auto list = Gamepad::Gamepads();
        for (uint32_t i = 0; i < 4; i++) {
            LampPad& p = pads[i];
            p = {};
            g_rumble[i] = nullptr;
            if (i < list.Size()) {
                Gamepad pad = list.GetAt(i);
                g_rumble[i] = pad;
                GamepadReading r = pad.GetCurrentReading();
                p.connected = true;
                p.lx = lamp_host_dead_zone((float)r.LeftThumbstickX); p.ly = lamp_host_dead_zone((float)r.LeftThumbstickY);
                p.rx = lamp_host_dead_zone((float)r.RightThumbstickX); p.ry = lamp_host_dead_zone((float)r.RightThumbstickY);
                p.lt = (float)r.LeftTrigger; p.rt = (float)r.RightTrigger;
                auto has = [&](GamepadButtons b) { return (r.Buttons & b) == b; };
                const struct { GamepadButtons from; uint32_t to; } map[] = {
                    { GamepadButtons::A, LAMP_A }, { GamepadButtons::B, LAMP_B }, { GamepadButtons::X, LAMP_X }, { GamepadButtons::Y, LAMP_Y },
                    { GamepadButtons::LeftShoulder, LAMP_LB }, { GamepadButtons::RightShoulder, LAMP_RB },
                    { GamepadButtons::Menu, LAMP_MENU }, { GamepadButtons::View, LAMP_VIEW },
                    { GamepadButtons::DPadUp, LAMP_UP }, { GamepadButtons::DPadDown, LAMP_DOWN },
                    { GamepadButtons::DPadLeft, LAMP_LEFT }, { GamepadButtons::DPadRight, LAMP_RIGHT },
                    { GamepadButtons::LeftThumbstick, LAMP_LSTICK }, { GamepadButtons::RightThumbstick, LAMP_RSTICK } };
                for (auto& m : map) if (has(m.from)) p.down |= m.to;
            }
            lamp_host_edges(&p, before[i]);
            before[i] = p.down;
        }
    }

    void Run() {
        CoreWindow window = CoreWindow::GetForCurrentThread();
        window.Activate();
        if (!ready) {
            // Nothing to draw with: the log says why, and the app stays open rather than vanish.
            window.Dispatcher().ProcessEvents(CoreProcessEventsOption::ProcessUntilQuit);
            return;
        }
        LARGE_INTEGER freq, start, last, now;
        QueryPerformanceFrequency(&freq);
        QueryPerformanceCounter(&start);
        last = start;
        LampFrame frame = {};
        frame.width = W; frame.height = H;
        int pads_seen = -1;
        double window_time = 0, slowest = 0;
        int window_frames = 0, late = 0;
        for (;;) {
            window.Dispatcher().ProcessEvents(CoreProcessEventsOption::ProcessAllIfPresent);
            QueryPerformanceCounter(&now);
            double dt = double(now.QuadPart - last.QuadPart) / double(freq.QuadPart);
            last = now;
            frame.dt = dt > 0.1 ? 0.1 : dt;
            frame.time = double(now.QuadPart - start.QuadPart) / double(freq.QuadPart);
            read_pads(frame.pads);
            int connected = 0;
            for (auto& p : frame.pads) connected += p.connected;
            if (connected != pads_seen) { lamp_log("Lamp: %d controller%s connected.", connected, connected == 1 ? "" : "s"); pads_seen = connected; }
            frame.swapchain = {};
            frame.swapchain.width = W; frame.swapchain.height = H; frame.swapchain.sample_count = 1;
            frame.swapchain.color_format = SG_PIXELFORMAT_BGRA8; frame.swapchain.depth_format = SG_PIXELFORMAT_DEPTH_STENCIL;
            frame.swapchain.d3d11.render_view = rtv.get();
            frame.swapchain.d3d11.depth_stencil_view = dsv.get();
            game_frame(&frame);
            frame.number++;
            HRESULT hr = swap->Present(1, 0);
            if (FAILED(hr)) {
                HRESULT why = device->GetDeviceRemovedReason();
                lamp_log("Lamp: the frame couldn't be shown (0x%08x, device 0x%08x); the game stops.", (unsigned)hr, (unsigned)why);
                break;
            }
            // Every ten seconds of play, how well it kept to 60 frames a second: what the agent reads to know.
            if (frame.number > 1) {
                window_time += dt; window_frames++;
                if (dt > slowest) slowest = dt;
                if (dt > 1.0 / 50.0) late++;
                if (window_frames == 600) {
                    lamp_log("Lamp: frames %.1f ms on average, slowest %.1f ms, %d of 600 late.", window_time * 1000 / window_frames, slowest * 1000, late);
                    window_time = 0; window_frames = 0; slowest = 0; late = 0;
                }
            }
        }
    }
};

int __stdcall wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    init_apartment();
    CoreApplication::Run(make<View>());
    return 0;
}
