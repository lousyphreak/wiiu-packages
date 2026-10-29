# Native TLS patch overview

## Why a distinct compiler ABI option exists

Wii U, Wii and GameCube use PowerPC CPUs from the same family. In particular,
WUT's `-mcpu=750 -meabi -mhard-float` flags are not a unique Wii U identifier:

| Existing selection | What it controls | Why it cannot imply Wii U TLS |
| --- | --- | --- |
| `-mcpu=750` | CPU instructions and tuning | Also used for Wii and GameCube |
| `-meabi` | Embedded calling convention and small-data conventions | Shared by other embedded PowerPC targets |
| `-mhard-float` | Hardware floating-point code and calling convention | Shared by several platforms |
| `-DESPRESSO`, `-D__WIIU__` | Preprocessor definitions | Source feature macros do not establish a compiler/runtime ABI |
| WUT rules, Wii U CMake platform, `wiiuvars.sh`, `wut.specs` | Wii U SDK selection | Correct place to enable the Wii U TLS ABI by default |

The CPU switch remains exactly as recommended by WUT. `-mwiiu-tls` adds a
different guarantee: TLS references must use the native module resolver rather
than an `r2` thread pointer. WUT does not maintain that thread pointer. Changing
the interpretation of the shared CPU/EABI flags would change code generation
for unrelated targets, which is unnecessary and potentially incompatible with
their runtimes.

The SDK now supplies this option automatically. WUT's Make `MACHDEP`, devkitPro's
Wii U CMake architecture settings, and the Wii U portlibs environment select it
during compilation. WUT specs select it through GCC's existing `self_spec`
mechanism, covering direct compilation and linking. This also lets the existing
conditional WUT link options see the selected mode. Application sources and
normal application build flags do not need a new manual switch.

The SDK settings need to be released with a compiler that understands the new
option. There is no claim that new WUT settings work with an unpatched old GCC.
Objects containing TLS built with the old ABI must be recompiled; there is no
link-time fix for machine code already using `r2` incorrectly.

## Why standard TLS-model flags were insufficient

`-ftls-model=global-dynamic` is an optimization preference, not a prohibition on
other TLS models. GCC's `decl_default_tls_model` can promote accesses to a more
direct model for executable-local symbols. That is valid for the ordinary ELF
TLS ABI, but not for this loader/runtime combination. The emitted non-PIC code
used TPREL relocations and `r2` even with that option. Explicit source attributes
also did not solve the complete compiler-generated guard/initialization case.

`-fPIC` is not an equivalent solution: it changes ordinary code/data accesses,
can still select local-dynamic TLS for internal symbols, and introduces other
relocations. The Wii U module loader does not require all application code to
be PIC. No generic optimization pass needs to be disabled.

The issue and the preference for a compiler-side fix were already discussed in
[WUT PR 155](https://github.com/devkitPro/wut/pull/155).
GCC explicitly documents model promotion in its
[code-generation options](https://gcc.gnu.org/onlinedocs/gcc/Code-Gen-Options.html).
This patch resolves that ABI mismatch behind an opt-in target option; it does
not change generic GCC TLS behavior.

## GCC patch

[`../buildscripts/patches/gcc-16.2.0-wiiu-tls.patch`](../buildscripts/patches/gcc-16.2.0-wiiu-tls.patch)
applies after the unchanged `gcc-16.2.0-1.patch`. The devkitPPC branch of
`build-devkit.sh` applies this separate patch before configuring GCC. It remains
separate from the existing multi-platform package patch.

- `rs6000.opt`: defines `-mwiiu-tls`, default off, saved with target options.
- `rs6000.cc`: the ELF section/symbol hook marks thread-local declarations as
  global-dynamic in that mode, including local symbols and generated guards.
  Existing PowerPC instruction selection still emits the resolver sequence.
- `eabi.h`: C++ compilation in that mode defaults to `-fuse-cxa-atexit` unless
  explicitly disabled. The toolchain's global `--disable-__cxa_atexit` default
  otherwise omits namespace-scope TLS destructor registration. This does not
  change the default for other devkitPPC platforms. It also means ordinary C++
  static destructors in this mode use the C++ ABI registration path.
- `invoke.texi`: documents the new option and its runtime/linker requirements.

The compiler does not implement a second TLS allocator or scheduler mechanism.
It calls the existing native resolver. That has a cost relative to an inline
thread-pointer access, but the latter is not valid for this runtime. No TLS
access microbenchmark has been used to claim an overhead figure.

## WUT runtime and layout patch

`patches/wut-native-tls.patch` contains the runtime and SDK selection changes.

- `cafe/coreinit.def`: enables the existing native `__tls_get_addr` import.
- `share/wut.ld`: collects initialized and zero-initialized TLS into one aligned
  module template. A zero-only template remains NOBITS. Explicitly places
  ordinary BSS after the TLS template, avoiding GNU TLS-BSS overlap semantics.
  Combining the input sections keeps the strongest TLS alignment at the start
  of the native image. A mixed template includes zero bytes in its compressed
  file representation instead of relying on two independently aligned images.
- `share/wut.specs`: selects the mode and disables the linker's ELF TLS
  relaxation. Otherwise binutils could reintroduce thread-pointer accesses
  after GCC generated the correct code. Wraps the existing newlib exit callback
  dispatcher so main-thread TLS is destroyed before globals and atexit callbacks.
- `share/wut_rules`: enables the mode for normal Make compilation; existing
  templates only supply the specs file at link time.
- `wut_tls.c`: supplies the missing newlib pthread-key operations. A fixed key
  registry plus per-thread values implements key creation, deletion and reuse;
  generation tokens prevent a reused key from exposing a deleted key's value.
  It uses one existing WUT thread-specific slot, not one native OS slot per key.
- The same file implements `__cxa_thread_atexit` with a per-thread LIFO list.
  Removing each entry before calling it allows destructors to construct/register
  additional TLS objects without losing or double-destroying entries.
- `wut_reent.c` and its internal header: run key/destructor cleanup inside the
  existing OS thread cleanup callback, before reclaiming the newlib context.

Language TLS storage itself is allocated and freed by the native loader. The
pthread-key array is a separate 128-entry structure (1 KiB per participating
thread), allocated lazily. Each C++ destructor-list node is 16 bytes on PPC32,
plus the allocator's overhead. Threads not using keys or C++ TLS destructors
do not allocate those structures.

The later module-unloading extension is excluded from these TLS-only branches.
Its containing-module references and host bindings remain on the preserved
`wiiu` branches for separate review.

## Converter patches

The upstream release still needs the earlier TLS work from
[wut-tools PR 6](https://github.com/devkitPro/wut-tools/pull/6).
`wut-tools-tls-base.patch` preserves that contributor's original commit and
adds native TLS flags, module metadata and initial descriptor conversion.
`wut-tools-native-tls.patch` then corrects the converter behavior:

- Normalizes data-section flags before skipping NOBITS sections, and translates
  ELF TLS flags for initialized and zero-only templates alike.
- Removes a spurious executable flag from data-range sections. GNU's TLS GOT
  contains an unused branch stub which otherwise makes a combined data section
  appear executable to the native loader; this caused a real pre-main loader
  alignment failure.
- Derives both native descriptor relocations from each GOT descriptor reference:
  DTPMOD32 for the module word and DTPREL32 for the offset word.
- Treats the TLS call relocation as a marker. It no longer assumes that the
  immediately preceding instruction identifies the descriptor; scheduling and
  common-subexpression elimination invalidate that assumption.
- Deduplicates repeated descriptor references and writes relocation records
  into the relocation section belonging to the descriptor's actual data section,
  creating that section if necessary. Code and GOT need not share a section.

No GNU binutils source change is needed for the verified path. The existing
linker supports the required relocations and `--no-tls-optimize`; elf2rpl
performs the ELF-to-native relocation translation.

## Build/package integration and upstream submission boundaries

The SDK adapter snapshots the current buildscripts commit based on devkitPPC
r51 and uses its GCC 16.2.0, binutils 2.47 and newlib 4.6.0.20260123 selections.
Release archives receive the existing package patches and then the separate
Wii U TLS patch. Configure/build/install still use the upstream stage scripts,
with local DESTDIR staging rather than a second configure recipe.

The upstream host preprocessor flags are exported through nested configure/make;
dropping `STDINT_LONG32=0` previously changed `int32_t`/`uint32_t` from devkitPro's
`int`/`unsigned int` to `long`/`unsigned long` and broke C++ signatures. The
adapter preserves that upstream input. The installed SDK bootstraps newlib
headers and tools; binutils, GCC and newlib are rebuilt into the local stage.
This is not yet a published binary pacman repository.

`pacman-packages-tls.patch` changes only Wii U settings plus their source
checksums: `cmake/wiiu/CafeOS.cmake` and `dkp-toolchain-vars/wiiuvars.sh` select
the mode at compile time. Other platform scripts and the common toolchain
configuration remain unchanged.

Upstream review should keep the compiler ABI change, original converter TLS
work plus corrections, WUT runtime/layout, and Wii U build integration separate.
The bundle excludes unrelated features already present on the development
branches. A release needs coordinated compiler/WUT/tool/package dependencies,
with final versions assigned during that release; fabricated package-version
requirements would not establish compatibility today.

The TLS branch excludes RPL host bindings, embedded-module packaging and the
unrelated WUT/backend additions. Earlier native TLS and RPL evidence remains in
the preserved development branches; current baseline verification is recorded
in the README. No upstream PR or package publication has been performed.
