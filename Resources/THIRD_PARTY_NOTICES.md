# Third-party notices

Lamp bundles the following software.

## pi coding agent

https://github.com/badlogic/pi-mono (`@earendil-works/pi-coding-agent`)

MIT License

Copyright (c) Mario Zechner

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## llama.cpp

https://github.com/ggml-org/llama.cpp (llama-server and its libraries)

MIT License

Copyright (c) 2023-2026 The ggml authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Lobe Icons

https://github.com/lobehub/lobe-icons (`@lobehub/icons-static-png`, the provider logos in Settings)

MIT License

Copyright (c) 2023 LobeHub

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## xwin

https://github.com/Jake-Shadle/xwin

Bundled to download Microsoft's Windows SDK and C runtime on the Mac it runs on, after the person accepts Microsoft's
licence there. Licensed under MIT or Apache 2.0; used under MIT.

Copyright (c) 2021 Jake Shadle

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Lamp's game kit for Xbox games

Lamp writes these libraries into the Xbox games it makes (Resources/GameKit/NOTICE.md has each one's source and
licence in full): sokol (https://github.com/floooh/sokol, zlib licence, Copyright (c) 2018 Andre Weissflog),
HandmadeMath (https://github.com/HandmadeMath/HandmadeMath, public domain), cgltf (https://github.com/jkuhlmann/cgltf,
MIT, Copyright (c) 2018-2021 Johannes Kuhlmann), stb_image and stb_vorbis (https://github.com/nothings/stb, MIT or
public domain, Copyright (c) 2017 Sean Barrett), and dr_wav and dr_mp3 (https://github.com/mackron/dr_libs, public domain
or MIT No Attribution, Copyright 2023 David Reid).

## Libraries for games' pages

Lamp writes these into the pages of the games it makes, each with its license beside it
(Resources/WebLibraries/<name>/NOTICE.md says which release and how it was checked): three.js
(https://github.com/mrdoob/three.js, MIT, Copyright © 2010-2026 three.js authors), for 3D, and Phaser
(https://github.com/phaserjs/phaser, MIT, Copyright (c) 2024 Richard Davey, Phaser Studio Inc.), for 2D, only into a
game that draws with it, and Rapier (https://github.com/dimforge/rapier, the npm package
@dimforge/rapier3d-compat, Apache License 2.0, Copyright 2020 Dimforge EURL), for physics, only into a game that
imports it.

three.js's addons also include small libraries from other projects: fflate, lil-gui, meshoptimizer's decoder, potpack,
stats.js and tween.js (MIT, and ISC for potpack), and an EXR loader ported from other code. Lamp copies them as three.js
publishes them, so each keeps the license label or notice in its own file, but their full copyright and permission texts
are not yet beside them in Resources/WebLibraries/three, which carries three.js's license alone.

## The phone service for LG games

Lamp puts ws (https://github.com/websockets/ws, MIT, Copyright (c) 2011 Einar Otto Stangvik, Copyright (c) 2013 Arnout
Kazemier and contributors, Copyright (c) 2016 Luigi Pinca and contributors) in the service it packages with a game for
an LG TV, with its license beside it (Resources/LGPhones/node_modules/ws/LICENSE; scripts/update-lg-ws.sh says which
release and how it was checked).

## QR codes

Lamp puts QR Code Generator for JavaScript 2.0.4 (https://github.com/kazuhikoarase/qrcode-generator, the npm package
qrcode-generator, MIT, Copyright (c) 2009 Kazuhiko Arase) in lamp.js, the script Lamp writes into the games and TV pages it makes (they show a QR
code phones scan to join), with its license at the top of that code and in Resources/WebLibraries/qrcode/LICENSE. "QR Code" is a registered trademark of DENSO WAVE
INCORPORATED.

## The Xbox web host

Lamp bundles a small Windows program that shows an Xbox web app's page (Resources/WebHost/App.exe, built from
lamp_web_host.cpp by scripts/build-web-host.sh) and Microsoft's WebView2 library it uses
(Microsoft.Web.WebView2.Core.dll, the Microsoft.Web.WebView2 package), under Microsoft's license in
Resources/WebHost/WebView2-LICENSE.txt (BSD 3-Clause, Copyright (C) Microsoft Corporation).

## Network hardware makers

Resources/vendors.xz is the IEEE Registration Authority's public lists of the first digits of hardware addresses
(MA-L, MA-M and MA-S, https://standards-oui.ieee.org), with each company's legal ending taken off; scripts/update-vendors.sh
makes it. Lamp reads it to say who made a device on the home network.

## Starter apps

Each starter app is its own repository (github.com/lampdotdev), with a credits file and the license of anything in it
that came from someone else beside the files.

## Logos and trademarks

The provider logos in Settings (Resources/ProviderLogos) come from Lobe Icons, above, under its MIT license. The logos
and the names they stand for are trademarks of their owners. Lamp shows them only to say which provider a setting is
about; they are not part of Lamp's MIT license and Lamp is not endorsed by their owners.
