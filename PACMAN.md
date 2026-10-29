# Local pacman repository

The local repository packages the native TLS compiler and application-host RPL
implementation. It replaces five ordinary devkitPro packages at their normal
`/opt/devkitpro` paths. It does not install anything on the Wii U or require a
shared runtime installation there.

This first repository targets the development machine: Arch Linux x86_64.
Host tools use Arch's normal shared libraries. These binaries are not a generic
Linux, Windows, or macOS distribution.

## Build

First build the compiler using the existing staged SDK adapter described in
[README.md](README.md). Then, from the parent development directory:

```sh
python3 wiiu-packages/scripts/build-local-repo.py
```

The packager uses the existing GCC 16.2 build's `install-strip` target and builds
WUT and wut-tools from pinned committed sources in fresh build directories.
It does not switch branches or include uncommitted edits. Source revisions are
listed in the script and copied into the repository's `sources.json`.

`JOBS` defaults to 24. `OVERLAY_RELEASE` defaults to 1 and selects the package
revision `1.1`; increment it when publishing changed packages. Keep source
revisions and package versions in the script current when updating the SDK.
`makepkg` must run as an ordinary user. It and `repo-add` come from pacman;
the other packaging dependencies are fakeroot and zstd. The upstream compiler
and tools build dependencies must already be installed.

Build products are outside this source repository:

```text
../.build/pacman-overlay/
  packages/             generated PKGBUILDs
  logs/                 component and packaging logs
  repo/x86_64/          package archives and wiiu-local.db
  wiiu-local.conf       ready-to-include repository configuration
```

The packages are:

| Package | Contents |
| --- | --- |
| `devkitppc-gcc` | GCC 16.2 with the separate Wii U TLS patch |
| `wut` | Libraries, headers, startup code, TLS lifetime and RPL host binding |
| `wut-tools` | TLS/RPL conversion and import/export tools |
| `wiiu-cmake` | TLS flags and RPL build integration |
| `dkp-toolchain-vars` | Standard environment scripts with Wii U TLS selection |
| `wiiu-sdk-experimental` | Exact dependencies on the five matching versions |

Binutils, newlib, the ordinary devkitPro build rules and unrelated libraries
remain official packages. GCC is packaged using its own install target rather
than by copying the entire staged SDK. Target archives and multilibs are retained;
the host packager does not strip them or remove static libraries.

## Enable and install

The build does **not** edit pacman configuration or install the SDK. For this
machine, publish the generated files outside the private home directory:

```sh
sudo install -d /srv/pacman/wiiu-local
sudo cp -a .build/pacman-overlay/repo/x86_64/. /srv/pacman/wiiu-local/
```

Then add the following section to `/etc/pacman.conf` **before** the existing
devkitPro repository sections:

```ini
[wiiu-local]
SigLevel = Optional
Server = file:///srv/pacman/wiiu-local
```

If the build directory is already readable by pacman's download user, the
generated configuration can be included directly instead:

```ini
Include = /absolute/path/to/.build/pacman-overlay/wiiu-local.conf
```

The package names are unchanged, so repository order matters. Pacman gives the
first repository priority when two repositories contain the same package name.
`SigLevel` is scoped to this local repository; official repository signature
verification is unchanged. The local directory must be traversable and its
packages readable by pacman's download user.

Then perform a normal full upgrade and install the matching set:

```sh
sudo pacman -Syu wiiu-local/wiiu-sdk-experimental
```

The metapackage pins the component versions so an incompatible compiler/tools
mix is not selected during upgrades. Existing build directories need a fresh
CMake configuration to pick up new flags. Recompile translation units using
language TLS; ordinary prebuilt non-TLS libraries need no conversion.

When updating this repository, increase `OVERLAY_RELEASE`, build all packages,
copy the updated repository to `/srv/pacman/wiiu-local` if using that location,
and upgrade the metapackage together with its dependencies. Do not run a partial
system upgrade using only `pacman -Sy`.

## Return to official packages

Remove the experimental metapackage, disable the repository include, then
explicitly select the official packages. Explicit `-S` selection allows returning
to their versions even when these are lower:

```sh
sudo pacman -R wiiu-sdk-experimental
sudo pacman -Syu dkp-linux/devkitppc-gcc dkp-linux/wut-tools \
    dkp-libs/wut dkp-libs/wiiu-cmake dkp-libs/dkp-toolchain-vars
```

Do not mix old WUT/tooling with newly built TLS applications. Reconfigure and
rebuild applications after returning to the official SDK.

## Public distribution later

The same package/database layout can be served over HTTPS. Before making that
a public installation source, build host tools against a documented compatible
host baseline, sign the packages/database, and distribute the public signing key.
Users then change the `Server` URL and use required package signatures.
The repository contains static files; it needs no package-server application.
GCC redistribution also needs the matching source archives, patches and build
instructions. The pinned source manifest is provenance, not a substitute for
providing the corresponding source.
