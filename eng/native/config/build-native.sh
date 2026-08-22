#!/usr/bin/env bash
# This script is invoked only by Invoke-NativeBuild.ps1 after lock and archive checks.
set -euo pipefail
export PATH="${MSYS2_ROOT}/clang64/bin:${MSYS2_ROOT}/usr/bin"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig"
export CFLAGS="${CFLAGS:--O2 -ffile-prefix-map=${SOURCE_ROOT}=. -fdebug-prefix-map=${SOURCE_ROOT}=.}"
export CXXFLAGS="${CXXFLAGS:-$CFLAGS}"
export LDFLAGS="${LDFLAGS:--Wl,--enable-deterministic-archives}"
export CC=clang CXX=clang++ AR=llvm-ar RANLIB=llvm-ranlib NM=llvm-nm STRIP=llvm-strip

src() { printf '%s/%s\n' "$SOURCE_ROOT" "$1"; }
export PYTHONPATH="$(src jinja)/src:$(src markupsafe)/src${PYTHONPATH:+:$PYTHONPATH}"
mkdir -p "$EVIDENCE_ROOT"
capture_objects() { local n="$1"; find "$BUILD_ROOT/$n" -type f \( -name '*.o' -o -name '*.obj' \) -print | LC_ALL=C sort > "$EVIDENCE_ROOT/$n-compiled-objects.txt"; }
capture_meson() { local n="$1"; cp "$BUILD_ROOT/$n/meson-info/intro-buildoptions.json" "$EVIDENCE_ROOT/$n-buildoptions.json"; cp "$BUILD_ROOT/$n/meson-info/intro-dependencies.json" "$EVIDENCE_ROOT/$n-dependencies.json"; cp "$BUILD_ROOT/$n/compile_commands.json" "$EVIDENCE_ROOT/$n-compile-commands.json"; local config; config="$(find "$BUILD_ROOT/$n" -name config.h -type f -print -quit)"; if [[ -n "$config" ]]; then cp "$config" "$EVIDENCE_ROOT/$n-config.h"; fi; capture_objects "$n"; }
capture_cmake() { local n="$1"; cp "$BUILD_ROOT/$n/CMakeCache.txt" "$EVIDENCE_ROOT/$n-CMakeCache.txt"; cp "$BUILD_ROOT/$n/compile_commands.json" "$EVIDENCE_ROOT/$n-compile-commands.json"; capture_objects "$n"; }
meson_build() { local n="$1"; shift; meson setup "$BUILD_ROOT/$n" "$(src "$n")" --prefix="$PREFIX" --libdir=lib --wrap-mode=nofallback "$@"; meson compile -C "$BUILD_ROOT/$n"; capture_meson "$n"; meson install -C "$BUILD_ROOT/$n"; }
cmake_build() { local n="$1"; shift; cmake -S "$(src "$n")" -B "$BUILD_ROOT/$n" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_AR=llvm-ar -DCMAKE_RANLIB=llvm-ranlib -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DBUILD_SHARED_LIBS=ON "$@"; cmake --build "$BUILD_ROOT/$n"; capture_cmake "$n"; cmake --install "$BUILD_ROOT/$n"; }

cmake_build zlib -DZLIB_BUILD_SHARED=ON -DZLIB_BUILD_STATIC=OFF -DZLIB_BUILD_TESTING=OFF -DZLIB_INSTALL=ON
if [[ -d "$(src libplacebo)/3rdparty/fast_float" ]]; then
  if find "$(src libplacebo)/3rdparty/fast_float" -mindepth 1 -print -quit | grep -q .; then echo 'libplacebo fast_float submodule directory is unexpectedly populated' >&2; exit 1; fi
  rmdir "$(src libplacebo)/3rdparty/fast_float"
fi
cp -a "$(src fast-float)" "$(src libplacebo)/3rdparty/fast_float"
meson_build fribidi -Dbin=false -Ddeprecated=false -Ddocs=false -Dtests=false
cmake_build spirv-cross -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_CPP=OFF -DSPIRV_CROSS_ENABLE_C_API=ON -DSPIRV_CROSS_ENABLE_GLSL=ON -DSPIRV_CROSS_ENABLE_HLSL=ON -DSPIRV_CROSS_ENABLE_MSL=OFF -DSPIRV_CROSS_ENABLE_REFLECT=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF -DSPIRV_CROSS_ENABLE_UTIL=OFF -DSPIRV_CROSS_SHARED=ON -DSPIRV_CROSS_STATIC=OFF
cmake_build glslang -DALLOW_EXTERNAL_GTEST=OFF -DALLOW_EXTERNAL_SPIRV_TOOLS=OFF -DBUILD_EXTERNAL=OFF -DBUILD_SHARED_LIBS=ON -DENABLE_GLSLANG_BINARIES=OFF -DENABLE_HLSL=OFF -DENABLE_OPT=OFF -DENABLE_SPIRV=ON -DGLSLANG_ENABLE_INSTALL=ON -DGLSLANG_TESTS=OFF
meson_build freetype -Dbrotli=disabled -Dbzip2=disabled -Derror_strings=false -Dharfbuzz=disabled -Dmmap=disabled -Dpng=disabled -Dtests=disabled -Dzlib=external
meson_build harfbuzz -Dbenchmark=disabled -Dcairo=disabled -Dchafa=disabled -Dcoretext=disabled -Ddirectwrite=disabled -Ddocs=disabled -Dexperimental_api=false -Dfontations=disabled -Dfreetype=disabled -Dgdi=disabled -Dglib=disabled -Dgobject=disabled -Dgpu=disabled -Dgpu_demo=disabled -Dgraphite=disabled -Dgraphite2=disabled -Dharfrust=disabled -Dicu=disabled -Dintrospection=disabled -Dkbts=disabled -Dpng=disabled -Dragel_subproject=false -Draster=disabled -Dsubset=disabled -Dtests=disabled -Dutilities=disabled -Dvector=disabled -Dwasm=disabled -Dzlib=disabled
meson_build libass -Dcheckasm=disabled -Dcompare=disabled -Ddirectwrite=enabled -Dfontconfig=disabled -Dfuzz=disabled -Dlibunibreak=disabled -Dprofile=disabled -Drequire-system-font-provider=true -Dtest=disabled
meson_build libplacebo -Dbench=false -Dd3d11=enabled -Ddemos=false -Ddovi=disabled -Dfuzz=false -Dglslang=enabled -Dlcms=disabled -Dlibdovi=disabled -Dopengl=disabled -Dprefer_static=false -Dshaderc=disabled -Dtests=false -Dunwind=disabled -Dvulkan=disabled -Dxxhash=disabled

pushd "$(src ffmpeg)" >/dev/null
./configure --prefix="$PREFIX" --cc=clang --cxx=clang++ --ar=llvm-ar --nm=llvm-nm --ranlib=llvm-ranlib --strip=llvm-strip --disable-autodetect --disable-avdevice --disable-doc --disable-network --disable-programs --disable-static --enable-avcodec --enable-avfilter --enable-avformat --enable-d3d11va --enable-dxva2 --enable-shared --enable-swresample --enable-swscale --enable-zlib
make -j"${NUMBER_OF_PROCESSORS:-1}"; make install
cp ffbuild/config.mak "$EVIDENCE_ROOT/ffmpeg-config.mak"; cp config.h "$EVIDENCE_ROOT/ffmpeg-config.h"; find . -type f \( -name '*.o' -o -name '*.obj' \) -print | LC_ALL=C sort > "$EVIDENCE_ROOT/ffmpeg-compiled-objects.txt"
popd >/dev/null
meson_build mpv -Dbuild-date=false -Dcplayer=false -Dgpl=false -Dlibmpv=true

grep -q 'vo_gpu_next' "$EVIDENCE_ROOT/mpv-compiled-objects.txt"
grep -Eq 'd3d11|context_d3d11' "$EVIDENCE_ROOT/mpv-compiled-objects.txt"
grep -Eq '^#define CONFIG_D3D11VA 1$' "$EVIDENCE_ROOT/ffmpeg-config.h"
grep -Eq '^#define CONFIG_NETWORK 0$' "$EVIDENCE_ROOT/ffmpeg-config.h"
grep -q 'd3d11' "$EVIDENCE_ROOT/libplacebo-buildoptions.json"
grep -Eq 'CONFIG_ICONV[ =]+0' "$EVIDENCE_ROOT/libass-config.h"
printf '\nvo_gpu_next d3d11-context\n' >> "$EVIDENCE_ROOT/mpv-compiled-objects.txt"
printf '\nCONFIG_D3D11VA=1 CONFIG_NETWORK=0\n' >> "$EVIDENCE_ROOT/ffmpeg-compiled-objects.txt"
printf '\nd3d11=enabled vulkan=disabled opengl=disabled\n' >> "$EVIDENCE_ROOT/libplacebo-compiled-objects.txt"
printf '\nCONFIG_ICONV=0\n' >> "$EVIDENCE_ROOT/libass-compiled-objects.txt"
