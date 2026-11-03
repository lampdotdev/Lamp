#!/bin/sh
# Lamp's game kit: builds the game. Lamp writes this file before every build and runs it in the app's sandbox; don't
# edit it.
#
#   sh Lamp/build.sh xbox      the console's app: build/xbox/App.exe, and build/xbox.zip with it and Assets/
#
# The game is every .cpp and .c in Game/, and every .glsl there is a shader, compiled by sokol-shdc into
# build/shaders/<name>.glsl.h for the game to include. $LAMP_WINDOWS is
# where Lamp keeps the tools for the console: LLVM's clang-cl and lld-link, Microsoft's SDK and sokol-shdc.
set -e
cd "$(dirname "$0")/.."
target="${1:-xbox}"
tools="${LAMP_WINDOWS:?Lamp gives the build the folder with the tools for the console}"
mkdir -p build/shaders

# Shaders first: the build includes what they make.
for shader in Game/*.glsl; do
  [ -e "$shader" ] || continue
  name=$(basename "$shader")
  out="build/shaders/$name.h"
  if [ ! -f "$out" ] || [ "$shader" -nt "$out" ] || [ "$tools/bin/sokol-shdc" -nt "$out" ]; then
    "$tools/bin/sokol-shdc" --input "$shader" --output "$out" --slang hlsl5:metal_macos >&2 || { rm -f "$out"; exit 1; }
  fi
done

# Lamp's own code, compiled again only when it changed (Lamp touches kit.stamp when any of its files does): it's
# the slow part. The game's, every time.
fresh() { [ -f "$1" ] && [ "$1" -nt "$2" ] && [ "$1" -nt Lamp/kit.stamp ]; }

sdk="$tools/sdk"
out=build/xbox
mkdir -p "$out"
cl="$tools/llvm/bin/clang-cl"
# The flags as the shell's own argument list, so a folder name with a space in it (the home folder's) stays one argument.
set -- --target=x86_64-pc-windows-msvc /std:c++20 /EHsc /O2 /MT /DWINAPI_FAMILY=WINAPI_FAMILY_APP /D_CRT_USE_WINAPI_FAMILY_DESKTOP_APP \
  /DUNICODE /D_UNICODE /DNOMINMAX /DLAMP_XBOX=1 -imsvc "$sdk/crt/include" -imsvc "$sdk/sdk/include/ucrt" -imsvc "$sdk/sdk/include/um" \
  -imsvc "$sdk/sdk/include/shared" -imsvc "$sdk/sdk/include/winrt" -imsvc "$sdk/sdk/include/cppwinrt" -ILamp -Ibuild/shaders -IGame
fresh "$out/lamp_kit.obj" Lamp/lamp_kit.cpp || "$cl" "$@" /DSOKOL_D3D11 -w /c Lamp/lamp_kit.cpp /Fo"$out/lamp_kit.obj"
fresh "$out/lamp_xbox.obj" Lamp/lamp_xbox.cpp || "$cl" "$@" -w /c Lamp/lamp_xbox.cpp /Fo"$out/lamp_xbox.obj"
fresh "$out/lamp_sound.obj" Lamp/lamp_sound.cpp || "$cl" "$@" -w /c Lamp/lamp_sound.cpp /Fo"$out/lamp_sound.obj"
objects="$out/lamp_kit.obj $out/lamp_xbox.obj $out/lamp_sound.obj"
for source in Game/*.cpp Game/*.c; do
  [ -e "$source" ] || continue
  object="$out/$(basename "$source").obj"
  case "$source" in *.c) "$cl" "$@" /TC /c "$source" /Fo"$object" ;;
                    *) "$cl" "$@" /c "$source" /Fo"$object" ;; esac
  objects="$objects $object"
done
# A static C++ runtime, so the console needs no package of Microsoft's beside the game's.
"$tools/llvm/bin/lld-link" /OUT:"$out/App.exe" /APPCONTAINER /SUBSYSTEM:WINDOWS /MACHINE:X64 /ENTRY:wWinMainCRTStartup /NODEFAULTLIB \
  /LIBPATH:"$sdk/crt/lib/onecore/x86_64" /LIBPATH:"$sdk/sdk/lib/ucrt/x86_64" /LIBPATH:"$sdk/sdk/lib/um/x86_64" \
  $objects libcmt.lib libvcruntime.lib libcpmt.lib ucrt.lib WindowsApp.lib d3d11.lib dxgi.lib xaudio2.lib
rm -f build/xbox.zip
( cd "$out" && zip -qX ../xbox.zip App.exe )
if [ -d Assets ]; then zip -qrXy build/xbox.zip Assets -x '*/.*' -x '.*'; fi
