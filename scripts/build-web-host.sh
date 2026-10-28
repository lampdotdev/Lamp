#!/bin/zsh
# Builds Lamp's web host for the Xbox (Resources/WebHost/App.exe, from lamp_web_host.cpp) and copies Microsoft's
# WebView2 library beside it. Lamp ships what this makes, so only whoever changes the host runs it; a web app is never
# built with it on the person's Mac.
#
# It needs the Xbox game tools Lamp downloads (clang-cl, lld-link and Microsoft's SDK, in the shared developer folder:
# build an Xbox game in Lamp Dev once, or point LAMP_WINDOWS at them), and fetches the rest into a temporary folder,
# each checked against the checksum its publisher gives (NuGet's SHA-512) or pinned to a commit:
#   - Microsoft.Web.WebView2: WebView2's WinRT metadata and the library the package carries.
#   - Microsoft.Windows.SDK.Contracts: Windows' metadata, which C++/WinRT reads to write WebView2's headers.
#   - C++/WinRT and the winmd reader: built here, for this Mac, to write those headers.
set -euo pipefail
cd "${0:A:h}/.."
tools="${LAMP_WINDOWS:-$HOME/Library/Developer/Lamp/Windows}"
sdk="$tools/sdk"
[[ -x "$tools/llvm/bin/clang-cl" && -d "$sdk/sdk/include/cppwinrt" ]] || { print -u2 "The Xbox game tools aren't in $tools: set up an Xbox game in Lamp Dev first."; exit 1; }

webview2=1.0.3719.77
webview2_sha512="Cpq7EGgijiCN0lg1RlTZuZcRkzyo/USU9cEJMSPh6FG4PLjmTEpJ5NKuJqQ06ONnVVARCcTLf31IjjhFJUrApw=="
contracts=10.0.26100.9169
contracts_sha512="Ogsqphg1TBx0cAsQr9+AS5yMUCDSyVRo5XEXlICcOmkVIkxs7CtjUQhYklbrHtgOtN5ZqTOUx3pkC5PfWeHUEw=="
# C++/WinRT's version must be the one the SDK's own headers are (their base.h says it).
cppwinrt_tag=2.0.250303.1
cppwinrt_commit=69c78cfc7920367c4ce9cc024cf8c5b8d217fb1b
winmd_commit=0f1eae3bfa63fa2ba3c2912cbfe72a01db94cc5a
grep -q "CPPWINRT_VERSION \"$cppwinrt_tag\"" "$sdk/sdk/include/cppwinrt/winrt/base.h" || { print -u2 "The SDK's C++/WinRT isn't $cppwinrt_tag."; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

nuget() { # id version sha512 folder
  local file="$work/$1.nupkg"
  curl -fsSL -o "$file" "https://api.nuget.org/v3-flatcontainer/${1:l}/$2/${1:l}.$2.nupkg"
  [[ "$(openssl dgst -sha512 -binary "$file" | base64)" == "$3" ]] || { print -u2 "$1 $2 isn't the package NuGet published."; exit 1; }
  mkdir -p "$4" && unzip -q "$file" -d "$4"
}
nuget Microsoft.Web.WebView2 $webview2 $webview2_sha512 "$work/webview2"
nuget Microsoft.Windows.SDK.Contracts $contracts $contracts_sha512 "$work/contracts"

git init -q "$work/cppwinrt" && git -C "$work/cppwinrt" fetch -q --depth 1 https://github.com/microsoft/cppwinrt.git $cppwinrt_commit && git -C "$work/cppwinrt" checkout -q FETCH_HEAD
git init -q "$work/winmd" && git -C "$work/winmd" fetch -q --depth 1 https://github.com/microsoft/winmd.git $winmd_commit && git -C "$work/winmd" checkout -q FETCH_HEAD
mkdir -p "$work/bin" "$work/gen"
clang++ -std=c++17 -O1 -I"$work/cppwinrt/cppwinrt" -o "$work/bin/prebuild" "$work/cppwinrt/prebuild/main.cpp" -DCPPWINRT_VERSION_STRING="\"$cppwinrt_tag\""
"$work/bin/prebuild" "$work/cppwinrt/strings" "$work/bin"
clang++ -std=c++17 -O2 -I"$work/bin" -I"$work/cppwinrt/cppwinrt" -I"$work/winmd/src" -o "$work/bin/cppwinrt" \
  "$work/cppwinrt/cppwinrt/main.cpp" "$work/bin/strings.cpp" -DCPPWINRT_VERSION_STRING="\"$cppwinrt_tag\""
"$work/bin/cppwinrt" -in "$work/webview2/lib/Microsoft.Web.WebView2.Core.winmd" -ref "$work/contracts/ref/netstandard2.0" -out "$work/gen" > /dev/null

"$tools/llvm/bin/clang-cl" --target=x86_64-pc-windows-msvc /std:c++20 /EHsc /O2 /MT /DWINAPI_FAMILY=WINAPI_FAMILY_APP \
  /D_CRT_USE_WINAPI_FAMILY_DESKTOP_APP /D_CRT_SECURE_NO_WARNINGS /DUNICODE /D_UNICODE /DNOMINMAX -imsvc "$sdk/crt/include" -imsvc "$sdk/sdk/include/ucrt" \
  -imsvc "$sdk/sdk/include/um" -imsvc "$sdk/sdk/include/shared" -imsvc "$sdk/sdk/include/winrt" -imsvc "$sdk/sdk/include/cppwinrt" \
  -imsvc "$work/gen" /c Resources/WebHost/lamp_web_host.cpp /Fo"$work/host.obj"
# A static C++ runtime, so the console needs no package of Microsoft's beside the app.
"$tools/llvm/bin/lld-link" /OUT:Resources/WebHost/App.exe /APPCONTAINER /SUBSYSTEM:WINDOWS /MACHINE:X64 /ENTRY:wWinMainCRTStartup \
  /NODEFAULTLIB /LIBPATH:"$sdk/crt/lib/onecore/x86_64" /LIBPATH:"$sdk/sdk/lib/ucrt/x86_64" /LIBPATH:"$sdk/sdk/lib/um/x86_64" \
  "$work/host.obj" libcmt.lib libvcruntime.lib libcpmt.lib ucrt.lib WindowsApp.lib
cp "$work/webview2/runtimes/win-x64/native_uap/Microsoft.Web.WebView2.Core.dll" Resources/WebHost/
cp "$work/webview2/LICENSE.txt" Resources/WebHost/WebView2-LICENSE.txt
print "Built Resources/WebHost/App.exe with WebView2 $webview2."
