#!/bin/bash

libbluray=""
fontconfig=""
libfreetype=""
libass=""
libtwolame=""
libmp3lame=""
libogg=""
libsoxr=""
libopus=""
libvpx=""
libx264=""
libx265=""
nonfree=""
libfdk_aac=""
decklink=""
opengl=""
zimg=""

mediainfo=""
mp4box=""

# --------------------------------------------------
# --------------------------------------------------
# enable / disable library:

#libbluray="--enable-libbluray"
#fontconfig="--enable-fontconfig"
#libfreetype="--enable-libfreetype"
#libass="--enable-libass"
#libtwolame="--enable-libtwolame --extra-cflags=-DLIBTWOLAME_STATIC"
libmp3lame="--enable-libmp3lame"
#libogg="--enable-libogg"
#libsoxr="--enable-libsoxr"
#libopus="--enable-libopus"
#libvpx="--enable-libvpx"
libx264="--enable-libx264"
libx265="--enable-libx265"
nonfree="--enable-nonfree"
libfdk_aac="--enable-libfdk-aac"
decklink="--enable-decklink"
opengl="--enable-opengl"
zimg="--enable-libzimg"
mediainfo="yes"
mp4box="yes"

# --------------------------------------------------

# check system
system=$( uname -s )
if [[ "$system" == "Darwin" ]]; then
	osExtra="-mmacosx-version-min=10.10"
	osString="osx"
	cpuCount=$( sysctl hw.ncpu | awk '{ print $2 - 1 }' )
	compNasm="no"
	osFlag=""
	osLibs="-liconv"
	arch="--arch=x86_64"
else
	osExtra=""
	osString="nix"
	cpuCount=$( nproc | awk '{ print $1 - 1 }' )
	compNasm="yes"
	osFlag="--enable-pic"
	osLibs="-lpthread"
	arch=""
fi

compile="false"
buildFFmpeg="false"

LOCALBUILDDIR="$PWD/build"
LOCALDESTDIR="$PWD/local"
export LOCALBUILDDIR LOCALDESTDIR

PKG_CONFIG_PATH="${LOCALDESTDIR}/lib/pkgconfig"
CPPFLAGS="-I${LOCALDESTDIR}/include"
CFLAGS="-I${LOCALDESTDIR}/include -mtune=generic -O2 $osExtra"
CXXFLAGS="${CFLAGS}"
LDFLAGS="-L${LOCALDESTDIR}/lib -pipe $osExtra"
export PKG_CONFIG_PATH CPPFLAGS CFLAGS CXXFLAGS LDFLAGS

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
echo -ne "\033]0;compile $gitFolder\007"
if [ ! -d "$gitFolder" ]; then
	if [[ $gitDepth == "noDepth" ]]; then
		git clone "$gitURL" "$gitFolder"
	else
		git clone --depth 1 "$gitURL" "$gitFolder"
	fi
	compile="true"
	cd "$gitFolder" || exit
else
	cd "$gitFolder" || exit
	oldHead=$(git rev-parse HEAD)
	git reset --hard "@{u}"
	git pull origin master
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

# get hg clone, or update
do_hg() {
local hgURL="$1"
local hgFolder="$2"
echo -ne "\033]0;compile $hgFolder\007"
if [ ! -d "$hgFolder" ]; then
	hg clone "$hgURL" "$hgFolder"
	compile="true"
	cd "$hgFolder" || exit
else
	cd "$hgFolder" || exit
	oldHead=$(hg id --id)
	hg pull
	hg update
	newHead=$(hg id --id)

	if [[ "$oldHead" != "$newHead" ]]; then
		compile="true"
	fi
fi
}

# get wget download
do_wget() {
    local url="$1"
    local archive="$2"
    local dirName="$3"
    if [[ -z $archive ]]; then
        # remove arguments and filepath
        archive=${url%%\?*}
        archive=${archive##*/}
    fi

    local -r response_code=$(curl --retry 20 --retry-max-time 5 -L -k -f -w "%{response_code}" -o "$archive" "$url")

    if [[ $response_code = "200" || $response_code = "226" ]]; then
      case "$archive" in
        *.tar.gz)
          dirName=$( expr "$archive" : '\(.*\)\.\(tar.gz\)$' )
          rm -rf "$dirName"
          tar -xf "$archive"
          rm "$archive"
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
          dirName=$( expr "$archive" : '\(.*\)\.\(tar.xz\)$' )
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
				echo "or if you know there is no dependences hit enter for continue it."
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
				echo "or if you know there is no dependences hit enter for continue it"
				read -r -p "first close the batch window, then the shell window"
				sleep 5
		fi
	fi
}

buildProcess() {
cd "$LOCALBUILDDIR" || exit
echo "-------------------------------------------------------------------------------"
echo
echo "compile global tools"
echo
echo "-------------------------------------------------------------------------------"

if [ ! -f "/usr/local/bin/nasm" ] && [[ $compNasm == "yes" ]]; then
    echo -ne "\033]0;compile nasm 64Bit\007"

    do_wget "http://www.nasm.us/pub/nasm/releasebuilds/2.13.01/nasm-2.13.01.tar.gz" nasm-2.13.01.tar.gz

    ./configure --prefix="$LOCALDESTDIR"

    make -j "$cpuCount"
    make install
	sudo cp "$LOCALDESTDIR/bin/nasm" "$LOCALDESTDIR/bin/ndisasm" /usr/local/bin/
else
    echo -------------------------------------------------
    echo "nasm-2.13.01 is already compiled, or not needed"
    echo -------------------------------------------------
fi

if [[ -n "$fontconfig" ]]; then
	if [ -f "$LOCALDESTDIR/lib/libexpat.a" ]; then
		echo -------------------------------------------------
		echo "expat-2.2.5 is already compiled"
		echo -------------------------------------------------
		else
			echo -ne "\033]0;compile expat 64Bit\007"

			do_wget "https://downloads.sourceforge.net/project/expat/expat/2.2.5/expat-2.2.5.tar.bz2"

			./configure --prefix="$LOCALDESTDIR" --enable-shared=no

			make -j "$cpuCount"
			make install

			do_checkIfExist expat-2.2.5 libexpat.a
	fi

	cd "$LOCALBUILDDIR" || exit

	if [ -f "$LOCALDESTDIR/lib/libfreetype.a" ]; then
		echo -------------------------------------------------
		echo "freetype-2.6 is already compiled"
		echo -------------------------------------------------
		else
			echo -ne "\033]0;compile freetype\007"

			do_wget "https://downloads.sourceforge.net/project/freetype/freetype2/2.8.1/freetype-2.8.1.tar.gz"

			./configure --prefix="$LOCALDESTDIR" --disable-shared --with-harfbuzz=no
			make -j "$cpuCount"
			make install

			do_checkIfExist freetype-2.6 libfreetype.a
	fi
fi

cd "$LOCALBUILDDIR" || exit

if [[ -n "$libfreetype" ]]; then
	if [ -f "$LOCALDESTDIR/lib/libfontconfig.a" ]; then
		echo -------------------------------------------------
		echo "fontconfig-2.12.6 is already compiled"
		echo -------------------------------------------------
		else
			echo -ne "\033]0;compile fontconfig\007"

			do_wget "https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.12.6.tar.gz"

			./configure --prefix="$LOCALDESTDIR" --enable-shared=no

			make -j "$cpuCount"
			make install

			do_checkIfExist fontconfig-2.12.6 libfontconfig.a
	fi
fi

cd "$LOCALBUILDDIR" || exit

if [[ -n "$libass" ]]; then
	if [ -f "$LOCALDESTDIR/lib/libfribidi.a" ]; then
		echo -------------------------------------------------
		echo "fribidi-0.19.7 is already compiled"
		echo -------------------------------------------------
		else
			echo -ne "\033]0;compile fribidi\007"

			do_wget "https://github.com/fribidi/fribidi/archive/0.19.7.tar.gz" fribidi-0.19.7.tar.gz

	        ./bootstrap
			./configure --prefix="$LOCALDESTDIR" --enable-shared=no --with-glib=no

			make -j "$cpuCount"
			make install

		do_checkIfExist fribidi-0.19.7 libfribidi.a
	fi
fi

cd "$LOCALBUILDDIR" || exit

if [[ -n "$opengl" ]]; then
	if [ -f "$LOCALDESTDIR/lib/libSDL2.a" ]; then
		echo -------------------------------------------------
		echo "SDL2-2.0.7 is already compiled"
		echo -------------------------------------------------
		else
			echo -ne "\033]0;compile SDL\007"

			do_wget "https://www.libsdl.org/release/SDL2-2.0.7.tar.gz"

	    ./configure --prefix="$LOCALDESTDIR" --enable-shared=no --disable-video-x11

			make -j "$cpuCount"
			make install

			do_checkIfExist SDL2-2.0.7 libSDL2.a

	    unset CFLAGS
	fi
fi
cd "$LOCALBUILDDIR" || exit

if [ -f "$LOCALDESTDIR/lib/libpng.a" ]; then
	echo -------------------------------------------------
	echo "libpng-1.6.34 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile libpng 64Bit\007"

		do_wget "https://downloads.sourceforge.net/project/libpng/libpng16/1.6.34/libpng-1.6.34.tar.gz"

		./configure --prefix="$LOCALDESTDIR" --disable-shared

		make -j "$cpuCount"
		make install

		do_checkIfExist libpng-1.6.34 libpng.a
fi

cd "$LOCALBUILDDIR" || exit

if [ -f "$LOCALDESTDIR/lib/libxml2.a" ]; then
	echo -------------------------------------------------
	echo "libxml2-2.9.7 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile libxml2\007"

		do_wget "ftp://xmlsoft.org/libxml2/libxml2-2.9.7.tar.gz"

		./configure --prefix="$LOCALDESTDIR" --disable-shared --enable-static

		make -j "$cpuCount"
		make install

		do_checkIfExist libxml2-2.9.7 libxml2.a
fi

cd "$LOCALBUILDDIR" || exit

if [[ -n "$zimg" ]]; then
	do_git "https://github.com/sekrit-twc/zimg.git" zimg-git

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

		do_checkIfExist zimg-git libzimg.a
	else
		echo -------------------------------------------------
		echo "zimg is already up to date"
		echo -------------------------------------------------
	fi
fi

echo "-------------------------------------------------------------------------------"
echo
echo "compile global tools done..."
echo
echo "-------------------------------------------------------------------------------"

cd "$LOCALBUILDDIR" || exit
echo "-------------------------------------------------------------------------------"
echo
echo "compile audio tools"
echo
echo "-------------------------------------------------------------------------------"

if [[ -n "$libmp3lame" ]]; then
	if [ -f "$LOCALDESTDIR/lib/libmp3lame.a" ]; then
		echo -------------------------------------------------
		echo "lame-3.100 is already compiled"
		echo -------------------------------------------------
		else
			echo -ne "\033]0;compile lame\007"

			do_wget "https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz" lame-3.100.tar.gz

			./configure --prefix="$LOCALDESTDIR" --enable-expopt=full --enable-shared=no

			make -j "$cpuCount"
			make install

			do_checkIfExist lame-3.100 libmp3lame.a
	fi
fi

cd "$LOCALBUILDDIR" || exit

if [[ -n "$libtwolame" ]]; then
	if [ -f "$LOCALDESTDIR/lib/libtwolame.a" ]; then
		echo -------------------------------------------------
		echo "twolame-0.3.13 is already compiled"
		echo -------------------------------------------------
		else
			echo -ne "\033]0;compile twolame 64Bit\007"

			do_wget "http://sourceforge.net/projects/twolame/files/twolame/0.3.13/twolame-0.3.13.tar.gz/download" twolame-0.3.13.tar.gz

			./configure --prefix="$LOCALDESTDIR" --disable-shared CPPFLAGS="$CPPFLAGS -DLIBTWOLAME_STATIC"

			make -j "$cpuCount"
			make install

			do_checkIfExist twolame-0.3.13 libtwolame.a
	fi
fi

cd "$LOCALBUILDDIR" || exit

if [[ -n "$libogg" ]]; then
	if [ -f "$LOCALDESTDIR/lib/libogg.a" ]; then
		echo -------------------------------------------------
		echo "libogg-1.3.3 is already compiled"
		echo -------------------------------------------------
		else
			echo -ne "\033]0;compile libogg 64Bit\007"

			do_wget "https://ftp.osuosl.org/pub/xiph/releases/ogg/libogg-1.3.3.tar.gz"

			./configure --prefix="$LOCALDESTDIR" --enable-shared=no
			make -j "$cpuCount"
			make install

			do_checkIfExist libogg-1.3.3 libogg.a
	fi
fi

cd "$LOCALBUILDDIR" || exit

if [[ -n "$libfdk_aac" ]]; then
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

if [[ -n "$libopus" ]]; then
	if [ -f "$LOCALDESTDIR/lib/libopus.a" ]; then
	    echo -------------------------------------------------
	    echo "opus-1.2.1 is already compiled"
	    echo -------------------------------------------------
	    else
			echo -ne "\033]0;compile opus\007"

			do_wget "https://ftp.osuosl.org/pub/xiph/releases/opus/opus-1.2.1.tar.gz"

	    ./configure --prefix="$LOCALDESTDIR" --enable-shared=no --enable-static --disable-doc

	    make -j "$cpuCount"
			make install

			do_checkIfExist opus-1.2.1 libopus.a
	fi
fi

cd "$LOCALBUILDDIR" || exit

if [[ -n "$libsoxr" ]]; then
	if [ -f "$LOCALDESTDIR/lib/libsoxr.a" ]; then
		echo -------------------------------------------------
		echo "soxr-0.1.2 is already compiled"
		echo -------------------------------------------------
		else
			echo -ne "\033]0;compile soxr-0.1.1\007"

			do_wget "https://downloads.sourceforge.net/project/soxr/soxr-0.1.2-Source.tar.xz"

			mkdir build
			cd build || exit

			cmake .. -DCMAKE_INSTALL_PREFIX="$LOCALDESTDIR" -DHAVE_WORDS_BIGENDIAN_EXITCODE=0 -DBUILD_SHARED_LIBS:bool=off -DBUILD_TESTS:BOOL=OFF -DWITH_OPENMP:BOOL=OFF -DUNIX:BOOL=on -Wno-dev

			make -j "$cpuCount"
			make install

			do_checkIfExist soxr-0.1.2-Source libsoxr.a
	fi
fi

echo "-------------------------------------------------------------------------------"
echo
echo "compile audio tools done..."
echo
echo "-------------------------------------------------------------------------------"

cd "$LOCALBUILDDIR" || exit
sleep 3
echo "-------------------------------------------------------------------------------"
echo
echo "compile video tools"
echo
echo "-------------------------------------------------------------------------------"

if [[ -n "$libvpx" ]]; then
do_git "https://github.com/webmproject/libvpx.git" libvpx-git noDepth

	if [[ $compile == "true" ]]; then
		if [ -d "$LOCALDESTDIR/include/vpx" ]; then
			rm -rf "$LOCALDESTDIR/include/vpx"
			rm -f "$LOCALDESTDIR/lib/pkgconfig/vpx.pc"
			rm -f "$LOCALDESTDIR/lib/libvpx.a"
			make clean
		fi

			./configure --prefix="$LOCALDESTDIR" --disable-shared --enable-static --disable-unit-tests --disable-docs --enable-postproc --enable-vp9-postproc --enable-runtime-cpu-detect $osFlag

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

if [[ -n "$libbluray" ]]; then
	do_git "git://git.videolan.org/libbluray.git" libbluray-git

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
	else
		echo -------------------------------------------------
		echo "libbluray-git is already up to date"
		echo -------------------------------------------------
	fi
fi

cd "$LOCALBUILDDIR" || exit

if [[ -n "$libass" ]]; then
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

		sed -i 's/-lass -lm/-lass -lfribidi -lm/' "$LOCALDESTDIR/lib/pkgconfig/libass.pc"

		do_checkIfExist libass-git libass.a
		buildFFmpeg="true"
	else
		echo -------------------------------------------------
		echo "libass is already up to date"
		echo -------------------------------------------------
	fi
fi

cd "$LOCALBUILDDIR" || exit

if [[ -n "$decklink" ]]; then
	if [ -f "$LOCALDESTDIR/include/DeckLinkAPI.h" ]; then
		echo -------------------------------------------------
		echo "DeckLinkAPI is already in place"
		echo -------------------------------------------------
	else
		echo -ne "\033]0;download DeckLinkAPI\007"

		cd "$LOCALDESTDIR/include" || exit

	    cp ../../decklink-${osString}/* .

			if [[ $osString == "osx" ]]; then
		    sed -i '' "s/void	InitDeckLinkAPI (void)/static void	InitDeckLinkAPI (void)/" DeckLinkAPIDispatch.cpp
		    sed -i '' "s/bool		IsDeckLinkAPIPresent (void)/static bool		IsDeckLinkAPIPresent (void)/" DeckLinkAPIDispatch.cpp
		    sed -i '' "s/void InitBMDStreamingAPI(void)/static void InitBMDStreamingAPI(void)/" DeckLinkAPIDispatch.cpp
			fi
	fi
fi

#------------------------------------------------
# final tools
#------------------------------------------------

cd "$LOCALBUILDDIR" || exit
if [[ -n "$mp4box" ]]; then
	do_git "https://github.com/gpac/gpac.git" gpac-git noDepth
	if [[ $compile = "true" ]]; then
	    if [ -d "$LOCALDESTDIR/include/gpac" ]; then
	        rm -rf "$LOCALDESTDIR/bin/MP4Box $LOCALDESTDIR/lib/libgpac*"
	        rm -rf "$LOCALDESTDIR/include/gpac"
	    fi
	    [[ -f config.mak ]] && make distclean
	    ./configure --prefix="$LOCALDESTDIR" --static-mp4box --extra-libs="-lz -lm"
	    make -j "$cpuCount"
	    make install-lib
	    cp bin/gcc/MP4Box "$LOCALDESTDIR/bin/"
	    do_checkIfExist gpac-git bin/MP4Box
	fi
fi

cd "$LOCALBUILDDIR" || exit

if [[ -n "$mediainfo" ]]; then
	do_git "https://github.com/MediaArea/ZenLib" libzen-git
	if [[ $compile = "true" ]]; then
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
fi

cd "$LOCALBUILDDIR" || exit

if [[ -n "$libx264" ]]; then
	do_git "git://git.videolan.org/x264.git" x264-git noDepth

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

if [[ -n "$libx265" ]]; then
	do_hg "https://bitbucket.org/multicoreware/x265" x265-hg

	if [[ $compile == "true" ]]; then
		cd build || exit/xcode
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
		buildFFmpeg="true"
	else
		echo -------------------------------------------------
		echo "x265 is already up to date"
		echo -------------------------------------------------
	fi
fi

cd "$LOCALBUILDDIR" || exit
echo "-------------------------------------------------------------------------------"
echo "compile ffmpeg"
echo "-------------------------------------------------------------------------------"

do_git "https://github.com/FFmpeg/FFmpeg.git" ffmpeg-git

if [[ $compile == "true" ]] || [[ $buildFFmpeg == "true" ]] || [[ ! -f "$LOCALDESTDIR/bin/ffmpeg" ]]; then
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

	if [ -f "ffbuild/config.mak" ]; then
		make distclean
	fi

	./configure $arch --prefix="$LOCALDESTDIR" --disable-debug --disable-shared --disable-doc --enable-gpl --enable-version3 --enable-runtime-cpudetect --enable-avfilter --enable-zlib $opengl $zimg $libbluray $fontconfig $libfreetype $libass $libtwolame $libmp3lame $libsoxr $libopus $libvpx $libx264 $libx265 $nonfree $libfdk_aac $decklink $libogg $osFlag --extra-libs="-lxml2 -llzma -lstdc++ -lpng -lm -lexpat $osLibs" pkg_config='pkg-config --static'

	make -j "$cpuCount"
	make install


	do_checkIfExist ffmpeg-git libavcodec.a
else
	echo -------------------------------------------------
	echo "ffmpeg is already up to date"
	echo -------------------------------------------------
fi

cd "$LOCALDESTDIR" || exit

echo -ne "\033]0;strip binaries\007"
echo
echo "-------------------------------------------------------------------------------"
echo
FILES=$(find bin -type f -mmin -600 ! \( -name '*-config' -o -name '.DS_Store' -o -name '*.conf' -o -name '*.png' -o -name '*.desktop' \))

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

buildProcess

echo -ne "\033]0;compiling done...\007"
echo
echo "Window close in 15"
echo
sleep 5
echo
echo "Window close in 10"
echo
sleep 5
echo
echo "Window close in 5"
sleep 5
