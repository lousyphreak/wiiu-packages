#!/usr/bin/env bash
set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
source_sdk=${DEVKITPRO:-/opt/devkitpro}
jobs=${JOBS:-24}
stage="$root/.build/sdk"
mkdir -p "$root/.build/gcc" "$root/.build/wut-tools"

cd "$root/.build/gcc"
if [ ! -f Makefile ]; then
    CC=${HOST_CC:-gcc-15} CXX=${HOST_CXX:-g++-15} ../../gcc/configure \
        --target=powerpc-eabi --build=x86_64-pc-linux-gnu --host=x86_64-pc-linux-gnu \
        --prefix=/opt/devkitpro/devkitPPC --enable-languages=c,c++,objc,lto \
        --enable-lto --with-cpu=750 --disable-nls --disable-shared \
        --enable-threads=posix --disable-multilib --disable-win32-registry \
        --disable-libstdcxx-pch --disable-libstdcxx-verbose \
        --enable-libstdcxx-time=yes --enable-libstdcxx-filesystem-ts \
        --disable-tm-clone-registry --disable-__cxa_atexit --disable-libssp \
        --enable-cxx-flags='-ffunction-sections -fdata-sections' \
        --with-newlib --with-native-system-header-dir=/include \
        --with-sysroot="$source_sdk/devkitPPC/powerpc-eabi" --with-system-zlib \
        --with-pkgversion='devkitPPC Wii U TLS' \
        --with-bugurl=https://github.com/lousyphreak/wut/issues > configure.log 2>&1
fi
make -j"$jobs" all-gcc > build.log 2>&1
make -j"$jobs" all-target-libgcc all-target-libstdc++-v3 > runtime-build.log 2>&1
make -j"$jobs" install-gcc install-target-libgcc install-target-libstdc++-v3 \
    DESTDIR="$stage" > install.log 2>&1
cp -a --update=none "$source_sdk/devkitPPC/powerpc-eabi/." \
    "$stage/opt/devkitpro/devkitPPC/powerpc-eabi/"

cd "$root"
DEVKITPRO="$source_sdk" DEVKITPPC="$source_sdk/devkitPPC" \
    make -C wut -j"$jobs" > .build/wut-build.log 2>&1
DEVKITPRO="$source_sdk" DEVKITPPC="$source_sdk/devkitPPC" \
    make -C wut -j"$jobs" install DESTDIR="$stage" > .build/wut-install.log 2>&1

cd "$root/wut-tools"
git submodule update --init --recursive
./autogen.sh > "$root/.build/wut-tools/autogen.log" 2>&1
cd "$root/.build/wut-tools"
../../wut-tools/configure --prefix=/opt/devkitpro/tools \
    CXXFLAGS='-O2 -g -std=gnu++14' > configure.log 2>&1
make -j"$jobs" > build.log 2>&1
make -j"$jobs" install DESTDIR="$stage" > install.log 2>&1
