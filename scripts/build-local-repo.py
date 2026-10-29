#!/usr/bin/env python3
"""Package the locally built TLS compiler and pinned RPL sources for pacman."""

import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import subprocess
import tarfile


root = Path(__file__).resolve().parents[2]
output = root / ".build/pacman-overlay"
sdk = root / ".build/sdk/opt/devkitpro"
jobs = os.environ.get("JOBS", "24")
release = os.environ.get("OVERLAY_RELEASE", "1")
pkgrel = f"1.{release}"
arch = platform.machine()
refs = {
    "buildscripts": "8f7c45b4251286c392c7415e539184c47e9eda02",
    "wut": "672dc14788fa551b7e6804faedff48ea0603c8be",
    "wut-tools": "56a396f88994f40cc7c24345a0903919019219f8",
    "pacman-packages": "d204c60a698f429405fe35cc28fa7e4e485c1c28",
}
repo = output / "repo" / arch
repo.mkdir(parents=True, exist_ok=True)
logs = output / "logs"
logs.mkdir(exist_ok=True)


def run(args, *, cwd=None, env=None, log=None):
    print(shlex.join(map(str, args)), flush=True)
    if log:
        with (logs / log).open("w") as stream:
            subprocess.run(args, cwd=cwd, env=env, stdout=stream,
                           stderr=subprocess.STDOUT, check=True)
    else:
        subprocess.run(args, cwd=cwd, env=env, check=True)


def snapshot(name, ref, destination):
    destination.mkdir(parents=True, exist_ok=True)
    archive = output / "source.tar"
    run(["git", "-C", str(root / name), "archive", "-o", str(archive), ref])
    with tarfile.open(archive) as source:
        source.extractall(destination, filter="data")
    archive.unlink()


# Build from committed files without switching branches or carrying generated edits.
sources = output / "sources"
shutil.rmtree(sources, ignore_errors=True)
for name in ("wut", "wut-tools", "pacman-packages"):
    snapshot(name, refs[name], sources / name)
for path, ref in (
    ("libraries/excmd", "b48dab4954bdc074d7768e38065171441aaff7ce"),
    ("libraries/fmt", "5386f1df20392a08844f5034e8436c6ec7ce0b03"),
):
    snapshot("wut-tools/" + path, ref, sources / "wut-tools" / path)

stage = output / "stage"
shutil.rmtree(stage, ignore_errors=True)
stage.mkdir()
run(["make", "-C", str(root / ".build/devkitPPC-16.2.0/powerpc-eabi/gcc"),
     f"-j{jobs}", f"DESTDIR={stage / 'devkitppc-gcc'}", "install-strip"],
    log="gcc-install.log")

env = os.environ.copy()
env.update(DEVKITPRO="/opt/devkitpro", DEVKITPPC=str(sdk / "devkitPPC"),
           DESTDIR=str(stage / "wut"))
env["PATH"] = f"{sdk}/tools/bin:{sdk}/devkitPPC/bin:" + env["PATH"]
run(["make", "-C", str(sources / "wut"), f"-j{jobs}", "install",
     f"CC={sdk}/devkitPPC/bin/powerpc-eabi-gcc",
     f"CXX={sdk}/devkitPPC/bin/powerpc-eabi-g++"],
    env=env, log="wut-build.log")

run(["./autogen.sh"], cwd=sources / "wut-tools", log="tools-autogen.log")
tools_build = output / "tools-build"
shutil.rmtree(tools_build, ignore_errors=True)
tools_build.mkdir()
run([str(sources / "wut-tools/configure"), "--prefix=/opt/devkitpro/tools"],
    cwd=tools_build, log="tools-configure.log")
run(["make", f"-j{jobs}"], cwd=tools_build, log="tools-build.log")
run(["make", f"-j{jobs}", f"DESTDIR={stage / 'wut-tools'}", "install-strip"],
    cwd=tools_build, log="tools-install.log")

# Use the upstream data-package recipes' file sets, without relocating prefixes.
cmake = sources / "pacman-packages/cmake/wiiu"
for source, destination in (
    ("powerpc-eabi-cmake", "portlibs/wiiu/bin/powerpc-eabi-cmake"),
    ("WiiU.cmake", "cmake/WiiU.cmake"),
    ("CafeOS.cmake", "cmake/Platform/CafeOS.cmake"),
):
    target = stage / "wiiu-cmake/opt/devkitpro" / destination
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(cmake / source, target)
variables = stage / "dkp-toolchain-vars/opt/devkitpro"
variables.mkdir(parents=True)
for source in (sources / "pacman-packages/dkp-toolchain-vars").glob("*.sh"):
    shutil.copy2(source, variables / source.name)

versions = {"devkitppc-gcc": "16.2.0", "wut": "1.9.1", "wut-tools": "1.3.5",
            "wiiu-cmake": "1.3.2", "dkp-toolchain-vars": "1.0.5"}
packages = [
    ("devkitppc-gcc", arch, "GPL-3.0-or-later", "devkitPPC GCC with native Wii U TLS",
     ["devkitppc-binutils", "devkitppc-newlib", "devkitppc-rules", "devkitppc-crtls",
      "glibc", "gcc-libs", "libisl", "libmpc", "mpfr", "gmp", "zlib", "zstd"]),
    ("wut-tools", arch, "GPL-2.0-only", "Wii U tools with native TLS and RPL host bindings",
     ["glibc", "gcc-libs", "zlib", "freeimage"]),
    ("wut", "any", "Zlib", "Wii U libraries with native TLS and application RPL support",
     ["devkitPPC", f"devkitppc-gcc>=16.2.0-{pkgrel}", f"wut-tools>=1.3.5-{pkgrel}"]),
    ("wiiu-cmake", "any", "LicenseRef-devkitPro", "Wii U CMake helpers with RPL host bindings",
     ["devkitppc-cmake", f"wut-tools>=1.3.5-{pkgrel}", "wiiu-pkg-config"]),
    ("dkp-toolchain-vars", "any", "LicenseRef-devkitPro", "devkitPro environments with native Wii U TLS",
     [f"devkitppc-gcc>=16.2.0-{pkgrel}"]),
]
versions["wiiu-sdk-experimental"] = "20261029"
packages.append(("wiiu-sdk-experimental", "any", "MIT", "Matching local Wii U TLS and RPL SDK packages",
                 [f"{name}={versions[name]}-{pkgrel}" for name in versions if name != "wiiu-sdk-experimental"]))

# Keep makepkg responsible for package metadata, mtree and compression.
makepkg_config = output / "makepkg.conf"
makepkg_config.write_text(Path("/etc/makepkg.conf").read_text() +
                         f"\nPKGDEST={shlex.quote(str(repo))}\n"
                         f"MAKEFLAGS=-j{jobs}\nCOMPRESSZST=(zstd -c -T{jobs} -3)\n")
archives = []
for name, package_arch, license_name, description, depends in packages:
    recipe = output / "packages" / name
    recipe.mkdir(parents=True, exist_ok=True)
    lines = [f"pkgname={name}", f"pkgver={versions[name]}", f"pkgrel={pkgrel}",
             f"pkgdesc={shlex.quote(description)}", f"arch=({package_arch})",
             "url=https://github.com/lousyphreak/wut", f"license=({license_name})",
             "options=(!strip !debug !lto staticlibs libtool !zipman !purge)",
             "depends=(" + " ".join(shlex.quote(d) for d in depends) + ")"]
    if name == "dkp-toolchain-vars":
        lines.append("conflicts=(devkitpro-pkgbuild-helpers)")
    lines.append("package() {")
    if name != "wiiu-sdk-experimental":
        lines.append(f'    cp -a {shlex.quote(str(stage / name))}/. "$pkgdir/"')
    lines.append("}")
    # An empty metapackage still needs a valid shell function body.
    if name == "wiiu-sdk-experimental":
        lines[-1:] = ["    :", "}"]
    (recipe / "PKGBUILD").write_text("\n".join(lines) + "\n")
    run(["makepkg", "--config", str(makepkg_config), "--nodeps", "--force"],
        cwd=recipe, log=name + "-package.log")
    archives.append(str(repo / f"{name}-{versions[name]}-{pkgrel}-{package_arch}.pkg.tar.zst"))

run(["repo-add", str(repo / "wiiu-local.db.tar.gz"), *archives], log="repo-add.log")
(repo / "sources.json").write_text(json.dumps(refs, indent=2) + "\n")
(output / "wiiu-local.conf").write_text(
    "[wiiu-local]\nSigLevel = Optional\nServer = " + repo.as_uri() + "\n")
print(f"\nRepository: {repo}\nConfiguration: {output / 'wiiu-local.conf'}")
