#!/bin/sh
# Lamp's game kit: builds the game. Lamp writes this file before every build and runs it in the app's sandbox; don't
# edit it.
#
#   sh Lamp/build.sh xbox      the console's app: build/xbox/App.exe, and build/xbox.zip with it and Assets/
#   sh Lamp/build.sh preview   the Mac preview: build/preview/lamp_preview
#
# The game is every .cpp and .c in Game/, and every .glsl there is a shader, compiled by sokol-shdc into
# build/shaders/<name>.glsl.h (HLSL for the console, Metal for the Mac) for the game to include. $LAMP_WINDOWS is
# where Lamp keeps the tools for the console: LLVM's clang-cl and lld-link, Microsoft's SDK and sokol-shdc.
set -e
cd "$(dirname "$0")/.."
target="${1:-xbox}"
tools="${LAMP_WINDOWS:?Lamp gives the build the folder with the tools for the console}"
mkdir -p build/shaders

# Shaders first: both builds include what they make.
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

if [ "$target" = preview ]; then
  out=build/preview
  mkdir -p "$out"
  flags="-std=c++20 -O1 -g0 -DLAMP_PREVIEW=1 -DSOKOL_METAL -ILamp -Ibuild/shaders -IGame"
  fresh "$out/lamp_kit.o" Lamp/lamp_kit.cpp ||
    clang++ $flags -DSOKOL_TRACE_HOOKS -x objective-c++ -fobjc-arc -w -c Lamp/lamp_kit.cpp -o "$out/lamp_kit.o"
  fresh "$out/lamp_preview.o" Lamp/lamp_preview.mm ||
    clang++ $flags -x objective-c++ -fobjc-arc -w -c Lamp/lamp_preview.mm -o "$out/lamp_preview.o"
  objects="$out/lamp_kit.o $out/lamp_preview.o"
  for source in Game/*.cpp Game/*.c; do
    [ -e "$source" ] || continue
    object="$out/$(basename "$source").o"
    case "$source" in *.c) clang -std=c17 -O1 -g0 -DLAMP_PREVIEW=1 -ILamp -Ibuild/shaders -IGame -c "$source" -o "$object" ;;
                      *) clang++ $flags -c "$source" -o "$object" ;; esac
    objects="$objects $object"
  done
  clang++ $objects -o "$out/lamp_preview" -framework Foundation -framework Metal -framework QuartzCore -framework ImageIO \
    -framework CoreGraphics -framework UniformTypeIdentifiers
  exit 0
fi

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
objects="$out/lamp_kit.obj $out/lamp_xbox.obj"
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
  $objects libcmt.lib libvcruntime.lib libcpmt.lib ucrt.lib WindowsApp.lib d3d11.lib dxgi.lib
rm -f build/xbox.zip
( cd "$out" && zip -qX ../xbox.zip App.exe )
if [ -d Assets ]; then zip -qrXy build/xbox.zip Assets -x '*/.*' -x '.*'; fi
