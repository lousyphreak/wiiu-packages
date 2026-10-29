# Wii U TLS toolchain work

This directory holds the local patch bundle for native C11 `_Thread_local`,
GNU `__thread`, and C++ `thread_local` support. Nothing here has been published
or installed over the system devkitPro SDK. Pacman repository packaging follows
the working TLS implementation.

## Sources

Sibling checkouts, relative to this directory:

| Directory | Baseline | TLS commit |
| --- | --- | --- |
| `../gcc` | GCC `releases/gcc-16.1.0`, then devkitPPC package patches at `43a9556d0` | `67816438e`, `f4bc1a3b4` |
| `../wut` | `a5d1c8dce4289392723edd83ecba4b0e416392dd` | `22eace9`, `de81d0a` |
| `../wut-tools` | `8b5b72366fd82791aea5323f8cc9b903e54a92c8` | `09ae765` |
| `../pacman-packages` | `b9e8b0de6a6423557fd2a57dc100bf327c79dd4a` | `daa1673` |

The `patches/` files contain the TLS changes, including the new WUT runtime file.
The GCC patch applies after the devkitPPC package patch, not directly to the
unmodified GCC release. The converter series first applies
`wut-tools-tls-base.patch`, preserving the existing TLS contributor's commit,
then `wut-tools-native-tls.patch`. Neither includes unrelated WUHB audio changes.

The build adapter uses the unmodified GCC stage scripts from devkitPro's
`devkitPPC_r50` release (`7a8c81eeccb4890c7abfe4677a21100909beff64`).
It deliberately retains the verified GCC 16.1.0/binutils/newlib baseline rather
than silently adopting the newer versions on the buildscripts master branch.
The updated Wii U settings in `../pacman-packages` cover `wiiu-cmake` and
`dkp-toolchain-vars`; other platform settings are unchanged.

## Build and use

From the parent directory, run `bash wiiu-packages/scripts/build-tls-sdk.sh`.
The script uses the installed devkitPPC binutils/newlib and the existing source
checkouts, with the r50 tag available in `../buildscripts`. It defaults to 24
build jobs and the host's normal C/C++ compilers. Set
`JOBS`, `HOST_CC`, `HOST_CXX`, or `DEVKITPRO` to override those inputs.
GCC 15 was used for the validated host build.

Build output and logs go in `../.build/devkitPPC/powerpc-eabi/gcc/`,
`../.build/wut-tools/`, and `../.build/wut-install.log`. The staged SDK is
`../.build/sdk/opt/devkitpro`; the installed SDK remains unchanged. Point
`DEVKITPRO` and `DEVKITPPC` at that staged SDK. Normal WUT Make builds, devkitPro
Wii U CMake builds, and `wiiuvars.sh` builds now select TLS automatically. Direct
compiler invocations select it with the normal `-specs=.../wut.specs` at compile
and link time. Use the staged `elf2rpl` converter too. All translation units
containing language TLS need recompilation with these settings; ordinary
prebuilt libraries can remain unchanged. Existing CMake builds need to be
reconfigured to obtain the updated compile flags.

`-mwiiu-tls` remains the low-level compiler ABI option. It is supplied by the
Wii U SDK settings, not an extra flag required in application Makefiles.
The updated WUT settings require the patched compiler and converter. They are
not compatible with an older compiler that does not recognize this option.

The option keeps TLS references on the module resolver path, including local
variables and compiler-generated guards. It enables C++ destructor registration
by default. Explicitly disabling `-fuse-cxa-atexit` prevents namespace-scope C++
TLS destructors from being registered. WUT disables linker TLS relaxation and
destroys main-thread TLS before ordinary exit callbacks and static objects.

The adapter delegates GCC configure/build/install to the released upstream
stage scripts and preserves their language, threading, optimization and runtime
settings. Its additions are local DESTDIR staging, an installed newlib/binutils
bootstrap, host system zlib, and development branding/issue routing. It does not
modify devkitPro's scripts or maintain its own GCC configure-options list.
WUT uses its own Makefile; wut-tools uses its normal Autotools build. Autogen
refreshes generated libtool files in that source checkout; those generated
changes are not part of the patch series.

See [PATCHES.md](PATCHES.md) for the per-file rationale, flag choice, and
remaining upstreaming work. Pacman binary packaging is still a separate step;
this adapter produces a staged SDK, not a replacement package manager.

## Verification

Native console probes passed with the staged toolchain:

- Initialized and zero-only TLS, external and hidden symbols, and 256-byte alignment.
- Independent values on the main thread, `std::thread` workers, and raw OS threads.
- Cross-translation-unit dynamic initialization and values retained across core migration.
- Function-local and namespace-scope C++ TLS destruction, including a destructor
  constructing another TLS object, and main-thread TLS destruction before globals.
- 96 pthread keys, deletion/reuse, and an LTO build.
- Zero-only TLS storage without overlap with ordinary BSS; clean return to Menu.

Scratch probe sources and logs are in `../.build/tls-native/` and
`../.build/tls-zero/`. Cemu also passed worker initialization and lifetime checks.
This Cemu checkout uses fixed 32-byte TLS alignment and does not implement the
probe's Menu-launch call; those are emulator limitations, verified separately
against the hardware results. Offscreen Cemu must use `GDK_BACKEND=x11` with an
isolated Xvfb display and `WAYLAND_DISPLAY` unset.

The upstream-stage rebuild and automatic SDK selection also passed a normal
devkitPro CMake build, a `wiiuvars.sh` compilation, and the complete lifetime
probe in offscreen Cemu (without its unsupported Menu-launch call). A stock vs
patched compiler comparison produced identical generic, Wii and GameCube TLS
assembly, excluding the compiler identity string. Logs are in
`../.build/tls-default/` and `../.build/tls-default-cemu/`.

The default CMake RPX itself was subsequently checked offscreen in Cemu, then
the identical artifact passed on the console, including all worker and
main-thread destructors and clean return to Menu. Its SHA-256 and native log
are saved in `../.build/tls-default/`. Cemu stops at that probe's Menu-launch
call; the variant mentioned above skips only this unsupported lifecycle call.

Export `DEVKITPRO` and `DEVKITPPC` for both CMake configuration and subsequent
builds, not just configuration: WUT's linker specs use `DEVKITPRO` at link time.

## Remaining scope

This establishes TLS in RPX applications. It does not establish general RPL
creation, cross-module TLS imports, or safe module unloading while other threads
still own objects from that module. The C++ registration entry currently does
not retain its DSO argument. Module lifetime integration must precede any claim
of unloadable C++ TLS support. No binutils patch was needed for the verified path.
