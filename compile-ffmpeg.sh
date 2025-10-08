#!/bin/bash

#ffmpeg_shared="yes"
#ffmpeg_branch="release/4.3"


while [[ $# -gt 0 ]] && [[ "$1" == "--"* ]]; do
    optimize='n'

    opt="$1";
    shift;
    case "$opt" in
        --ffmpeg-only=* )
           compile_ffmpeg_only="${opt#*=}";;
        --libs-only=* )
           compile_libs_only="${opt#*=}";;
        --extras=* )
           compile_extras="${opt#*=}";;
        --optimize=* )
           optimize="${opt#*=}";;
        --help )
           showHelp=true;;
        *);;
   esac
done

if [[ $showHelp ]]; then
    echo "-------------------------------------------------------------"
    echo "compile with:"
    echo
    echo '--libs-only=[y/n]      # compile only libs'
    echo '--ffmpeg-only=[y/n]    # compile only ffmpeg'
    echo '--extras=[y/n]         # compile mediainfo and MP4Box'
    echo '--optimize=[y/n]       # compile system optimized version'
    echo '--help                 # show this help'

    exit 0
fi

arch=$(uname -m)
system=$(uname -s)

if [[ $arch == "arm64" ]]; then
    export CXX=$(which clang++)
fi

if [[ "$optimize" == "y" ]] || [[ "$arch" != "x86_64" ]]; then
    tune="native"
    onum=3
    cpuDetect=""
    vpxFlags=""
else
    tune="generic"
    onum=2
    cpuDetect="--enable-runtime-cpudetect"
    vpxFlags="--enable-postproc --enable-vp9-postproc --enable-runtime-cpu-detect"
fi

config="build_config.txt"

if [[ ! -f "$config" ]]; then
cat <<EOF > "$config"
#--enable-decklink
#--enable-libklvanc
#--disable-ffplay
#--disable-sdl2
#--enable-libfontconfig
#--enable-libaom
#--enable-libass
#--enable-libbluray
#--enable-libfdk-aac
#--enable-libfribidi
#--enable-libfreetype
#--enable-libharfbuzz
#--enable-libmp3lame
#--enable-libopus
#--enable-libsoxr
#--enable-libsrt
#--enable-librist
#--enable-libtwolame
#--enable-libvpx
#--enable-libx264
#--enable-libx265
#--enable-libzimg
#--enable-libzmq
#--enable-nonfree
#--enable-opencl
#--enable-opengl
#--enable-libopenjpeg
#--enable-openssl
#--enable-libsvtav1
#--enable-librav1e
#--enable-libdav1d
#--enable-cuda-nvcc
#--enable-cuvid
#--enable-nvenc
#--enable-nvdec
#--enable-libnpp
#--enable-libndi_newtek
#--enable-libpulse
#--enable-vulkan
#--enable-libplacebo
#--enable-libshaderc
#--enable-libvmaf
EOF
    echo "-------------------------------------------------------------------------------"
    echo "-------------------------------------------------------------------------------"
    echo ""
    echo " edit \"$config\" and activate all libs that you need"
    echo ""
    echo "-------------------------------------------------------------------------------"
    echo "-------------------------------------------------------------------------------"
    while true; do
        read -r -p "run (y/n):$ " run

        if [[ "$run" == 'y' ]]; then
            break
        elif [[ "$run" == 'n' ]]; then
            exit
        else
            echo ""
            echo "Please type 'y' or 'n'"
            echo "------------------------------------"
            echo ""
        fi
    done
fi

# --------------------------------------------------

# check system
if [[ "$system" == "Darwin" ]]; then
    osExtra="-mmacosx-version-min=11"
    osString="osx"
    cpuCount=$( sysctl hw.ncpu | awk '{ print $2 - 1 }' )
    compNasm="no"
    osLib="-liconv"
    osFlag=""
    arch="--arch=$arch"
    fpic=""
    sd="gsed"

    if [[ "$arch" == "x86_64" ]]; then
        extraLibs="-lintl"
    else
        extraLibs=""
    fi

else
    osExtra="-static-libstdc++ -static-libgcc"
    osString="nix"
    cpuCount=$( nproc | awk '{ print $1 - 1 }' )
    compNasm="yes"
    osLib=""
    osFlag="--enable-pic"
    arch=""
    fpic="-fPIC"
    sd="sed"
    extraLibs="-lpthread"
fi

get_options() {
    $sd -r '# remove commented text
        s/#.*//
        # delete empty lines
        /^\s*$/d
        # remove leading whitespace
        s/^\s+//
        # remove trailing whitespace
        s/\s+$//
        ' "$config" | tr -d '\r'
}

IFS=$'\n' read -d '' -r -a FFMPEG_LIBS < <(get_options)

compile="false"
buildFFmpeg="false"

EXTRA_CFLAGS="-march=$tune"
LOCALBUILDDIR="$PWD/build"
LOCALDESTDIR="$PWD/local"
export LOCALBUILDDIR LOCALDESTDIR

PKG_CONFIG_PATH="${LOCALDESTDIR}/lib/pkgconfig"
PKG_CONFIG_ALL_STATIC=1
PKG_CONFIG_PREFER_STATIC=1

CPPFLAGS="-I${LOCALDESTDIR}/include $fpic $osExtra"
CFLAGS="-I${LOCALDESTDIR}/include -mtune=$tune -O$onum $osExtra $fpic"
CXXFLAGS="${CFLAGS}"
LDFLAGS="-L${LOCALDESTDIR}/lib -pipe $osExtra"

export PKG_CONFIG_PATH PKG_CONFIG_ALL_STATIC PKG_CONFIG_PREFER_STATIC \
    CPPFLAGS CFLAGS CXXFLAGS LDFLAGS

[ -d "$LOCALBUILDDIR" ] || mkdir "$LOCALBUILDDIR"
[ -d "$LOCALDESTDIR" ] || mkdir "$LOCALDESTDIR"

do_prompt() {
    # from http://superuser.com/a/608509
    while read -r -s -e -t 0.1; do : ; done
    read -r -p "$1"
}

# get git clone, or update
do_git() {
    local gitURL="$1"
    local gitFolder="$2"
    local gitDepth="$3"
    local gitBranch="$4"
    local commit="$5"
    echo -ne "\033]0;compile $gitFolder\007"
    if [ ! -d "$gitFolder" ]; then
        if [[ $gitDepth == "noDepth" ]]; then
            git clone "$gitURL" "$gitFolder"
        elif [[ $gitBranch != "" ]]; then
            git clone --depth 1 --single-branch -b $gitBranch "$gitURL" "$gitFolder"
        else
            git clone --depth 1 "$gitURL" "$gitFolder"
        fi

        compile="true"
        cd "$gitFolder" || exit

        if [[ -n $commit ]]; then
            git checkout $commit
        fi
    else
        cd "$gitFolder" || exit
        oldHead=$(git rev-parse HEAD)
        git reset --hard "@{u}"

        if [[ -n $commit ]]; then
            git checkout $commit
        else
            git pull origin master
        fi

        newHead=$(git rev-parse HEAD)

        if [[ "$oldHead" != "$newHead" ]]; then
            compile="true"
        fi
    fi
}

# get svn checkout, or update
do_svn() {
    local svnURL="$1"
    local svnFolder="$2"
    echo -ne "\033]0;compile $svnFolder\007"
    if [ ! -d "$svnFolder" ]; then
        svn checkout "$svnURL" "$svnFolder"
        compile="true"
        cd "$svnFolder" || exit
    else
        cd "$svnFolder" || exit
        oldRevision=$(svnversion)
        svn update
        newRevision=$(svnversion)

        if [[ "$oldRevision" != "$newRevision" ]]; then
            compile="true"
        fi
    fi
}

# get curl download
do_curl() {
    local url="$1"
    local archive="$2"
    local dirName="$3"
    if [[ -z $archive ]]; then
        # remove arguments and filepath
        archive=${url%%\?*}
        archive=${archive##*/}
    fi

    if [[ -f "$archive" ]]; then
        local response_code=200
    else
        local -r response_code=$(curl --retry 20 --retry-max-time 5 -L -k -f -w "%{response_code}" -o "$archive" "$url")
    fi

    if [[ $response_code = "200" || $response_code = "226" ]]; then
        case "$archive" in
            *.tar.gz)
                dirName=$( expr "$archive" : '\(.*\)\.\(tar.gz\)$' )
                rm -rf "$dirName"
                tar -xf "$archive"
                #rm "$archive"
                cd "$dirName" || exit
            ;;
            *.tar.bz2)
                dirName=$( expr "$archive" : '\(.*\)\.\(tar.bz2\)$' )
                rm -rf "$dirName"
                tar -xf "$archive"
                rm "$archive"
                cd "$dirName" || exit
            ;;
            *.tar.xz)
                if [[ -z $dirName ]]; then
                    dirName=$( expr "$archive" : '\(.*\)\.\(tar.xz\)$' )
                fi
                #rm -rf $dirName
                tar -xf "$archive"
                #  rm "$archive"
                cd "$dirName" || exit
            ;;
            *.zip)
                unzip "$archive"
                rm "$archive"
            ;;
            *.7z)
                dirName=$(expr "$archive" : '\(.*\)\.\(7z\)$' )
                7z x -o"$dirName" "$archive"
                rm "$archive"
            ;;
        esac
    elif [[ $response_code -gt 400 ]]; then
        echo "Error $response_code while downloading $URL"
        echo "Try again later or <Enter> to continue"
        do_prompt "if you're sure nothing depends on it."
    fi
}

# check if compiled file exist
do_checkIfExist() {
    local packetName="$1"
    local fileName="$2"
    local fileExtension=${fileName##*.}
    if [[ "$fileExtension" != "a" ]]; then
        if [ -f "$LOCALDESTDIR/$fileName" ]; then
            echo -
            echo -------------------------------------------------
            echo "build $packetName done..."
            echo -------------------------------------------------
            echo -
            compile="false"
        else
            echo -------------------------------------------------
            echo "Build $packetName failed..."
            echo "Delete the source folder under '$LOCALBUILDDIR' and start again,"
            echo "or if you know there is no dependencies hit enter for continue it."
            read -r -p ""
            sleep 5
        fi
    else
        if [ -f "$LOCALDESTDIR/lib/$fileName" ]; then
            echo -
            echo -------------------------------------------------
            echo "build $packetName done..."
            echo -------------------------------------------------
            echo -
            compile="false"
        else
            echo -------------------------------------------------
            echo "build $packetName failed..."
            echo "delete the source folder under '$LOCALBUILDDIR' and start again,"
            echo "or if you know there is no dependencies hit enter for continue it"
            read -r -p ""
            sleep 5
        fi
    fi
}

buildLibs() {
    cd "$LOCALBUILDDIR" || exit

    if [[ "$system" == "Darwin" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libuuid.a" ]; then
            echo -------------------------------------------------
            echo "uuid-1.6.2 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile uuid 64Bit\007"

            do_curl "https://www.mirrorservice.org/sites/ftp.ossp.org/pkg/lib/uuid/uuid-1.6.2.tar.gz"

            ./configure --prefix="$LOCALDESTDIR" --disable-shared

            make -j "$cpuCount"
            make install

            do_checkIfExist uuid-1.6.2 libuuid.a
        fi
    else
        if [ -f "$LOCALDESTDIR/lib/libuuid.a" ]; then
            echo -------------------------------------------------
            echo "libuuid is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile uuid 64Bit\007"

            do_git https://github.com/gershnik/libuuid-cmake.git libuuid-cmake-git

            cmake -S . -B build -DLIBUUID_SHARED=OFF -DLIBUUID_STATIC=ON -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" -DCMAKE_INSTALL_DATAROOTDIR=$LOCALDESTDIR/lib -DCMAKE_INSTALL_LIBDIR="lib" -DCMAKE_STATIC_LIBRARY_SUFFIX=".a" -DCMAKE_IMPORT_LIBRARY_SUFFIX=".lib"
            cmake --build build
            cmake --install build

            do_checkIfExist libuuid libuuid.a
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [ -f "$LOCALDESTDIR/lib/libz.a" ]; then
        echo -------------------------------------------------
        echo "zlib-1.3.1 is already compiled"
        echo -------------------------------------------------
    else
        echo -ne "\033]0;compile libz 64Bit\007"

        do_curl "https://zlib.net/zlib-1.3.1.tar.gz"

        ./configure --prefix="$LOCALDESTDIR" --static

        make -j "$cpuCount"
        make install

        do_checkIfExist zlib-1.3.1 libz.a
    fi

    cd "$LOCALBUILDDIR" || exit

    if [ -f "$LOCALDESTDIR/lib/libiconv.a" ]; then
        echo -------------------------------------------------
        echo "libiconv-1.18 is already compiled"
        echo -------------------------------------------------
    else
        echo -ne "\033]0;compile libiconv 64Bit\007"

        do_curl "https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.18.tar.gz"

        ./configure --prefix="$LOCALDESTDIR" --disable-shared

        make -j "$cpuCount"
        make install

        do_checkIfExist libiconv-1.18 libiconv.a
    fi

    cd "$LOCALBUILDDIR" || exit

    if [ -f "$LOCALDESTDIR/lib/libbz2.a" ]; then
        echo -------------------------------------------------
        echo "bzip2-1.0.8 is already compiled"
        echo -------------------------------------------------
    else
        echo -ne "\033]0;compile bzip2 64Bit\007"

        do_curl "https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz"

        if [[ "$system" == "Darwin" ]]; then
            $sd -ri "s/^CFLAGS=-Wall/^CFLAGS=-Wall $osExtra/g" Makefile
        fi

        make install PREFIX="$LOCALDESTDIR"

        cat <<EOF > $LOCALDESTDIR/lib/pkgconfig/bzip2.pc
prefix=$LOCALDESTDIR
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: bzip2
Description: High-quality block-sorting file compressor library (static)
Version: 1.0.8
Libs: \${libdir}/libbz2.a
Libs.private: -lm
Cflags: -I\${includedir}
EOF

        do_checkIfExist bzip2-1.0.8 libbz2.a
    fi

    cd "$LOCALBUILDDIR" || exit

    if [ -f "$LOCALDESTDIR/lib/liblzma.a" ]; then
        echo -------------------------------------------------
        echo "xz-5.4.3 is already compiled"
        echo -------------------------------------------------
    else
        echo -ne "\033]0;compile xz 64Bit\007"

        do_curl "https://downloads.sourceforge.net/project/lzmautils/xz-5.4.3.tar.gz"

        ./configure --prefix="$LOCALDESTDIR" --disable-shared

        make -j "$cpuCount"
        make install

        do_checkIfExist xz-5.4.3 liblzma.a
    fi

    cd "$LOCALBUILDDIR" || exit

    if [ -f "$LOCALDESTDIR/lib/libpng.a" ]; then
        echo -------------------------------------------------
        echo "libpng-1.6.48 is already compiled"
        echo -------------------------------------------------
    else
        echo -ne "\033]0;compile libpng 64Bit\007"

        do_curl "http://prdownloads.sourceforge.net/libpng/libpng-1.6.48.tar.gz"

        ./configure --prefix="$LOCALDESTDIR" --disable-shared

        make -j "$cpuCount"
        make install

        do_checkIfExist libpng-1.6.48 libpng.a
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libfribidi" ]] || [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libass" ]]; then
        do_git "https://github.com/fribidi/fribidi.git" fribidi-git

        if [[ $compile == "true" ]]; then
            rm -rf build
            mkdir build
            cd build

            meson setup -Ddocs=false -Dbin=false -Dtests=false --default-library=static .. --prefix "$LOCALDESTDIR" --libdir="$LOCALDESTDIR/lib"
            ninja
            ninja install

            if [[ ! -f "$LOCALDESTDIR/lib/pkgconfig/fribidi.pc" ]]; then
                cp fribidi.pc "$LOCALDESTDIR/lib/pkgconfig/"
            fi

            do_checkIfExist fribidi-git libfribidi.a

        else
            echo -------------------------------------------------
            echo "fribidi is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libfreetype" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libexpat.a" ]; then
            echo -------------------------------------------------
            echo "expat2.7.1 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile expat 64Bit\007"

            do_curl "https://github.com/libexpat/libexpat/releases/download/R_2_7_1/expat-2.7.1.tar.bz2"

            ./configure --prefix="$LOCALDESTDIR" --enable-shared=no --without-docbook

            make -j "$cpuCount"
            make install

            do_checkIfExist expat-2.7.1 libexpat.a
        fi

        cd "$LOCALBUILDDIR" || exit

        if [ -f "$LOCALDESTDIR/lib/libbrotlienc.a" ]; then
            echo -------------------------------------------------
            echo " brotli-1.1.0 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile  brotli\007"

            do_curl "https://github.com/google/brotli/archive/refs/tags/v1.1.0.tar.gz" brotli-1.1.0.tar.gz

            mkdir build
            cd build

            cmake .. -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_BINDIR="bin" -DCMAKE_INSTALL_LIBDIR="lib" -DCMAKE_INSTALL_INCLUDEDIR="include"

            make -j "$cpuCount"
            make install

            do_checkIfExist brotli-1.1.0 libbrotlienc.a
        fi

        cd "$LOCALBUILDDIR" || exit

        if [ -f "$LOCALDESTDIR/lib/libfreetype.a" ]; then
            echo -------------------------------------------------
            echo "freetype-2.13.3 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile freetype\007"

            do_curl "https://sourceforge.net/projects/freetype/files/freetype2/2.13.3/freetype-2.13.3.tar.gz"

            ./configure --prefix="$LOCALDESTDIR" --disable-shared --with-harfbuzz=no
            make -j "$cpuCount"
            make install

            do_checkIfExist freetype-2.13.3 libfreetype.a

            $sd -ri "s/(Libs\:.*)/\1 -lpng16 -lbz2 -lz/g" "$LOCALDESTDIR/lib/pkgconfig/freetype2.pc"
        fi
    fi

    cd "$LOCALBUILDDIR" || exit
    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libfontconfig" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libfontconfig.a" ]; then
            echo -------------------------------------------------
            echo "fontconfig-2.16.0 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile fontconfig\007"

            do_curl "https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.16.0.tar.xz"

            ./configure --prefix="$LOCALDESTDIR" --enable-shared=no

            make -j "$cpuCount"
            make install

            do_checkIfExist fontconfig-2.16.0 libfontconfig.a

            # on linux fontconfig.pc is not copyed
            [[ ! -f "$LOCALDESTDIR/lib/pkgconfig/fontconfig.pc" ]] && cp fontconfig.pc "$LOCALDESTDIR/lib/pkgconfig/"

            $sd -ri "s/(Libs\:.*)/\1 -lpng16 -lbz2 -lxml2 -lz -lstdc++ $osLib -llzma -lm -lexpat -luuid/g" "$LOCALDESTDIR/lib/pkgconfig/fontconfig.pc"
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libharfbuzz" ]]; then
        do_git "https://github.com/harfbuzz/harfbuzz.git" harfbuzz-git

        if [[ $compile == "true" ]]; then
            mkdir build
            cd build

            meson setup --default-library=static --prefix "$LOCALDESTDIR" --libdir="$LOCALDESTDIR/lib" ..

            ninja
            ninja install

            do_checkIfExist harfbuzz-git libharfbuzz.a

            $sd -ri "s/(Libs\:.*)/\1 -lstdc++/g" "$LOCALDESTDIR/lib/pkgconfig/harfbuzz.pc"
        else
            echo -------------------------------------------------
            echo "harfbuzz is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [ -f "$LOCALDESTDIR/lib/libxml2.a" ]; then
        echo -------------------------------------------------
        echo "libxml2-2.14.3 is already compiled"
        echo -------------------------------------------------
    else
        echo -ne "\033]0;compile libxml2\007"

        do_curl "https://github.com/GNOME/libxml2/archive/refs/tags/v2.14.3.tar.gz" "libxml2-2.14.3.tar.gz"

        if [[ ! -f ./configure ]]; then
                ./autogen.sh
            else
                make uninstall
                make clean
            fi

        ./configure --prefix="$LOCALDESTDIR" --disable-shared --enable-static --with-iconv=no --with-python=no

        make -j "$cpuCount"
        make install

        do_checkIfExist libxml2-2.14.3 libxml2.a
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libzimg" ]]; then
        do_git "https://github.com/sekrit-twc/zimg.git" zimg-git

        if [[ $compile == "true" ]]; then
            if [[ ! -f ./configure ]]; then
                ./autogen.sh
            else
                make uninstall
                make clean
            fi

            git submodule update --init --recursive
            ./configure --prefix="$LOCALDESTDIR" --enable-shared=no

            make -j "$cpuCount"
            make install

            do_checkIfExist zimg-git libzimg.a

            $sd -ri "s/(Libs\:.*)/\1 -lstdc++/g" "$LOCALDESTDIR/lib/pkgconfig/zimg.pc"
        else
            echo -------------------------------------------------
            echo "zimg is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libzmq" ]]; then
        EXTRA_CFLAGS="$EXTRA_CFLAGS -DZMG_STATIC"

        do_git "https://github.com/zeromq/libzmq.git" libzmq-git

        if [[ $compile == "true" ]]; then
            if [[ ! -f ./configure ]]; then
                ./autogen.sh
            else
                make uninstall
                make clean
            fi

            ./configure --prefix="$LOCALDESTDIR" --enable-static --disable-shared

            make -j "$cpuCount"
            make install

            do_checkIfExist libzmq-git libzmq.a

        else
            echo -------------------------------------------------
            echo "libzmq is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libopenjpeg" ]]; then

        do_git "https://github.com/uclouvain/openjpeg.git" libopenjpeg-git

        if [[ $compile == "true" ]]; then
            mkdir build
            cd build

            cmake .. -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_BINDIR="bin" -DCMAKE_INSTALL_LIBDIR="lib" -DCMAKE_INSTALL_INCLUDEDIR="include"

            make -j "$cpuCount"
            make install

            do_checkIfExist libopenjpeg-git libopenjp2.a

        else
            echo -------------------------------------------------
            echo "libopenjpeg is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-openssl" ]] || [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libsrt" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libssl.a" ]; then
            echo -------------------------------------------------
            echo "openssl-3.5.0 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile openssl 64Bit\007"

            if [[ "$system" == "Darwin" ]]; then
                target="darwin64-x86_64-cc"
            else
                target="linux-x86_64"
            fi

            do_curl "https://github.com/openssl/openssl/releases/download/openssl-3.5.0/openssl-3.5.0.tar.gz"

            ./Configure --prefix=$LOCALDESTDIR --openssldir=$LOCALDESTDIR $target --libdir="$LOCALDESTDIR/lib" no-shared no-docs zlib -static -mtune=$tune $osExtra

            make depend all
            make install_sw

            do_checkIfExist openssl-3.5.0 libssl.a
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libsrt" ]]; then
        do_git "https://github.com/Haivision/srt.git" srt-git

        if [[ $compile == "true" ]]; then
            mkdir build
            cd build || exit

            cmake .. -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" -DENABLE_SHARED:BOOLEAN=OFF -DUSE_STATIC_LIBSTDCXX:BOOLEAN=ON -DENABLE_CXX11:BOOLEAN=OFF -DCMAKE_INSTALL_BINDIR="bin" -DCMAKE_INSTALL_LIBDIR="lib" -DCMAKE_INSTALL_INCLUDEDIR="include"

            make -j "$cpuCount"
            make install

            do_checkIfExist srt-git libsrt.a

            if [[ "$system" == "Darwin" ]]; then
                extra=""
            else
                extra="-lpthread -ldl"
            fi

            $sd -ri "s/(Libs\:.*)/\1 -lstdc++ -lcrypto -lz $extra/g" "$LOCALDESTDIR/lib/pkgconfig/srt.pc"
        else
            echo -------------------------------------------------
            echo "srt is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-librist" ]]; then
        do_git "https://code.videolan.org/rist/librist.git" librist-git

        if [[ $compile == "true" ]]; then
            mkdir build
            cd build || exit

            meson setup --default-library=static --prefix "$LOCALDESTDIR" --libdir="$LOCALDESTDIR/lib" ..

            ninja
            ninja install

            do_checkIfExist librist-git librist.a
        else
            echo -------------------------------------------------
            echo "librist is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libvmaf" ]]; then
        do_git "https://github.com/Netflix/vmaf.git" vmaf-git

        if [[ $compile == "true" ]]; then
            cd libvmaf
            mkdir build
            cd build || exit

            meson setup --default-library=static -Denable_avx512=true -Dbuilt_in_models=true --buildtype release --prefix "$LOCALDESTDIR" --libdir="$LOCALDESTDIR/lib" ..

            ninja
            ninja install

            $sd -ri "s/(Libs\:.*)/\1 -lstdc++/g" "$LOCALDESTDIR/lib/pkgconfig/libvmaf.pc"

            do_checkIfExist vmaf-git libvmaf.a
        else
            echo -------------------------------------------------
            echo "vmaf is already up to date"
            echo -------------------------------------------------
        fi
    fi

    echo "-------------------------------------------------------------------------------"
    echo
    echo "compile global tools and libs done..."
    echo
    echo "-------------------------------------------------------------------------------"

    cd "$LOCALBUILDDIR" || exit
    echo "-------------------------------------------------------------------------------"
    echo
    echo "compile audio libs"
    echo
    echo "-------------------------------------------------------------------------------"

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libmp3lame" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libmp3lame.a" ]; then
            echo -------------------------------------------------
            echo "lame-3.100 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile lame\007"

            do_curl "https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz" lame-3.100.tar.gz

            ./configure --prefix="$LOCALDESTDIR" --enable-expopt=full --enable-shared=no

            make -j "$cpuCount"
            make install

            do_checkIfExist lame-3.100 libmp3lame.a
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libtwolame" ]]; then
        EXTRA_CFLAGS="$EXTRA_CFLAGS -DLIBTWOLAME_STATIC"
        if [ -f "$LOCALDESTDIR/lib/libtwolame.a" ]; then
            echo -------------------------------------------------
            echo "twolame-0.4.0 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile twolame 64Bit\007"

            do_curl "https://sourceforge.net/projects/twolame/files/twolame/0.4.0/twolame-0.4.0.tar.gz/download" twolame-0.4.0.tar.gz

            ./configure --prefix="$LOCALDESTDIR" --disable-shared CPPFLAGS="$CPPFLAGS -DLIBTWOLAME_STATIC"

            make -j "$cpuCount"
            make install

            do_checkIfExist twolame-0.4.0 libtwolame.a
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libfdk-aac" ]]; then
        do_git "https://github.com/mstorsjo/fdk-aac" fdk-aac-git

        if [[ $compile == "true" ]]; then
            if [[ ! -f ./configure ]]; then
                ./autogen.sh
            else
                make uninstall
                make clean
            fi

            ./configure --prefix="$LOCALDESTDIR" --enable-shared=no

            make -j "$cpuCount"
            make install

            do_checkIfExist fdk-aac-git libfdk-aac.a
        else
            echo -------------------------------------------------
            echo "fdk-aac is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libsoxr" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libsoxr.a" ]; then
            echo -------------------------------------------------
            echo "soxr-0.1.3 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile soxr-0.1.1\007"

            do_curl "https://downloads.sourceforge.net/project/soxr/soxr-0.1.3-Source.tar.xz"

            mkdir build
            cd build || exit



            cmake .. -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" -DHAVE_WORDS_BIGENDIAN_EXITCODE=0 -DBUILD_SHARED_LIBS:bool=off -DBUILD_TESTS:BOOL=OFF -DWITH_OPENMP:BOOL=OFF -DUNIX:BOOL=on -Wno-dev

            make -j "$cpuCount"
            make install

            do_checkIfExist soxr-0.1.3-Source libsoxr.a
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libopus" ]]; then
        if [ -f "$LOCALDESTDIR/lib/libopus.a" ]; then
            echo -------------------------------------------------
            echo "opus-1.5.2 is already compiled"
            echo -------------------------------------------------
        else
            echo -ne "\033]0;compile opus\007"

            do_curl "https://github.com/xiph/opus/releases/download/v1.5.2/opus-1.5.2.tar.gz"

            ./configure --prefix="$LOCALDESTDIR" --enable-shared=no --enable-static --disable-doc

            make -j "$cpuCount"
            make install

            do_checkIfExist opus-1.5.2 libopus.a
        fi
    fi

    echo "-------------------------------------------------------------------------------"
    echo
    echo "compile audio libs done..."
    echo
    echo "-------------------------------------------------------------------------------"

    cd "$LOCALBUILDDIR" || exit
    sleep 3
    echo "-------------------------------------------------------------------------------"
    echo
    echo "compile video libs"
    echo
    echo "-------------------------------------------------------------------------------"

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libsvtav1" ]]; then
        do_git "https://gitlab.com/AOMediaCodec/SVT-AV1.git" libsvtav1-git "noDepth"

        if [[ $compile == "true" ]]; then
            cd Build

            rm -rf *

            cmake .. -G"Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_BINDIR="bin" -DCMAKE_INSTALL_LIBDIR="lib" -DCMAKE_INSTALL_INCLUDEDIR="include"

            make -j "$cpuCount"
            make install

            do_checkIfExist libsvtav1-git libSvtAv1Enc.a

            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "libsvtav1-git is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libdav1d" ]]; then
        do_git "https://code.videolan.org/videolan/dav1d.git" libdav1d-git

        if [[ $compile == "true" ]]; then
            rm -rf build
            mkdir build
            cd build

            meson setup -Denable_tools=false -Denable_tests=false --default-library=static .. --prefix "$LOCALDESTDIR" --libdir="$LOCALDESTDIR/lib"
            ninja
            ninja install

            do_checkIfExist libdav1d-git libdav1d.a

            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "libdav1d-git is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libaom" ]]; then
        do_git "https://aomedia.googlesource.com/aom" libaom-git

        if [[ $compile == "true" ]]; then
            if [ -d "aom_build" ]; then
                cd aom_build
                make uninstall

                rm -rf *
            else
                mkdir aom_build
                cd aom_build
            fi

            cmake -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" -DBUILD_SHARED_LIBS=0 -DENABLE_NASM=on -DAOM_EXTRA_C_FLAGS="-mtune=$tune $osExtra" -DAOM_EXTRA_CXX_FLAGS="-mtune=$tune $osExtra" ../

            make -j "$cpuCount"
            make install

            cp -R $LOCALDESTDIR/lib64/* $LOCALDESTDIR/lib/

            do_checkIfExist libaom-git libaom.a

            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "libvaom is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libvpx" ]]; then
        do_git "https://github.com/webmproject/libvpx.git" libvpx-git noDepth

        if [[ $compile == "true" ]]; then
            if [ -d "$LOCALDESTDIR/include/vpx" ]; then
                rm -rf "$LOCALDESTDIR/include/vpx"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/vpx.pc"
                rm -f "$LOCALDESTDIR/lib/libvpx.a"
                make clean
            fi

            ./configure --prefix="$LOCALDESTDIR" --disable-shared --enable-static --disable-unit-tests --disable-docs $vpxFlags $osFlag

            make -j "$cpuCount"
            make install

            do_checkIfExist libvpx-git libvpx.a

            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "libvpx-git is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libbluray" ]]; then
        do_git "https://code.videolan.org/videolan/libbluray" libbluray-git

        if [[ $compile == "true" ]]; then

            if [[ ! -f "configure" ]]; then
                git submodule update --init
                autoreconf -fiv
            else
                make uninstall
                make clean
            fi

            ./configure --prefix="$LOCALDESTDIR" --disable-shared --enable-static --disable-examples --disable-bdjava-jar --disable-doxygen-doc --disable-doxygen-dot --without-fontconfig --without-freetype LIBXML2_LIBS="-L$LOCALDESTDIR/lib -lxml2" LIBXML2_CFLAGS="-I$LOCALDESTDIR/include/libxml2 -DLIBXML_STATIC"

            make -j "$cpuCount"
            make install

            do_checkIfExist libbluray-git libbluray.a

            $sd -ri "s/(Libs\:.*)/\1 -lxml2 -lstdc++ -lz $osLib -llzma -lm -ldl/g" "$LOCALDESTDIR/lib/pkgconfig/libbluray.pc"
        else
            echo -------------------------------------------------
            echo "libbluray-git is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libass" ]]; then
        do_git "https://github.com/libass/libass.git" libass-git

        if [[ $compile == "true" ]]; then
            if [ -f "$LOCALDESTDIR/lib/libass.a" ]; then
                make uninstall
                make clean
            fi

            if [[ ! -f "configure" ]]; then
                ./autogen.sh
            fi

            ./configure --prefix="$LOCALDESTDIR" --enable-shared=no --disable-harfbuzz FRIBIDI_LIBS="-L$LOCALDESTDIR/lib" FRIBIDI_CFLAGS="-I$LOCALDESTDIR/include/fribidi"

            make -j "$cpuCount"
            make install

            $sd -i 's/-lass -lm/-lass -lfribidi -lm/' "$LOCALDESTDIR/lib/pkgconfig/libass.pc"

            do_checkIfExist libass-git libass.a
            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "libass is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-decklink" ]]; then
        if [ -f "$LOCALDESTDIR/include/DeckLinkAPI.h" ]; then
            echo -------------------------------------------------
            echo "DeckLinkAPI is already in place"
            echo -------------------------------------------------
        else
            cd "$LOCALDESTDIR/include" || exit

            cp ../../headers/decklink-${osString}/* .

            if [[ $osString == "osx" ]]; then
                $sd -i '' "s/void    InitDeckLinkAPI (void)/static void    InitDeckLinkAPI (void)/" DeckLinkAPIDispatch.cpp
                $sd -i '' "s/bool        IsDeckLinkAPIPresent (void)/static bool        IsDeckLinkAPIPresent (void)/" DeckLinkAPIDispatch.cpp
                $sd -i '' "s/void InitBMDStreamingAPI(void)/static void InitBMDStreamingAPI(void)/" DeckLinkAPIDispatch.cpp
            fi
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libndi_newtek" ]]; then
        if [ -f "$LOCALDESTDIR/include/Processing.NDI.Lib.h" ]; then
            echo -------------------------------------------------
            echo "NDI headers are already in place"
            echo -------------------------------------------------
        else

            cd "$LOCALDESTDIR/include" || exit

            cp ../../headers/ndi-${osString}/* .
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libklvanc" ]]; then
        do_git "https://github.com/stoth68000/libklvanc.git" libklvanc-git noDepth

        if [[ $compile == "true" ]]; then
            if [ -f "$LOCALDESTDIR/lib/libklvanc.a" ]; then
                make distclean
            fi

            ./autogen.sh --build

            ./configure --prefix=$LOCALDESTDIR --enable-shared=no

            make -j "$cpuCount"
            make install

            do_checkIfExist libklvanc-git libklvanc.a

            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "libklvanc-git is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libx264" ]]; then
        do_git "https://code.videolan.org/videolan/x264" x264-git noDepth

        if [[ $compile == "true" ]]; then
            echo -ne "\033]0;compile x264-git\007"

            if [ -f "$LOCALDESTDIR/lib/libx264.a" ]; then
                rm -f "$LOCALDESTDIR/include/x264.h $LOCALDESTDIR/include/x264_config.h $LOCALDESTDIR/lib/libx264.a"
                rm -f "$LOCALDESTDIR/bin/x264 $LOCALDESTDIR/lib/pkgconfig/x264.pc"
            fi

            if [ -f "libx264.a" ]; then
                make distclean
            fi

            ./configure --prefix="$LOCALDESTDIR" --enable-static $osFlag

            make -j "$cpuCount"
            make install

            do_checkIfExist x264-git libx264.a
            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "x264 is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libx265" ]]; then
        do_git "https://bitbucket.org/multicoreware/x265_git.git" x265-git noDepth

        if [[ $compile == "true" ]]; then
            cd build || exit
            rm -rf ./*
            rm -f "$LOCALDESTDIR/bin/x265"
            rm -f "$LOCALDESTDIR/include/x265.h"
            rm -f "$LOCALDESTDIR/include/x265_config.h"
            rm -f "$LOCALDESTDIR/lib/libx265.a"
            rm -f "$LOCALDESTDIR/lib/pkgconfig/x265.pc"

            cmake ../source -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" -DENABLE_SHARED:BOOLEAN=OFF -DCMAKE_CXX_FLAGS_RELEASE:STRING="-O3 -DNDEBUG $CXXFLAGS"

            make -j "$cpuCount"
            make install

            do_checkIfExist x265-git libx265.a

            if [[ "$system" == "Darwin" ]]; then
                extra="-lc++"
            else
                extra="-lstdc++ -lpthread -ldl"
            fi

            $sd -ri "s/(Libs\:.*)/\1 $extra/g" "$LOCALDESTDIR/lib/pkgconfig/x265.pc"

            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "x265 is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-librav1e" ]]; then
        do_git "https://github.com/xiph/rav1e.git" rav1e-git noDepth

        if [[ $compile == "true" ]]; then
            export RUSTFLAGS="-C target-cpu=native"
            target=""

            if [[ $system == "Linux" ]]; then
                target="--target=x86_64-unknown-linux-musl"
            fi

            cargo cinstall --release $target --jobs "$cpuCount" --prefix=$LOCALDESTDIR --libdir=$LOCALDESTDIR/lib --includedir=$LOCALDESTDIR/include --library-type=staticlib --crt-static

            do_checkIfExist rav1e-git librav1e.a

            buildFFmpeg="true"
        else
            echo -------------------------------------------------
            echo "rav1e-git is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-nvenc" ]]; then
        do_git "https://git.videolan.org/git/ffmpeg/nv-codec-headers" nv-codec-headers-git

        if [[ $compile == "true" ]]; then
            make -j "$cpuCount"
            make install  PREFIX="$LOCALDESTDIR"
        else
            echo -------------------------------------------------
            echo "nv-codec-headers-git is already up to date"
            echo -------------------------------------------------
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-vulkan" ]] || [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libplacebo" ]]; then
        if [[ ! -f $LOCALDESTDIR/share/vulkan/registry/vk.xml ]]; then
            do_curl https://sdk.lunarg.com/sdk/download/1.4.321.0/linux/vulkansdk-linux-x86_64-1.4.321.0.tar.xz vvulkansdk-linux-x86_64-1.4.321.0.tar.xz "1.4.321.0"
            rsync --remove-source-files -auv x86_64/ $LOCALDESTDIR/
        fi
    fi

    cd "$LOCALBUILDDIR" || exit

    if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libplacebo" ]]; then
        do_git "https://code.videolan.org/videolan/libplacebo" libplacebo-git
        git submodule update --init

        if [[ $compile == "true" ]]; then
            rm -rf build
            mkdir build
            cd build

            meson setup -Dvulkan-registry=$LOCALDESTDIR/share/vulkan/registry/vk.xml --default-library=static --prefix "$LOCALDESTDIR" --libdir="$LOCALDESTDIR/lib" ..

            ninja
            ninja install

            do_checkIfExist libplacebo-git libplacebo.a
        else
            echo -------------------------------------------------
            echo "nv-codec-headers-git is already up to date"
            echo -------------------------------------------------
        fi
    fi
}

buildFfmpeg() {
    cd "$LOCALBUILDDIR" || exit
    echo "-------------------------------------------------------------------------------"
    echo "compile ffmpeg"
    echo "-------------------------------------------------------------------------------"

    do_git "https://github.com/FFmpeg/FFmpeg.git" ffmpeg-git "" $ffmpeg_branch

    if [[ $compile == "true" ]] || [[ $buildFFmpeg == "true" ]] || [[ ! -f "$LOCALDESTDIR/bin/ffmpeg" ]] && [[ ! -f "$LOCALDESTDIR/bin/ffmpeg_shared/bin/ffmpeg" ]]; then
        if [[ "$ffmpeg_shared" == "yes" ]]; then
            rm -rf "$LOCALDESTDIR/bin/ffmpeg_shared"
            static_share="--enable-shared"
            pkg_extra=""
            prefix_extra="$LOCALDESTDIR/bin/ffmpeg_shared"
            mkdir "$prefix_extra"
        else
            static_share="--disable-shared"
            pkg_extra="--pkg-config-flags=--static"
            prefix_extra="$LOCALDESTDIR"

            if [ -f "$LOCALDESTDIR/lib/libavcodec.a" ]; then
                rm -rf "$LOCALDESTDIR/include/libavutil"
                rm -rf "$LOCALDESTDIR/include/libavcodec"
                rm -rf "$LOCALDESTDIR/include/libpostproc"
                rm -rf "$LOCALDESTDIR/include/libswresample"
                rm -rf "$LOCALDESTDIR/include/libswscale"
                rm -rf "$LOCALDESTDIR/include/libavdevice"
                rm -rf "$LOCALDESTDIR/include/libavfilter"
                rm -rf "$LOCALDESTDIR/include/libavformat"
                rm -f "$LOCALDESTDIR/lib/libavutil.a"
                rm -f "$LOCALDESTDIR/lib/libswresample.a"
                rm -f "$LOCALDESTDIR/lib/libswscale.a"
                rm -f "$LOCALDESTDIR/lib/libavcodec.a"
                rm -f "$LOCALDESTDIR/lib/libavdevice.a"
                rm -f "$LOCALDESTDIR/lib/libavfilter.a"
                rm -f "$LOCALDESTDIR/lib/libavformat.a"
                rm -f "$LOCALDESTDIR/lib/libpostproc.a"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/libavcodec.pc"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/libavutil.pc"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/libpostproc.pc"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/libswresample.pc"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/libswscale.pc"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/libavdevice.pc"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/libavfilter.pc"
                rm -f "$LOCALDESTDIR/lib/pkgconfig/libavformat.pc"
            fi
        fi

        if [ -f "ffbuild/config.mak" ]; then
            # make uninstall
            make distclean
        fi

        if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libndi_newtek" ]]; then
            git apply ../../patches/revert-libndi_newtek.patch
            cp ../../patches/libndi/libavdevice/libndi_newtek_* libavdevice/
        fi

        EXTRA_CFLAGS=$(echo $EXTRA_CFLAGS | sed "s/-march=generic //")
        if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-libplacebo" ]]; then
            EXTRA_LD="-Wl,--copy-dt-needed-entries"
        fi

        if [[ " ${FFMPEG_LIBS[@]} " =~ "--enable-nvenc" ]]; then
            export PATH="/usr/local/cuda-12.0/bin:$PATH"
            export LD_LIBRARY_PATH="/usr/local/cuda-12.0/lib64:$LD_LIBRARY_PATH"
            EXTRA_CFLAGS="$EXTRA_CFLAGS -I/usr/local/cuda/include"
            EXTRA_LD="$EXTRA_LD -L/usr/local/cuda/lib64"
        fi

        ./configure $arch --prefix="$prefix_extra" --disable-debug "$static_share" $disable_ffplay \
        --disable-doc --enable-gpl --enable-version3 \
        $cpuDetect --enable-avfilter --enable-zlib "${FFMPEG_LIBS[@]}" \
        $osFlag --extra-libs="-lm -liconv $extraLibs" --extra-cflags="$EXTRA_CFLAGS" $pkg_extra --extra-ldflags="$EXTRA_LD"

        $sd -ri "s/--prefix=[^ ]* //g" config.h
        $sd -ri "s/ --extra-libs='.*'//g" config.h
        $sd -ri "s/ --pkg-config-flags=--static//g" config.h
        $sd -ri "s/ --extra-cflags=[a-zA-Z_'-]*//g" config.h
        $sd -ri "s/ --extra-ldflags=[a-zA-Z_'-,]*//g" config.h

        make -j "$cpuCount"
        make install

        if [[ -z "$ffmpeg_shared" ]]; then
            do_checkIfExist ffmpeg-git libavcodec.a
        else
            do_checkIfExist ffmpeg-git "bin/ffmpeg_shared/bin/ffmpeg"
        fi

        if [[ -n "$libzmq" ]]; then
            cd tools
            gcc -o $LOCALDESTDIR/bin/zmqsend zmqsend.c -I.. `pkg-config --libs --cflags libzmq libavutil` -DZMG_STATIC -lstdc++
        fi

        # when you copy the shared libs to /usr/local/lib
        # run "sudo ldconfig"

    else
        echo -------------------------------------------------
        echo "ffmpeg is already up to date"
        echo -------------------------------------------------
    fi
}

buildExtras() {
    #------------------------------------------------
    # build extra tools
    #------------------------------------------------

    cd "$LOCALBUILDDIR" || exit

    do_git "https://github.com/gpac/gpac.git" gpac-git noDepth
    if [[ $compile = "true"  ]] || [[ ! -f "$LOCALDESTDIR/bin/MP4Box" ]]; then
        if [ -d "$LOCALDESTDIR/include/gpac" ]; then
            rm -rf "$LOCALDESTDIR/bin/MP4Box $LOCALDESTDIR/lib/libgpac*"
            rm -rf "$LOCALDESTDIR/include/gpac"
        fi
        [[ -f config.mak ]] && make distclean
        ./configure --prefix="$LOCALDESTDIR" --static-bin --static-build --static-modules
        make -j "$cpuCount"
        make install
        do_checkIfExist gpac-git bin/MP4Box
    fi

    cd "$LOCALBUILDDIR" || exit

    do_git "https://github.com/MediaArea/ZenLib" libzen-git
    if [[ $compile = "true" ]] || [[ ! -f "$LOCALDESTDIR/bin/mediainfo" ]]; then
        cd Project/GNU/Library || exit
        [[ ! -f "configure" ]] && ./autogen.sh
        [[ -f libzen.pc ]] && make distclean

        if [[ -d "$LOCALDESTDIR/include/ZenLib" ]]; then
            rm -rf "$LOCALDESTDIR/include/ZenLib $LOCALDESTDIR/bin-global/libzen-config"
            rm -f "$LOCALDESTDIR/lib/libzen.{l,}a $LOCALDESTDIR/lib/pkgconfig/libzen.pc"
        fi
        ./configure --prefix="$LOCALDESTDIR" --disable-shared

        make -j "$cpuCount"
        make install

        [[ -f "$LOCALDESTDIR/bin/libzen-config" ]] && rm "$LOCALDESTDIR/bin/libzen-config"
        do_checkIfExist libzen-git libzen.a
        buildMediaInfo="true"
    fi

    cd "$LOCALBUILDDIR" || exit

    do_git "https://github.com/MediaArea/MediaInfoLib" libmediainfo-git
    if [[ $compile = "true" || $buildMediaInfo = "true" ]]; then
        cd Project/GNU/Library || exit
        [[ ! -f "configure" ]] && ./autogen.sh
        [[ -f libmediainfo.pc ]] && make distclean

        if [[ -d "$LOCALDESTDIR/include/MediaInfo" ]]; then
            rm -rf "$LOCALDESTDIR/include/MediaInfo{,DLL}"
            rm -f "$LOCALDESTDIR/lib/libmediainfo.{l,}a $LOCALDESTDIR/lib/pkgconfig/libmediainfo.pc"
            rm -f "$LOCALDESTDIR/bin-global/libmediainfo-config"
        fi
        ./configure --prefix="$LOCALDESTDIR" --disable-shared

        make -j "$cpuCount"
        make install

        cp libmediainfo.pc "$LOCALDESTDIR/lib/pkgconfig/"
        do_checkIfExist libmediainfo-git libmediainfo.a
        buildMediaInfo="true"
    fi

    cd "$LOCALBUILDDIR" || exit

    do_git "https://github.com/MediaArea/MediaInfo" mediainfo-git
    if [[ $compile = "true" || $buildMediaInfo = "true" ]]; then
        cd Project/GNU/CLI || exit
        [[ ! -f "configure" ]] && ./autogen.sh
        [[ -f config.log ]] && make distclean

        [[ -d "$LOCALDESTDIR/bin/mediainfo" ]] && rm -rf "$LOCALDESTDIR/bin/mediainfo"

        ./configure --prefix="$LOCALDESTDIR" --disable-shared --enable-staticlibs

        make -j "$cpuCount"
        make install

        do_checkIfExist mediainfo-git bin/mediainfo
    fi
}

stripAll() {
    echo -ne "\033]0;strip binaries\007"
    echo
    echo "-------------------------------------------------------------------------------"
    echo
    FILES=$(find "$LOCALDESTDIR/bin" -type f -mmin -600 ! \( -name '*-config' -o -name '.DS_Store' -o -name '*.conf' -o -name '*.png' -o -name '*.desktop' -o -path 'bin/ffmpeg_shared/*' -prune \))

    for f in $FILES; do
        strip "$f"
        echo "strip $f done..."
    done

    echo -ne "\033]0;deleting source folders\007"
    echo
    echo "deleting source folders..."
    echo
    find "$LOCALBUILDDIR" -mindepth 1 -maxdepth 1 -type d ! \( -name '*-git' -o -name '*-svn' -o -name '*-hg' \) -print0 | xargs -0 rm -rf
}

if [[ "$compile_libs_only" == "y" ]]; then
    buildLibs
fi

if [[ "$compile_ffmpeg_only" == "y" ]]; then
    buildFfmpeg
fi

if [[ -z "$compile_libs_only" ]] && [[ -z "$compile_ffmpeg_only" ]] && [[ -z "$compile_extras" ]]; then
    buildLibs
    buildFfmpeg
fi

if [[ "$compile_extras" == "y" ]]; then
    buildExtras
fi

stripAll

echo -ne "\033]0;compiling done...\007"
exit 0
