# compile-ffmpeg for MacOS/Linux

Build script for compiling ffmpeg under MacOS and Linux.

It currently supports decklink and NDI from Newtek, but since NDI is not officially supported, there is no guarantee that the patch will work forever. To use NDI, you need the lib from the NDI SDK, which can be downloaded from [here](https://www.ndi.tv/sdk/). For using decklink, Desktop Video from [blackmagic](https://www.blackmagicdesign.com/de/support/) need to be installed.

For MacOS is needed: homebrew with installed:

```
cmake git wget curl pkg-config nasm autoconf automake libtool autogen \
gnu-sed sdl2 shtool ninja-build cargo cargo-c meson rsync
```

For Linux (ubuntu/debian) is needed:

```
sudo apt install autoconf automake build-essential libtool pkg-config texi2html \
yasm cmake curl git wget gperf ninja-build cargo cargo-c nasm meson rsync xxd
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

**Warning: the ffmpeg version is "nonfree", you are not allowed to redistribute or share the compiled binary!**

These scripts are mostly for personal use - there will not be much support.

Feel free to fork and modify them.

A more active windows version can be found here: https://github.com/jb-alvarado/media-autobuild_suite
