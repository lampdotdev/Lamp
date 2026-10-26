# The game kit's libraries

Lamp writes these into every Xbox game it makes, and the game is built with them. Each is used as published, at the
commit named, under its own licence.

- sokol_gfx.h, sokol_log.h, sokol_gl.h, sokol_debugtext.h, sokol_shape.h: https://github.com/floooh/sokol at
  efeb77603e24daea7d1dd6445b9358bb5d82533b, zlib licence (below).
- HandmadeMath.h: https://github.com/HandmadeMath/HandmadeMath at 661fef0893bccfe30342049e848b8d54e7430234, public
  domain (CC0 1.0).
- cgltf.h: https://github.com/jkuhlmann/cgltf at 85cd62382dfea638278962690cf515023f33ed00, MIT licence, Copyright (c)
  2018-2021 Johannes Kuhlmann.
- stb_image.h and stb_vorbis.c: https://github.com/nothings/stb at 003501f6d7a8668ce8b6d875e34dd97ad0d5d5b5, MIT
  licence or public domain, Copyright (c) 2017 Sean Barrett (the licence is at the end of each file).
- dr_wav.h, dr_mp3.h: https://github.com/mackron/dr_libs at dfe8377631000664666519fdb83da193fd8037f4, public domain
  (Unlicense) or MIT No Attribution, Copyright 2023 David Reid (the licence is at the end of each file).
- The hammer on a new web game's card (scaffold-web/Web/game.js): Lucide's "hammer" icon, https://lucide.dev, ISC
  licence (below).

## sokol

zlib/libpng license

Copyright (c) 2018 Andre Weissflog

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
    claim that you wrote the original software. If you use this software in a
    product, an acknowledgment in the product documentation would be
    appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
    be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source
    distribution.

## MIT licence (cgltf)

Copyright (c) 2018-2021 Johannes Kuhlmann

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

## Lucide

ISC License

Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2022 as part of Feather (MIT). All other copyright
(c) for Lucide are held by Lucide Contributors 2022.

Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby
granted, provided that the above copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
