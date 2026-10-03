# compile-ffmpeg for MacOS/Linux

Build script for compiling ffmpeg under MacOS and Linux.

It currently supports decklink and NDI from Newtek, but since NDI is not officially supported, there is no guarantee that the patch will work forever. To use NDI, you need the lib from the NDI SDK, which can be downloaded from [here](https://www.ndi.tv/sdk/). For using decklink, Desktop Video from [blackmagic](https://www.blackmagicdesign.com/de/support/) need to be installed.

For MacOS is needed: homebrew with installed:

```
cmake git wget curl pkg-config nasm autoconf automake libtool autogen \
gnu-sed sdl2 shtool ninja cargo cargo-c meson rsync
```

For Linux (ubuntu/debian) is needed:

```
sudo apt install autoconf automake build-essential libtool pkg-config texi2html \
yasm cmake curl git wget gperf ninja-build cargo cargo-c nasm meson rsync xxd uuid-dev
```
On Ubuntu install cargo-c with `cargo install cargo-c`

For rhel based/fedora install:

```
dnf group install "Development Tools"

dnf install libstdc++-static libtool cmake ninja-build cargo ragel meson \
cargo-c gcc-c++ python3-devel gperf perl glibc-static binutils-devel nasm \
rsync xxd
```

Install `sdl2/libsdl2-dev` only if you need ffplay or opengl!

NOTE: Make sure the full path where you check out this project does not contain any spaces or the script will not work.

Choose FFmpeg linkage with `--linkage=static|shared|both`:

```sh
./compile-ffmpeg.sh --linkage=static   # default
./compile-ffmpeg.sh --linkage=shared
./compile-ffmpeg.sh --linkage=both
```

| Mode | Programs | Libraries and headers |
| --- | --- | --- |
| Static | `local/bin/` | `local/lib/*.a`, `local/include/` |
| Shared | `local/ffmpeg-shared/bin/` | `local/ffmpeg-shared/lib/`, `local/ffmpeg-shared/include/` |

Each prefix has its own `lib/pkgconfig/`. Building one mode keeps the other mode's
installation. FFmpeg is reconfigured and rebuilt on every invocation, including
when options change without an upstream source update. `--linkage=both` builds
the modes sequentially from the same checkout. Use `--ffmpeg-only=y` together
with `--linkage` to reuse already built codec dependencies.

Codec dependencies continue to be installed as static libraries in `local/`.
The shared mode links them into FFmpeg's shared libraries, producing `.dylib`
files on macOS and `.so` files on Linux. Dependencies must be compiled with PIC;
when reusing older Linux dependency builds, rebuild their archives before using
the shared mode. Static FFmpeg on macOS still uses Apple's system libraries and
frameworks; it is not a fully static macOS executable.

For Rust with `ffmpeg-next`, use a released FFmpeg branch that matches the crate
version rather than the development branch. For example, for `ffmpeg-next` 8:

```sh
./compile-ffmpeg.sh --linkage=both --ffmpeg-branch=release/8.0
```

The script otherwise uses FFmpeg's upstream default branch. When changing the
FFmpeg release, rebuild both modes if you want to keep both on the same release.
Architecture is detected automatically; Rust must target the same architecture
as the installed FFmpeg libraries (also relevant when using Rosetta).

In the Rust project's `Cargo.toml`:

```toml
[dependencies]
ffmpeg-next = "8"

[features]
ffmpeg-static = ["ffmpeg-next/static"]
```

To link dynamically, run these commands in the Rust project. Replace the example
repository path with the absolute path to this repository:

```sh
export FFMPEG_PREFIX="/absolute/path/to/compile-ffmpeg-osx-linux/local/ffmpeg-shared"
unset FFMPEG_DIR PKG_CONFIG_ALL_STATIC PKG_CONFIG_ALL_DYNAMIC
export PKG_CONFIG_PATH="$FFMPEG_PREFIX/lib/pkgconfig"
pkg-config --modversion libavcodec
pkg-config --variable=libdir libavcodec
export CARGO_TARGET_DIR="target/ffmpeg-shared"
export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C link-arg=-Wl,-rpath,$FFMPEG_PREFIX/lib"
cargo run
```

`ffmpeg-sys-next` (used by `ffmpeg-next`) finds headers and link flags via
`pkg-config` when `FFMPEG_DIR` is unset. The Cargo `static` feature selects static
linking; leave it disabled for shared linking. Do not enable the crate's `build`
feature when using the installation from this script. See the upstream
[build script](https://github.com/zmwangx/rust-ffmpeg-sys/blob/master/build.rs) and
[versioning notes](https://github.com/zmwangx/rust-ffmpeg#readme).

The Rust executable also needs to find shared libraries at runtime. The example
embeds an absolute rpath for local development. FFmpeg's own shared programs use
`--enable-rpath`; macOS libraries also use their absolute installation names.
Keep that installation at its build path. Shipping an application requires
bundling its shared dependencies and setting relative loader paths/install names.
Check the resulting executable with `otool -L` on macOS or `ldd` on Linux.

To link FFmpeg statically in the Rust project instead, use a fresh shell (so the
dynamic example's `RUSTFLAGS` does not carry over):

```sh
export FFMPEG_PREFIX="/absolute/path/to/compile-ffmpeg-osx-linux/local"
unset FFMPEG_DIR PKG_CONFIG_ALL_STATIC PKG_CONFIG_ALL_DYNAMIC
export PKG_CONFIG_PATH="$FFMPEG_PREFIX/lib/pkgconfig"
export CARGO_TARGET_DIR="target/ffmpeg-static"
cargo run --features ffmpeg-static
```

Use `pkg-config` for static linking too, so private codec dependencies are
included. Separate Cargo target directories keep the two Rust build variants
apart. Both variants require `pkg-config` and a working libclang for bindgen.

**Warning: the ffmpeg version is "nonfree", you are not allowed to redistribute or share the compiled binary!**

These scripts are mostly for personal use - there will not be much support.

Feel free to fork and modify them.

A more active windows version can be found here: https://github.com/jb-alvarado/media-autobuild_suite
