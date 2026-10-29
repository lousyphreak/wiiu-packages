#!/usr/bin/env bash
set -e

root=$(cd "$(dirname "$0")/../.." && pwd)
source_sdk=${DEVKITPRO:-/opt/devkitpro}
jobs=${JOBS:-24}
stage="$root/.build/sdk"

# Use the current devkitPPC build stages and package patches.
release="$root/.build/buildscripts-current"
mkdir -p "$release"
git -C "$root/buildscripts" archive HEAD | tar -x -C "$release"
BUILD_DKPRO_PACKAGE=2
DKPPC_RULES_VER=1.2.1
DKPPC_CRTLS_VER=1.0.0
. "$release/select_toolchain.sh"
# GCC's nested host configure inherits these flags from make's environment.
export CPPFLAGS="$cppflags ${CPPFLAGS:-}"

BUILDDIR="$root/.build/devkitPPC-$GCC_VER"
BUILDSCRIPTDIR="$release"
MAKE="make -j$jobs"
prefix=/opt/devkitpro/devkitPPC
host=$($release/config.guess)
CROSS_PARAMS="--build=$host --host=$host"
EXTRA_GCC_PARAMS="--with-system-zlib --with-build-sysroot=$stage$prefix/$target --with-build-time-tools=$stage$prefix/$target/bin --with-pkgversion=WiiU-TLS-development --with-bugurl=https://github.com/lousyphreak/wut/issues"
export CC=${HOST_CC:-cc} CXX=${HOST_CXX:-c++}
export DESTDIR="$stage"
export PATH="$stage$prefix/bin:$source_sdk/devkitPPC/bin:$PATH"

sources="$root/.build/sources"
mkdir -p "$sources" "$BUILDDIR" "$stage$prefix/$target"
cp -a --update=none "$source_sdk/devkitPPC/$target/." "$stage$prefix/$target/"
cp "$source_sdk/devkitPPC/base_rules" "$source_sdk/devkitPPC/base_tools" "$stage$prefix/"
for archive in "binutils-$BINUTILS_VER.tar.xz" "gcc-$GCC_VER.tar.xz" "newlib-$NEWLIB_VER.tar.gz"; do
    if [ ! -f "$sources/$archive" ]; then
        curl -fL -A dkp-buildscript "https://downloads.devkitpro.org/$archive" -o "$sources/$archive"
    fi
done
cd "$BUILDDIR"
for component in "binutils-$BINUTILS_VER" "gcc-$GCC_VER" "newlib-$NEWLIB_VER"; do
    if [ ! -d "$component" ]; then
        tar -xf "$sources/$component.tar."* -C "$BUILDDIR"
        case "$component" in
            binutils-*) patch="$BINUTILS_PKGREL" ;;
            gcc-*) patch="$GCC_PKGREL" ;;
            newlib-*) patch="$NEWLIB_PKGREL" ;;
        esac
        patch -p1 -d "$component" < "$release/patches/$component-$patch.patch"
        if [ "$component" = "gcc-$GCC_VER" ]; then
            patch -p1 -d "$component" < "$release/patches/$component-wiiu-tls.patch"
        fi
    fi
done
. "$release/build-binutils.sh" > binutils.log 2>&1

# Let make handle incremental source changes instead of retaining build stamps.
mkdir -p "$BUILDDIR/$target/gcc"
cd "$BUILDDIR/$target/gcc"
rm -f built-gcc installed-gcc built-gcc-stage2 installed-gcc-stage2
. "$release/build-gcc-stage1.sh" > stage1.log 2>&1
. "$release/build-newlib.sh" > "$BUILDDIR/newlib.log" 2>&1
. "$release/build-gcc-stage2.sh" > "$BUILDDIR/$target/gcc/stage2.log" 2>&1

cd "$root"
# Use the new compiler, with the usual logical prefix plus DESTDIR installation.
DEVKITPRO=/opt/devkitpro DEVKITPPC="$stage/opt/devkitpro/devkitPPC" \
    make -C wut -j"$jobs" install \
    CC="$stage/opt/devkitpro/devkitPPC/bin/powerpc-eabi-gcc" \
    CXX="$stage/opt/devkitpro/devkitPPC/bin/powerpc-eabi-g++" \
    > .build/wut-install.log 2>&1

cd "$root/wut-tools"
git submodule update --init --recursive
mkdir -p "$root/.build/wut-tools"
./autogen.sh > "$root/.build/wut-tools/autogen.log" 2>&1
cd "$root/.build/wut-tools"
../../wut-tools/configure --host="$host" --prefix=/opt/devkitpro/tools \
    > configure.log 2>&1
make -j"$jobs" > build.log 2>&1
make -j"$jobs" install-strip > install.log 2>&1

# Stage the existing devkitPro CMake/environment integration with Wii U TLS flags.
mkdir -p "$stage/opt/devkitpro/cmake"
cp -a --update=none "$source_sdk/cmake/." "$stage/opt/devkitpro/cmake/"
install -Dm644 "$root/pacman-packages/cmake/wiiu/CafeOS.cmake" \
    "$stage/opt/devkitpro/cmake/Platform/CafeOS.cmake"
install -Dm755 "$root/pacman-packages/cmake/wiiu/powerpc-eabi-cmake" \
    "$stage/opt/devkitpro/portlibs/wiiu/bin/powerpc-eabi-cmake"
install -Dm755 "$source_sdk/portlibs/wiiu/bin/powerpc-eabi-pkg-config" \
    "$stage/opt/devkitpro/portlibs/wiiu/bin/powerpc-eabi-pkg-config"
install -Dm644 "$root/pacman-packages/dkp-toolchain-vars/wiiuvars.sh" \
    "$stage/opt/devkitpro/wiiuvars.sh"
# The packaged helper uses the fixed installation prefix. Relocate its local copy.
sed "s|/opt/devkitpro|$stage/opt/devkitpro|g" \
    "$root/pacman-packages/dkp-toolchain-vars/devkitppc.sh" \
    > "$stage/opt/devkitpro/devkitppc.sh"
