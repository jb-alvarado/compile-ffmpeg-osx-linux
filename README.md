# compile-ffmpeg-osx / linux
Build script for compiling ffmpeg under OSX and linux (ubuntu/debian)

For OSX is needed: homebrew with installed: cmake mercurial git wget curl pkg-config nasm autoconf automake libtool autogen gnu-sed sdl2 shtool

For Linux (ubuntu/debian) is needed: sudo apt install autoconf automake build-essential libtool pkg-config texi2html yasm cmake curl mercurial git wget gperf (debian needs sudo for install nasm to /usr/local/bin/)

For Centos install: `yum group install "Development Tools"`

Install sdl2/libsdl2-dev only when you need ffplay or opengl!

NOTE: make sure the full path where you checkout this project does not contain any spaces or the script will not work.

Warning: the ffmpeg version is "nonfree", you are not allow to redistribute or share this version!

This scripts are mostly for private use - there will be not much support.

Feel free to fork and modify.

A more active windows version you found here: https://github.com/jb-alvarado/media-autobuild_suite
