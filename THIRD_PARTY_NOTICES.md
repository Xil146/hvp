# Third-party notices

HVP source is MIT licensed. Lean V1 pins the Windows x64 `mpv-dev-lgpl` bundle
from [`zhongfly/mpv-winbuild` release
`2026-08-22-49418246f3`](https://github.com/zhongfly/mpv-winbuild/releases/tag/2026-08-22-49418246f3):

- archive: `mpv-dev-lgpl-x86_64-20260822-git-49418246f3.7z`
- archive SHA-256: `4b9295dc281bf63129260237006c36c38aad9031569205bb2bdf6dd0ccfc79aa`
- shipped DLL: `libmpv-2.dll`
- DLL SHA-256: `7b3128c51da4f23e021e7ccdc3ae455dcf8d5c287b74702a6356ff19f750e288`
- build/source material: [publisher build run](https://github.com/zhongfly/mpv-winbuild/actions/runs/32571847564)
- build repository commit: `16ca55d5f3e8a847a53f52e2d59bf60976264d43`
- declared LGPL build mode: [publisher build patch](https://github.com/zhongfly/mpv-winbuild/blob/16ca55d5f3e8a847a53f52e2d59bf60976264d43/compile-lgpl-libmpv.patch)

The publisher states that this variant uses LGPLv2.1+ libmpv and statically
links LGPLv3 FFmpeg. The corresponding verbatim GNU texts are staged as
[`licenses/LGPL-2.1.txt`](licenses/LGPL-2.1.txt) and
[`licenses/LGPL-3.0.txt`](licenses/LGPL-3.0.txt), and are copied beside the
published app. The downloaded development archive itself contains no license
or notice files. These two texts are not an asserted complete dependency
closure inventory.

This V1 record is intentionally small: it does not require a custom native
build, an SBOM, or a candidate-promotion/provenance system. It does not replace
legal advice or the obligations in the selected bundle's licenses. The
publisher also disclaims an independent legal guarantee for its build mode.

This record is not yet a complete static-link closure inventory. Before a
distributed native-bearing folder or issue #6 closure, record and stage every
applicable dependency notice/license and corresponding-source or relinking
material for the exact linked bundle.
