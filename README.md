# compile-ffmpeg for MacOS/Linux

Build script for compiling ffmpeg under MacOS and Linux.

It currently supports decklink and NDI from Newtek, but since NDI is not officially supported, there is no guarantee that the patch will work forever. To use NDI, you need the lib from the NDI SDK, which can be downloaded from [here](https://www.ndi.tv/sdk/). For using decklink, Desktop Video from [blackmagic](https://www.blackmagicdesign.com/de/support/) need to be installed.

For MacOS is needed: homebrew with installed:

```
cmake git mercurial wget curl pkg-config nasm autoconf automake libtool autogen \
gnu-sed sdl2 shtool ninja-build cargo cargo-c
```

For Linux (ubuntu/debian) is needed:

```
sudo apt install autoconf automake build-essential libtool pkg-config texi2html \
yasm cmake curl git mercurial wget gperf ninja-build cargo cargo-c
```

(debian needs sudo for install nasm to /usr/local/bin/)

For rhel based/fedora install:

```
dnf group install "Development Tools"

dnf install mercurial libstdc++-static libtool cmake ninja-build cargo \
cargo-c gcc-c++ python3-devel gperf perl glibc-static binutils-devel
```

For libdav1d install meson: `pip3 install --upgrade --user meson`.

Install `sdl2/libsdl2-dev` only if you need ffplay or opengl!

NOTE: Make sure the full path where you check out this project does not contain any spaces or the script will not work.

**Warning: the ffmpeg version is "nonfree", you are not allowed to redistribute or share the compiled binary!**

These scripts are mostly for personal use - there will not be much support.

Feel free to fork and modify them.

A more active windows version can be found here: https://github.com/jb-alvarado/media-autobuild_suite
