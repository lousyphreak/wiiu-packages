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
settings, including its `STDINT_LONG32=0` host-build setting in nested GCC
configurations. Its additions are local DESTDIR staging, an installed newlib/binutils
bootstrap, host system zlib, and development branding/issue routing. It does not
modify devkitPro's scripts or maintain its own GCC configure-options list.
WUT uses its own Makefile; wut-tools uses its normal Autotools build. Autogen
refreshes generated libtool files in that source checkout; those generated
changes are not part of the patch series.

See [PATCHES.md](PATCHES.md) for the per-file rationale, flag choice, and
remaining upstreaming work. Pacman binary packaging is still a separate step;
this adapter produces a staged SDK, not a replacement package manager.

## Dynamic modules

The implementation uses the existing native loader and loose RPL files on the
SD card. Each application owns its GCC/newlib/WUT runtime in its RPX. There is
no companion runtime RPL, shared runtime installation, SD cache, extraction, or
Aroma/Mocha modification.

Build application exports with `wut_add_exports(app host.def HOST)`. Build a
module with `wut_link_rpl(module app)` and `wut_create_rpl(module)`. The host
manifest lists application/runtime functions under `:TEXT`, ordinary objects
under `:DATA`, and thread-local objects under `:TLS`. Keep native OS imports as
normal WUT imports. Module code and every implementation archive included in it
must use `-fPIC -msdata=none -msecure-plt`. The CMake helper applies these flags to
the module target; prebuilt archives must be rebuilt separately. Host-bound
modules link without default static runtime libraries, so omitted runtime imports
fail at link time instead of quietly embedding a second runtime.

Generated module call veneers use writable pointer slots. Taking a function's
address resolves to the real host address. Ordinary data and TLS descriptors
are bound before module constructors through `__wut_bind_imports_v1` exported
by the RPX. Missing imports fail the native acquisition before constructors run.
The loader retains code while registered C++ TLS destructors still need it.
Module-local `atexit` forwards to `__cxa_atexit` with the module DSO, so C callbacks
and C++ static destructors both finish before unload using the same runtime list.
Applications still must finish module calls and destroy ordinary module objects
before releasing their last explicit handle.

Open a module with `OSDynLoad_Acquire`, find its exports with
`OSDynLoad_FindExport`, and release it with `OSDynLoad_Release`. Existing Aroma
supports explicit SD paths encoded as `~|wiiu|apps|myapp|engine.rpl` or, for a
shared compiler, `~|wiiu|lib|cafeglsl1.rpl`. Each `|` represents `/`, starting at
the SD root. The encoded stem before `.rpl` must fit the native 59-byte filename
limit. This is an existing loader route, not a new system patch.

An RPX or WUHB application may load these loose files. RPL files embedded inside
a WUHB are outside this implementation: the application content mount is not a
native module source.

Private engines should use the same toolchain/runtime build as their host.
Independently updated global modules should expose a stable C interface with
opaque objects and matching create/destroy functions. They must retain a
compatible host-runtime import baseline; missing newer symbols cause a normal
load failure, and a genuinely incompatible runtime requires a new module ABI.
This does not promise compatibility across arbitrary GCC/newlib ABI changes.

The patched Cemu is an independent Git checkout at `../Cemu`. Its fresh build
is `../Cemu/.build/cemu-rpl`, preserving the previous graphics work. Standalone
homebrew encoded paths read files directly from its configured `sdcard/`
directory. Native filename identity, initialization errors, reference counts,
TLS templates/alignment and destructor ordering are checked against retail
loader evidence. Guest NX enforcement and physical aliases are still incomplete
in Cemu; its API emulation is not proof of a custom executable-memory loader.

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
The original Cemu run used fixed 32-byte TLS alignment; the loader updates now
use the module alignment. Cemu still does not implement the probe's Menu-launch
call; native lifecycle results were verified separately on hardware. Offscreen Cemu must use `GDK_BACKEND=x11` with an
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

## Dynamic-module validation

Built the modified tools, WUT, native module/host artifacts and relocated Cemu
with parallelism 24. The local SDK now preserves devkitPro's integer-type build
setting throughout the compiler and runtime build.

Offscreen Cemu checks completed:

- Direct loose SD-file loading, duplicate handles, final unload and reload.
- Constructor-time host function/data access and canonical function pointers.
- C++ exceptions thrown in the module and caught by the host.
- A worker started before module loading, initialized/zeroed and 256-byte-aligned
  module TLS, independent imported host TLS, and delayed unload until its TLS
  destructor completes.
- Missing imports rejected before constructors; failed module entry finalized
  once without publishing a handle.
- Ordinary static-only application startup and existing thread-local lifetime.
- The real CafeGLSL PIC archive loaded as a 2.7 MiB loose RPL, compiled a shader
  pair, freed the results, unloaded, reloaded and repeated. Its 208-byte vertex
  and 8-byte pixel programs matched the host compiler's instruction hashes.
  Host process exit also completed after both module unloads.

CafeGLSL needed no source changes. Its runtime import contract currently has
179 live functions and 12 data objects (plus module-local `atexit`); the
module contains one implementation archive and uses the application's runtime. The original ScummVM engine port is
not part of this SDK slice; the worker/module lifetime exercised here covers the
loader mechanics it needs, rather than claiming an engine integration run.

Reproduction artifacts and complete logs are local under
`../.build/rpl-native/`, `../.build/rpl-cafeglsl/` and
`../.build/rpl-validation/`. Native-loader evidence and emulator limitations are
recorded in `../.build/native-loader-research/`. This is Cemu validation, not a
native-console pass; emulator timings are not hardware performance figures.

## Remaining scope

The native-console results above establish RPX TLS. Dynamic module integration
has passed the offscreen Cemu checks below; native-console RPL verification is
still pending. No
binutils patch is needed for the implemented path. Embedded WUHB modules and
arbitrary inter-module dependency discovery remain outside this implementation.
