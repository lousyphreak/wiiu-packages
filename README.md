# Wii U TLS toolchain work

This directory holds the local patch bundle for native C11 `_Thread_local`,
GNU `__thread`, and C++ `thread_local` support. Nothing here has been published
or installed over the system devkitPro SDK. Pacman repository packaging follows
the working TLS implementation.

## Sources

Sibling checkouts, relative to this directory:

| Directory | Baseline | TLS commit |
| --- | --- | --- |
| `../gcc` | GCC `releases/gcc-16.1.0`, then devkitPPC package patches at `43a9556d0` | `67816438e` |
| `../wut` | `a5d1c8dce4289392723edd83ecba4b0e416392dd` | `22eace9` |
| `../wut-tools` | `8b5b72366fd82791aea5323f8cc9b903e54a92c8` | `09ae765` |

The `patches/` files contain the TLS commits, including the new WUT runtime file.
The GCC patch applies after the devkitPPC package patch, not directly to the
unmodified GCC release.

## Build and use

From the parent directory, run `bash wiiu-packages/scripts/build-tls-sdk.sh`.
The script uses the installed devkitPPC binutils/newlib and the existing source
checkouts. It defaults to 24 build jobs and GCC 15 as the host compiler. Set
`JOBS`, `HOST_CC`, `HOST_CXX`, or `DEVKITPRO` to override those inputs.

Build output and logs go in `../.build/`. The staged SDK is
`../.build/sdk/opt/devkitpro`; the installed SDK remains unchanged. Point
`DEVKITPRO` and `DEVKITPPC` at that staged SDK and add `-mwiiu-tls` to both
compilation and linking, alongside the normal WUT specs. Use the staged
`elf2rpl` converter too. All translation units containing language TLS need
the new compiler mode; ordinary prebuilt libraries can remain unchanged.

The option keeps TLS references on the module resolver path, including local
variables and compiler-generated guards. It enables C++ destructor registration
by default. Explicitly disabling `-fuse-cxa-atexit` prevents namespace-scope C++
TLS destructors from being registered. WUT disables linker TLS relaxation and
destroys main-thread TLS before ordinary exit callbacks and static objects.

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

## Remaining scope

This establishes TLS in RPX applications. It does not establish general RPL
creation, cross-module TLS imports, or safe module unloading while other threads
still own objects from that module. The C++ registration entry currently does
not retain its DSO argument. Module lifetime integration must precede any claim
of unloadable C++ TLS support. No binutils patch was needed for the verified path.
