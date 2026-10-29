# Wii U TLS toolchain work

This directory holds the local patch bundle for native C11 `_Thread_local`,
GNU `__thread`, and C++ `thread_local` support. Nothing here has been published
or installed over the system devkitPro SDK. Pacman repository packaging follows
the working TLS implementation.

## Sources

TLS-only SDK changes live on `wiiu-tls` in the sibling repositories. The
compiler inspection checkout uses `wiiu-tls-16.2`; this directory uses
`tls-16.2`. The earlier validated TLS/RPL setup remains on the `wiiu` branches
and its SDK snapshot is `../.build/sdk-gcc16.1/`.

| Directory | Current upstream baseline | TLS changes |
| --- | --- | --- |
| `../buildscripts` | devkitPPC r51 / `5740da9` | Separate GCC 16.2.0 TLS patch and application step |
| `../gcc` | GCC 16.2.0 plus the original devkitPro package patch | Compiler inspection/rebase; not a build input |
| `../wut` | `937f0d6` | Runtime, template layout, cleanup, SDK selection |
| `../wut-tools` | `b22de1a` | Original contributor's TLS work, then conversion corrections |
| `../pacman-packages` | `b9e8b0d` | Wii U CMake and portlibs environment selection |

The integration target is
[`buildscripts/patches/gcc-16.2.0-wiiu-tls.patch`](../buildscripts/patches/gcc-16.2.0-wiiu-tls.patch).
`build-devkit.sh` applies it after the unchanged `gcc-16.2.0-1.patch`, only for
devkitPPC. The compiler mode remains opt-in; the Wii U SDK selects it. Other
platforms retain their existing defaults.

The `patches/` files contain the rebased WUT, converter, and package changes.
The converter series first applies `wut-tools-tls-base.patch`, preserving the
original contributor's authorship, then `wut-tools-native-tls.patch`. It contains
no unrelated WUHB audio or RPL host-binding work.

## Build and use

From the parent directory, run `bash wiiu-packages/scripts/build-tls-sdk.sh`.
The script snapshots the current local buildscripts commit, downloads the
selected release archives into `../.build/sources/`, applies the normal package
patches followed by the separate TLS patch, and invokes the upstream binutils,
GCC and newlib build stages. It does not compile the patched `../gcc` checkout.
It defaults to 24 build jobs and the host's normal C/C++ compilers. Set
`JOBS`, `HOST_CC`, `HOST_CXX`, or `DEVKITPRO` to override those inputs.
GCC 15 was used for the validated host build.

Build output and logs go in `../.build/devkitPPC-16.2.0/powerpc-eabi/gcc/`,
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

The adapter delegates configure/build/install to upstream stage scripts and
preserves their language, threading, optimization and runtime settings,
including `STDINT_LONG32=0` in nested GCC configurations. Its additions are local
DESTDIR staging, the installed SDK bootstrap, host system zlib, and development
branding/issue routing. It does not maintain a separate configure recipe. The
only buildscripts change is the devkitPPC-specific TLS patch application step.
WUT uses its own Makefile; wut-tools uses its normal Autotools build. Autogen
refreshes generated libtool files in that source checkout; those generated
changes are not part of the patch series.

See [PATCHES.md](PATCHES.md) for the per-file rationale, flag choice, and
remaining upstreaming work. Pacman binary packaging is still a separate step;
this adapter produces a staged SDK, not a replacement package manager.

## Verification

The GCC 16.2.0 / binutils 2.47 / newlib 4.6.0.20260123 SDK and WUT release/debug
archives built with 24 jobs. The separate TLS patch applied after the existing
package patch to the official GCC release archive. The four modified GCC files
match the rebased inspection checkout. The package patch itself is unchanged.

The existing TLS probes passed offscreen Cemu preflight and then the console:

- Initialized/zeroed TLS, external and hidden symbols, and 256-byte alignment.
- Independent values on the main thread, `std::thread` workers, and raw OS threads.
- Cross-translation-unit dynamic initialization and retained values across cores.
- Function-local and namespace-scope C++ TLS destruction, including a destructor
  constructing another TLS object, and main-thread TLS destruction before globals.
- 96 pthread keys, deletion/reuse, and the original LTO application build.
- A separate C11 zero-only template with intact ordinary BSS and independent
  worker/main values; both native probes returned cleanly to Menu.

CMake, the existing Make probe, and `wiiuvars.sh` compilation passed with automatic
SDK selection. No application TLS attributes or manual TLS option were added.
The existing generic/Wii/GameCube assembly probe matches the installed unmodified
GCC 16.1.0 compiler, and the new compiler's default output matches explicit
`-mno-wiiu-tls`. This is a small code-generation control, not a full cross-platform
regression suite. Wii U output calls `__tls_get_addr` without thread-pointer
relocations. The staged compiler retains devkitPro's `int`/`unsigned int` 32-bit
type definitions.

Logs, artifacts and exact commands are in `../.build/tls-16.2/`. The probe sources
remain in `../.build/tls-default/`, `../.build/tls-default-cemu/` and
`../.build/tls-zero/`; no new test framework was added. Cemu's Menu-launch call
remains unsupported, so its C++ exit/destructor control uses the existing variant
that omits that call. The actual native artifacts also reached their completion
markers in Cemu before deployment. Cemu runs used an isolated Xvfb display with
`GDK_BACKEND=x11` and `WAYLAND_DISPLAY` unset.

## Remaining scope

The TLS branches intentionally omit the later RPL host-binding implementation.
It remains available on the preserved `wiiu` branches and is a separate upstream
proposal. Native TLS uses the existing loader resolver; no binutils TLS change
or system modification is required. Upstream review, coordinated package
versions and multi-host binary packaging remain pending. No PR or package has
been published.
