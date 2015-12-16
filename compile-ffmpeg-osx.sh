#!/bin/bash

cpuCount=8
compile="false"
buildFFmpeg="false"

newFfmpeg="no"

LOCALBUILDDIR=$PWD/build
LOCALDESTDIR=$PWD/local
export LOCALBUILDDIR LOCALDESTDIR

PKG_CONFIG_PATH="${LOCALDESTDIR}/lib/pkgconfig"
CPPFLAGS="-I${LOCALDESTDIR}/include"
CFLAGS="-I${LOCALDESTDIR}/include -mtune=generic -O2 -pipe -mmacosx-version-min=10.8"
CXXFLAGS="${CFLAGS}"
LDFLAGS="-L${LOCALDESTDIR}/lib -pipe -mmacosx-version-min=10.8"
export PKG_CONFIG_PATH CPPFLAGS CFLAGS CXXFLAGS LDFLAGS

[ -d $LOCALBUILDDIR ] || mkdir $LOCALBUILDDIR
[ -d $LOCALDESTDIR ] || mkdir $LOCALDESTDIR

do_prompt() {
    # from http://superuser.com/a/608509
    while read -s -e -t 0.1; do : ; done
    read -p "$1"
}

# get git clone, or update
do_git() {
local gitURL="$1"
local gitFolder="$2"
local gitDepth="$3"
echo -ne "\033]0;compile $gitFolder\007"
if [ ! -d $gitFolder ]; then
	if [[ $gitDepth == "noDepth" ]]; then
		git clone $gitURL $gitFolder
	else
		git clone --depth 1 $gitURL $gitFolder
	fi
	compile="true"
	cd $gitFolder || exit
else
	cd $gitFolder || exit
	oldHead=`git rev-parse HEAD`
	git reset --hard @{u}
	git pull origin master
	newHead=`git rev-parse HEAD`

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
if [ ! -d $svnFolder ]; then
	svn checkout $svnURL $svnFolder
	compile="true"
	cd $svnFolder || exit
else
	cd $svnFolder || exit
	oldRevision=`svnversion`
	svn update
	newRevision=`svnversion`

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
if [ ! -d $hgFolder ]; then
	hg clone $hgURL $hgFolder
	compile="true"
	cd $hgFolder || exit
else
	cd $hgFolder || exit
	oldHead=`hg id --id`
	hg pull
	hg update
	newHead=`hg id --id`

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
          dirName=$( expr $archive : '\(.*\)\.\(tar.gz\)$' )
          rm -rf $dirName
          tar -xf "$archive"
          rm "$archive"
          cd "$dirName"
          ;;
        *.tar.bz2)
          dirName=$( expr $archive : '\(.*\)\.\(tar.bz2\)$' )
          rm -rf $dirName
          tar -xf "$archive"
          rm "$archive"
          cd "$dirName"
          ;;
        *.tar.xz)
          dirName=$( expr $archive : '\(.*\)\.\(tar.xz\)$' )
          #rm -rf $dirName
          tar -xf "$archive"
        #  rm "$archive"
          cd "$dirName"
          ;;
        *.zip)
          unzip "$archive"
          rm "$archive"
          ;;
        *.7z)
          dirName=$(expr $archive : '\(.*\)\.\(7z\)$' )
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
				read -p ""
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
				read -p "first close the batch window, then the shell window"
				sleep 5
		fi
	fi
}

buildProcess() {
cd $LOCALBUILDDIR || exit || exit
echo "-------------------------------------------------------------------------------"
echo
echo "compile global tools"
echo
echo "-------------------------------------------------------------------------------"

if [ -f "$LOCALDESTDIR/lib/libopenjpeg.a" ]; then
	echo -------------------------------------------------
	echo "openjpeg-1.5.2 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile openjpeg\007"

		do_wget "http://sourceforge.net/projects/openjpeg.mirror/files/1.5.2/openjpeg-1.5.2.tar.gz/download" openjpeg-1.5.2.tar.gz

		cmake -DBUILD_SHARED_LIBS:BOOL=off -DBUILD_MJ2:BOOL=on -DBUILD_JPWL:BOOL=on -DBUILD_JPIP:BOOL=on -DBUILD_THIRDPARTY:BOOL=on -DCMAKE_INSTALL_PREFIX=$LOCALDESTDIR -DCMAKE_C_FLAGS="-mtune=generic -pipe -DOPJ_STATIC"

		make -j $cpuCount
		make install

		do_checkIfExist openjpeg-1.5.2 libopenjpeg.a

		cp $LOCALDESTDIR/include/openjpeg-1.5/openjpeg.h $LOCALDESTDIR/include
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libexpat.a" ]; then
	echo -------------------------------------------------
	echo "expat-2.1.0 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile expat 64Bit\007"

		do_wget "http://sourceforge.net/projects/expat/files/expat/2.1.0/expat-2.1.0.tar.gz/download" expat-2.1.0.tar.gz

		./configure --prefix=$LOCALDESTDIR --enable-shared=no

		make -j $cpuCount
		make install

		do_checkIfExist expat-2.1.0 libexpat.a
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libfreetype.a" ]; then
	echo -------------------------------------------------
	echo "freetype-2.6 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile freetype\007"

		do_wget http://downloads.sourceforge.net/project/freetype/freetype2/2.6/freetype-2.6.tar.gz

		./configure --prefix=$LOCALDESTDIR --disable-shared --with-harfbuzz=no
		make -j $cpuCount
		make install

		do_checkIfExist freetype-2.6 libfreetype.a
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libfontconfig.a" ]; then
	echo -------------------------------------------------
	echo "fontconfig-2.11.94 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile fontconfig\007"

		do_wget http://www.freedesktop.org/software/fontconfig/release/fontconfig-2.11.94.tar.gz

		./configure --prefix=$LOCALDESTDIR --enable-shared=no

		sed -i 's/-L${libdir} -lfontconfig[^l]*$/-L${libdir} -lfontconfig -lfreetype -lexpat/' fontconfig.pc

		make -j $cpuCount
		make install

		do_checkIfExist fontconfig-2.11.94 libfontconfig.a
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libfribidi.a" ]; then
	echo -------------------------------------------------
	echo "fribidi-0.19.6 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile fribidi\007"

		do_wget http://fribidi.org/download/fribidi-0.19.6.tar.bz2

		./configure --prefix=$LOCALDESTDIR --enable-shared=no --with-glib=no

		make -j $cpuCount
		make install

if [ ! -f ${LOCALDESTDIR}/bin-global/fribidi-config ]; then
cat > ${LOCALDESTDIR}/bin-global/fribidi-config << "EOF"
#!/bin/sh
case $1 in
  --version)
    pkg-config --modversion fribidi
    ;;
  --cflags)
    pkg-config --cflags fribidi
    ;;
  --libs)
    pkg-config --libs fribidi
    ;;
  *)
    false
    ;;
esac
EOF
fi

	do_checkIfExist fribidi-0.19.6 libfribidi.a
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libSDL.a" ]; then
	echo -------------------------------------------------
	echo "SDL-1.2.15 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile SDL\007"

		do_wget "http://www.libsdl.org/release/SDL-1.2.15.tar.gz"

    sed -i '' "s:CGDirectPaletteRef palette;:/* CGDirectPaletteRef palette; */:" "src/video/quartz/SDL_QuartzVideo.h"

    ./configure --prefix=$LOCALDESTDIR --enable-shared=no --disable-video-x11

		make -j $cpuCount
		make install

		sed -i "s/-mwindows//" "$LOCALDESTDIR/bin/sdl-config"
		sed -i "s/-mwindows//" "$LOCALDESTDIR/lib/pkgconfig/sdl.pc"

		do_checkIfExist SDL-1.2.15 libSDL.a

    unset CFLAGS
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libpng.a" ]; then
	echo -------------------------------------------------
	echo "libpng-1.6.20 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile libpng 64Bit\007"

		do_wget "http://downloads.sourceforge.net/project/libpng/libpng16/1.6.20/libpng-1.6.20.tar.gz"

		./configure --prefix=$LOCALDESTDIR --disable-shared

		make -j $cpuCount
		make install

		do_checkIfExist libpng-1.6.20 libpng.a
fi

cd $LOCALBUILDDIR || exit

#----------------------
# crypto engine
#----------------------

if [ -f "$LOCALDESTDIR/lib/libssl.a" ]; then
	echo -------------------------------------------------
	echo "openssl-1.0.2e is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile openssl 64Bit\007"

		do_wget "https://www.openssl.org/source/openssl-1.0.2e.tar.gz"

		./Configure --prefix=$LOCALDESTDIR darwin64-x86_64-cc no-shared zlib enable-camellia enable-idea enable-mdc2 enable-tlsext enable-rfc3779

		make depend all
		make install

		do_checkIfExist openssl-1.0.2e libssl.a
fi

cd $LOCALBUILDDIR || exit

do_git "git://git.ffmpeg.org/rtmpdump" rtmpdump-git noDepth

if [[ $compile == "true" ]]; then
	if [ -f "$LOCALDESTDIR/lib/librtmp.a" ]; then
		rm -rf $LOCALDESTDIR/include/librtmp
		rm $LOCALDESTDIR/lib/librtmp.a
		rm $LOCALDESTDIR/lib/pkgconfig/librtmp.pc
		rm $LOCALDESTDIR/man/man3/librtmp.3
		rm $LOCALDESTDIR/bin/rtmpdum
		rm $LOCALDESTDIR/man/man1/rtmpdump.1
		rm $LOCALDESTDIR/man/man8/rtmpgw.8
		make clean
	fi

	make LDFLAGS="$LDFLAGS" prefix=$LOCALDESTDIR SHARED= SYS=posix install LIBS="-Llibrtmp -lrtmp $LIBS -lssl -lcrypto -ldl -lz"

	do_checkIfExist rtmpdump librtmp.a
	compile="false"
else
	echo -------------------------------------------------
	echo "rtmpdump is already up to date"
	echo -------------------------------------------------
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libxml2.a" ]; then
	echo -------------------------------------------------
	echo "libxml2-2.9.1 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile libxml2\007"

		do_wget "ftp://xmlsoft.org/libxml2/libxml2-2.9.1.tar.gz"

		./configure --prefix=$LOCALDESTDIR --disable-shared --enable-static

		make -j $cpuCount
		make install

		do_checkIfExist libxml2-2.9.1 libxml2.a
fi

echo "-------------------------------------------------------------------------------"
echo
echo "compile global tools done..."
echo
echo "-------------------------------------------------------------------------------"

cd $LOCALBUILDDIR || exit
echo "-------------------------------------------------------------------------------"
echo
echo "compile audio tools"
echo
echo "-------------------------------------------------------------------------------"

if [ -f "$LOCALDESTDIR/lib/libmp3lame.a" ]; then
	echo -------------------------------------------------
	echo "lame-3.99.5 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile lame\007"

		do_wget "http://sourceforge.net/projects/lame/files/lame/3.99/lame-3.99.5.tar.gz/download" lame-3.99.5.tar.gz

		./configure --prefix=$LOCALDESTDIR --enable-expopt=full --enable-shared=no

		make -j $cpuCount
		make install

		do_checkIfExist lame-3.99.5 libmp3lame.a
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libtwolame.a" ]; then
	echo -------------------------------------------------
	echo "twolame-0.3.13 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile twolame 64Bit\007"

		do_wget "http://sourceforge.net/projects/twolame/files/twolame/0.3.13/twolame-0.3.13.tar.gz/download" twolame-0.3.13.tar.gz

		./configure --prefix=$LOCALDESTDIR --disable-shared CPPFLAGS="$CPPFLAGS -DLIBTWOLAME_STATIC"

		make -j $cpuCount
		make install

		do_checkIfExist twolame-0.3.13 libtwolame.a
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libogg.a" ]; then
	echo -------------------------------------------------
	echo "libogg-1.3.1 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile libogg 64Bit\007"

		do_wget "http://downloads.xiph.org/releases/ogg/libogg-1.3.1.tar.gz"

		./configure --prefix=$LOCALDESTDIR --enable-shared=no
		make -j $cpuCount
		make install

		do_checkIfExist libogg-1.3.1 libogg.a
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libvorbis.a" ]; then
	echo -------------------------------------------------
	echo "libvorbis-1.3.3 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile libvorbis 64Bit\007"

		do_wget "http://downloads.xiph.org/releases/vorbis/libvorbis-1.3.3.tar.xz"

		./configure --prefix=$LOCALDESTDIR --enable-shared=no

		make -j $cpuCount
		make install

		do_checkIfExist libvorbis-1.3.3 libvorbis.a
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libtheora.a" ]; then
	echo -------------------------------------------------
	echo "libtheora-1.1.1 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile libtheora\007"

		do_wget "http://downloads.xiph.org/releases/theora/libtheora-1.1.1.tar.bz2"

		./configure --prefix=$LOCALDESTDIR --enable-shared=no --disable-examples

		make -j $cpuCount
		make install

		do_checkIfExist libtheora-1.1.1 libtheora.a
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libspeex.a" ]; then
	echo -------------------------------------------------
	echo "speex-1.2rc1 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile speex\007"

		do_wget "http://downloads.xiph.org/releases/speex/speex-1.2rc1.tar.gz"

		./configure --prefix=$LOCALDESTDIR --enable-shared=no

		make -j $cpuCount
		make install

		do_checkIfExist speex-1.2rc1 libspeex.a
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libvo-aacenc.a" ]; then
	echo -------------------------------------------------
	echo "vo-aacenc-0.1.3 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile vo-aacenc\007"

		do_wget "http://downloads.sourceforge.net/project/opencore-amr/vo-aacenc/vo-aacenc-0.1.3.tar.gz"

		./configure --prefix=$LOCALDESTDIR --enable-shared=no

		make -j $cpuCount
		make install

		do_checkIfExist vo-aacenc-0.1.3 libvo-aacenc.a
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libopencore-amrnb.a" ]; then
	echo -------------------------------------------------
	echo "opencore-amr-0.1.3 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile opencore-amr\007"

		do_wget "http://downloads.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-0.1.3.tar.gz"

		./configure --prefix=$LOCALDESTDIR --enable-shared=no

		make -j $cpuCount
		make install

		do_checkIfExist opencore-amr-0.1.3 libopencore-amrnb.a
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libvo-amrwbenc.a" ]; then
	echo -------------------------------------------------
	echo "vo-amrwbenc-0.1.2 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile vo-amrwbenc\007"

		do_wget "http://downloads.sourceforge.net/project/opencore-amr/vo-amrwbenc/vo-amrwbenc-0.1.2.tar.gz"

		./configure --prefix=$LOCALDESTDIR --enable-shared=no

		make -j $cpuCount
		make install

		do_checkIfExist vo-amrwbenc-0.1.2 libvo-amrwbenc.a
fi

cd $LOCALBUILDDIR || exit

do_git "https://github.com/mstorsjo/fdk-aac" fdk-aac-git

if [[ $compile == "true" ]]; then
	if [[ ! -f ./configure ]]; then
		./autogen.sh
	else
		make uninstall
		make clean
	fi

	./configure --prefix=$LOCALDESTDIR --enable-shared=no

	make -j $cpuCount
	make install

	do_checkIfExist fdk-aac-git libfdk-aac.a
else
	echo -------------------------------------------------
	echo "fdk-aac is already up to date"
	echo -------------------------------------------------
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libopus.a" ]; then
    echo -------------------------------------------------
    echo "opus-1.1 is already compiled"
    echo -------------------------------------------------
    else
		echo -ne "\033]0;compile opus\007"

		do_wget "http://downloads.xiph.org/releases/opus/opus-1.1.tar.gz"

    ./configure --prefix=$LOCALDESTDIR --enable-shared=no --enable-static --disable-doc

    make -j $cpuCount
		make install

		do_checkIfExist opus-1.1 libopus.a
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libsoxr.a" ]; then
	echo -------------------------------------------------
	echo "soxr-0.1.1 is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile soxr-0.1.1\007"

		do_wget "http://sourceforge.net/projects/soxr/files/soxr-0.1.1-Source.tar.xz"

		mkdir build
		cd build || exit

		cmake .. -DCMAKE_INSTALL_PREFIX=$LOCALDESTDIR -DHAVE_WORDS_BIGENDIAN_EXITCODE=0 -DBUILD_SHARED_LIBS:bool=off -DBUILD_TESTS:BOOL=OFF -DWITH_OPENMP:BOOL=OFF -DUNIX:BOOL=on -Wno-dev

		make -j $cpuCount
		make install

		do_checkIfExist soxr-0.1.1-Source libsoxr.a
fi

echo "-------------------------------------------------------------------------------"
echo
echo "compile audio tools done..."
echo
echo "-------------------------------------------------------------------------------"

cd $LOCALBUILDDIR || exit
sleep 3
echo "-------------------------------------------------------------------------------"
echo
echo "compile video tools"
echo
echo "-------------------------------------------------------------------------------"

do_git "https://github.com/webmproject/libvpx.git" libvpx-git noDepth

if [[ $compile == "true" ]]; then
	if [ -d $LOCALDESTDIR/include/vpx ]; then
		rm -rf $LOCALDESTDIR/include/vpx
		rm -f $LOCALDESTDIR/lib/pkgconfig/vpx.pc
		rm -f $LOCALDESTDIR/lib/libvpx.a
		make clean
	fi

		./configure --prefix=$LOCALDESTDIR --disable-shared --enable-static --disable-unit-tests --disable-docs --enable-postproc --enable-vp9-postproc --enable-runtime-cpu-detect

	make -j $cpuCount
	make install

	do_checkIfExist libvpx-git libvpx.a

	buildFFmpeg="true"
else
	echo -------------------------------------------------
	echo "libvpx-git is already up to date"
	echo -------------------------------------------------
fi

cd $LOCALBUILDDIR || exit

do_git "git://git.videolan.org/libbluray.git" libbluray-git

if [[ $compile == "true" ]]; then

  if [[ ! -f "configure" ]]; then
		autoreconf -fiv
	else
		make uninstall
		make clean
	fi

	./configure --prefix=$LOCALDESTDIR --disable-shared --enable-static --disable-examples --disable-bdjava --disable-doxygen-doc --disable-doxygen-dot --without-libxml2 --without-fontconfig --without-freetype --disable-udf LIBXML2_LIBS="-L$LOCALDESTDIR/lib -lxml2" LIBXML2_CFLAGS="-I$LOCALDESTDIR/include/libxml2 -DLIBXML_STATIC"

	make -j $cpuCount
	make install

	do_checkIfExist libbluray-git libbluray.a
else
	echo -------------------------------------------------
	echo "libbluray-git is already up to date"
	echo -------------------------------------------------
fi

cd $LOCALBUILDDIR || exit

do_git "https://github.com/libass/libass.git" libass-git

if [[ $compile == "true" ]]; then
	if [ -f $LOCALDESTDIR/lib/libass.a ]; then
		make uninstall
		make clean
	fi

	if [[ ! -f "configure" ]]; then
		./autogen.sh
	fi

	./configure --prefix=$LOCALDESTDIR --enable-shared=no --disable-harfbuzz FRIBIDI_LIBS="-L$LOCALDESTDIR/lib" FRIBIDI_CFLAGS="-I$LOCALDESTDIR/include/fribidi"

	make -j $cpuCount
	make install

	sed -i 's/-lass -lm/-lass -lfribidi -lm/' "$LOCALDESTDIR/lib/pkgconfig/libass.pc"

	do_checkIfExist libass-git libass.a
	buildFFmpeg="true"
else
	echo -------------------------------------------------
	echo "libass is already up to date"
	echo -------------------------------------------------
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/include/decklink/DeckLinkAPI.h" ]; then
	echo -------------------------------------------------
	echo "DeckLinkAPI is already downloaded"
	echo -------------------------------------------------
	else
	echo -ne "\033]0;download DeckLinkAPI\007"

		cd $LOCALDESTDIR/include || exit
    mkdir decklink
    cd decklink || exit

    do_wget https://raw.githubusercontent.com/jb-alvarado/compile-ffmpeg-osx/master/decklink-osx/DeckLinkAPI.h
    do_wget https://raw.githubusercontent.com/jb-alvarado/compile-ffmpeg-osx/master/decklink-osx/DeckLinkAPIConfiguration.h
    do_wget https://raw.githubusercontent.com/jb-alvarado/compile-ffmpeg-osx/master/decklink-osx/DeckLinkAPIDeckControl.h
    do_wget https://raw.githubusercontent.com/jb-alvarado/compile-ffmpeg-osx/master/decklink-osx/DeckLinkAPIDiscovery.h
    do_wget https://raw.githubusercontent.com/jb-alvarado/compile-ffmpeg-osx/master/decklink-osx/DeckLinkAPIModes.h
    do_wget https://raw.githubusercontent.com/jb-alvarado/compile-ffmpeg-osx/master/decklink-osx/DeckLinkAPIStreaming.h
    do_wget https://raw.githubusercontent.com/jb-alvarado/compile-ffmpeg-osx/master/decklink-osx/DeckLinkAPITypes.h
    do_wget https://raw.githubusercontent.com/jb-alvarado/compile-ffmpeg-osx/master/decklink-osx/DeckLinkAPIVersion.h
    do_wget https://raw.githubusercontent.com/jb-alvarado/compile-ffmpeg-osx/master/decklink-osx/DeckLinkAPIDispatch.cpp

    sed -i '' "s/void	InitDeckLinkAPI (void)/static void	InitDeckLinkAPI (void)/" DeckLinkAPIDispatch.cpp
    sed -i '' "s/bool		IsDeckLinkAPIPresent (void)/static bool		IsDeckLinkAPIPresent (void)/" DeckLinkAPIDispatch.cpp
    sed -i '' "s/void InitBMDStreamingAPI(void)/static void InitBMDStreamingAPI(void)/" DeckLinkAPIDispatch.cpp

		if [ ! -f "$LOCALDESTDIR/include/decklink/DeckLinkAPI.h" ]; then
			echo -------------------------------------------------
			echo "DeckLinkAPI.h download failed..."
			echo "if you know there is no dependences hit enter for continue it,"
			echo "or run script again"
			read -p ""
			sleep 5
		else
			echo -
			echo -------------------------------------------------
			echo "download DeckLinkAPI done..."
			echo -------------------------------------------------
			echo -
		fi
fi

cd $LOCALBUILDDIR || exit

if [ -f "$LOCALDESTDIR/lib/libxvidcore.a" ]; then
	echo -------------------------------------------------
	echo "xvidcore is already compiled"
	echo -------------------------------------------------
	else
		echo -ne "\033]0;compile xvidcore 64Bit\007"
    rm -rf xvidcore

		do_wget "http://downloads.xvid.org/downloads/xvidcore-1.3.4.tar.gz"

		cd xvidcore/build/generic || exit

		./configure --disable-assembly --prefix=$LOCALDESTDIR

		make -j $cpuCount
		make install

    rm $LOCALDESTDIR/lib/libxvidcore.4.dylib

		do_checkIfExist xvidcore libxvidcore.a
fi

#------------------------------------------------
# final tools
#------------------------------------------------

cd $LOCALBUILDDIR || exit

do_git "https://github.com/gpac/gpac.git" gpac-git noDepth
if [[ $compile = "true" ]]; then
    if [ -d "$LOCALDESTDIR/include/gpac" ]; then
        rm -rf $LOCALDESTDIR/bin/MP4Box $LOCALDESTDIR/lib/libgpac*
        rm -rf $LOCALDESTDIR/include/gpac
    fi
    [[ -f config.mak ]] && make distclean
    ./configure --prefix=$LOCALDESTDIR --static-mp4box --extra-libs="-lz"
    make -j $cpuCount
    make install-lib
    cp bin/gcc/MP4Box $LOCALDESTDIR/bin/
    do_checkIfExist gpac-git bin/MP4Box
fi

cd $LOCALBUILDDIR || exit

do_git "https://github.com/MediaArea/ZenLib" libzen-git
if [[ $compile = "true" ]]; then
    cd Project/GNU/Library || exit
    [[ ! -f "configure" ]] && ./autogen.sh || make distclean
    if [[ -d $LOCALDESTDIR/include/ZenLib ]]; then
        rm -rf $LOCALDESTDIR/include/ZenLib $LOCALDESTDIR/bin-global/libzen-config
        rm -f $LOCALDESTDIR/lib/libzen.{l,}a $LOCALDESTDIR/lib/pkgconfig/libzen.pc
    fi
    ./configure --prefix=$LOCALDESTDIR --disable-shared

		make -j $cpuCount
    make install

    [[ -f "$LOCALDESTDIR/bin/libzen-config" ]] && rm $LOCALDESTDIR/bin/libzen-config
    do_checkIfExist libzen-git libzen.a
    buildMediaInfo="true"
fi

cd $LOCALBUILDDIR || exit

do_git "https://github.com/MediaArea/MediaInfoLib" libmediainfo-git
if [[ $compile = "true" || $buildMediaInfo = "true" ]]; then
    cd Project/GNU/Library || exit
    [[ ! -f "configure" ]] && ./autogen.sh || make distclean
    if [[ -d $LOCALDESTDIR/include/MediaInfo ]]; then
        rm -rf $LOCALDESTDIR/include/MediaInfo{,DLL}
        rm -f $LOCALDESTDIR/lib/libmediainfo.{l,}a $LOCALDESTDIR/lib/pkgconfig/libmediainfo.pc
        rm -f $LOCALDESTDIR/bin-global/libmediainfo-config
    fi
    ./configure --prefix=$LOCALDESTDIR --disable-shared

		make -j $cpuCount
    make install

    cp libmediainfo.pc $LOCALDESTDIR/lib/pkgconfig/
    do_checkIfExist libmediainfo-git libmediainfo.a
    buildMediaInfo="true"
fi

cd $LOCALBUILDDIR || exit

do_git "https://github.com/MediaArea/MediaInfo" mediainfo-git
if [[ $compile = "true" || $buildMediaInfo = "true" ]]; then
    cd Project/GNU/CLI || exit
    [[ ! -f "configure" ]] && ./autogen.sh || make distclean
    [[ -d $LOCALDESTDIR/bin/mediainfo ]] && rm -rf $LOCALDESTDIR/bin/mediainfo

    ./configure --prefix=$LOCALDESTDIR --disable-shared --enable-staticlibs

		make -j $cpuCount
    make install

    do_checkIfExist mediainfo-git bin/mediainfo
fi

cd $LOCALBUILDDIR || exit

do_git "git://git.videolan.org/x264.git" x264-git noDepth

if [[ $compile == "true" ]]; then
	echo -ne "\033]0;compile x264-git\007"

	if [ -f "$LOCALDESTDIR/lib/libx264.a" ]; then
		rm -f $LOCALDESTDIR/include/x264.h $LOCALDESTDIR/include/x264_config.h $LOCALDESTDIR/lib/libx264.a
		rm -f $LOCALDESTDIR/bin/x264 $LOCALDESTDIR/lib/pkgconfig/x264.pc
	fi

	if [ -f "libx264.a" ]; then
		make distclean
	fi

	./configure --prefix=$LOCALDESTDIR --enable-static

	make -j $cpuCount
	make install

	do_checkIfExist x264-git libx264.a
	buildFFmpeg="true"
else
	echo -------------------------------------------------
	echo "x264 is already up to date"
	echo -------------------------------------------------
fi

cd $LOCALBUILDDIR || exit

do_hg "https://bitbucket.org/multicoreware/x265" x265-hg

if [[ $compile == "true" ]]; then
	cd build || exit/xcode
	rm -rf *
	rm -f $LOCALDESTDIR/bin/x265
	rm -f $LOCALDESTDIR/include/x265.h
	rm -f $LOCALDESTDIR/include/x265_config.h
	rm -f $LOCALDESTDIR/lib/libx265.a
	rm -f $LOCALDESTDIR/lib/pkgconfig/x265.pc

	cmake ../source -DCMAKE_INSTALL_PREFIX=$LOCALDESTDIR -DENABLE_SHARED:BOOLEAN=OFF -DCMAKE_CXX_FLAGS_RELEASE:STRING="-O3 -DNDEBUG $CXXFLAGS"

	make -j $cpuCount
	make install

	do_checkIfExist x265-git libx265.a
	buildFFmpeg="true"
else
	echo -------------------------------------------------
	echo "x265 is already up to date"
	echo -------------------------------------------------
fi

cd $LOCALBUILDDIR || exit
echo "-------------------------------------------------------------------------------"
echo "compile ffmpeg"
echo "-------------------------------------------------------------------------------"

do_git "https://github.com/FFmpeg/FFmpeg.git" ffmpeg-git

if [[ $compile == "true" ]] || [[ $buildFFmpeg == "true" ]] || [[ ! -f $LOCALDESTDIR/bin/ffmpeg ]]; then
	if [ -f "$LOCALDESTDIR/lib/libavcodec.a" ]; then
		rm -rf $LOCALDESTDIR/include/libavutil
		rm -rf $LOCALDESTDIR/include/libavcodec
		rm -rf $LOCALDESTDIR/include/libpostproc
		rm -rf $LOCALDESTDIR/include/libswresample
		rm -rf $LOCALDESTDIR/include/libswscale
		rm -rf $LOCALDESTDIR/include/libavdevice
		rm -rf $LOCALDESTDIR/include/libavfilter
		rm -rf $LOCALDESTDIR/include/libavformat
		rm -f $LOCALDESTDIR/lib/libavutil.a
		rm -f $LOCALDESTDIR/lib/libswresample.a
		rm -f $LOCALDESTDIR/lib/libswscale.a
		rm -f $LOCALDESTDIR/lib/libavcodec.a
		rm -f $LOCALDESTDIR/lib/libavdevice.a
		rm -f $LOCALDESTDIR/lib/libavfilter.a
		rm -f $LOCALDESTDIR/lib/libavformat.a
		rm -f $LOCALDESTDIR/lib/libpostproc.a
		rm -f $LOCALDESTDIR/lib/pkgconfig/libavcodec.pc
		rm -f $LOCALDESTDIR/lib/pkgconfig/libavutil.pc
		rm -f $LOCALDESTDIR/lib/pkgconfig/libpostproc.pc
		rm -f $LOCALDESTDIR/lib/pkgconfig/libswresample.pc
		rm -f $LOCALDESTDIR/lib/pkgconfig/libswscale.pc
		rm -f $LOCALDESTDIR/lib/pkgconfig/libavdevice.pc
		rm -f $LOCALDESTDIR/lib/pkgconfig/libavfilter.pc
		rm -f $LOCALDESTDIR/lib/pkgconfig/libavformat.pc
	fi

	if [ -f "config.mak" ]; then
		make distclean
	fi

	./configure --arch=x86_64 --prefix=$LOCALDESTDIR --disable-debug --disable-shared --disable-doc --enable-gpl --enable-version3 --enable-runtime-cpudetect --enable-avfilter --enable-bzlib --enable-zlib --enable-libbluray --enable-libopenjpeg --enable-fontconfig --enable-libfreetype --enable-openssl --enable-librtmp --enable-libass --enable-libmp3lame --enable-libopencore-amrnb --enable-libopencore-amrwb --enable-libvo-amrwbenc --enable-libsoxr --enable-libtwolame --enable-libspeex --enable-libtheora --enable-libvorbis --enable-libvo-aacenc --enable-opengl --enable-libopus --enable-libvpx --enable-libx264 --enable-libx265 --enable-libxvid --enable-nonfree --enable-libfdk-aac --enable-decklink --extra-cflags='-I$LOCALDESTDIR/include/decklink' --extra-ldflags='-L$LOCALDESTDIR/include/decklink' --extra-cflags='-DLIBTWOLAME_STATIC' --extra-libs='-lxml2 -llzma -lstdc++ -lpng -lm -lexpat -liconv' pkg_config='pkg-config --static'

  sed -i '' "s/ -std=c99//" config.mak

	make -j $cpuCount
	make install


	do_checkIfExist ffmpeg-git libavcodec.a

  newFfmpeg="yes"
else
	echo -------------------------------------------------
	echo "ffmpeg is already up to date"
	echo -------------------------------------------------
fi

cd $LOCALBUILDDIR || exit

do_git "http://luajit.org/git/luajit-2.0.git" luajit-git noDepth

if [[ $compile = "true" ]]; then
    if [[ -f "$LOCALDESTDIR/lib/libluajit-5.1.a" ]]; then
        rm -rf $LOCALDESTDIR/include/luajit-2.0 $LOCALDESTDIR/bin/luajit* $LOCALDESTDIR/lib/lua
        rm -rf $LOCALDESTDIR/lib/libluajit-5.1.a $LOCALDESTDIR/lib/pkgconfig/luajit.pc
    fi

    [[ -f "src/luajit" ]] && make clean
    make BUILDMODE=static amalg
    make BUILDMODE=static PREFIX=$LOCALDESTDIR FILE_T=luajit INSTALL_TNAME='luajit-$(VERSION)' INSTALL_TSYMNAME=luajit install
    # luajit comes with a broken .pc file
    sed -i '' "s/Libs.private: -Wl,-E -lm -ldl/Libs.private: -lm -ldl -liconv/" $LOCALDESTDIR/lib/pkgconfig/luajit.pc
    do_checkIfExist luajit-git libluajit-5.1.a
fi

cd $LOCALBUILDDIR || exit

do_git "https://github.com/lachs0r/rubberband.git" rubberband-git

if [[ $compile = "true" ]]; then
    [[ -f $LOCALDESTDIR/lib/librubberband.a ]] && make PREFIX=$LOCALDESTDIR uninstall
    [[ -f "lib/librubberband.a" ]] && make clean
    make PREFIX=$LOCALDESTDIR install-static
    do_checkIfExist rubberband-git librubberband.a
fi

cd $LOCALBUILDDIR || exit

do_git "https://github.com/mpv-player/mpv.git" mpv-git

if [[ $compile == "true" ]] || [[ $newFfmpeg == "yes" ]] || [[ ! -f $LOCALDESTDIR/bin/mpv/bin/mpv ]]; then
	if [ ! -f waf ]; then
		./bootstrap.py
	else
		./waf distclean
		rm waf
		rm -rf .waf-*
		rm -rf $LOCALDESTDIR/bin/mpv
		./bootstrap.py
	fi

	LDFLAGS="$LDFLAGS -pagezero_size 10000 -image_base 100000000" ./waf configure --prefix=$LOCALDESTDIR/bin/mpv --disable-debug-build --enable-static-build --disable-manpage-build --disable-pdf-build --lua=luajit

	./waf build -j $cpuCount
	./waf install

	cp -R TOOLS/osxbundle/mpv.app $LOCALDESTDIR/bin
	cp $LOCALDESTDIR/bin/mpv/bin/mpv $LOCALDESTDIR/bin/mpv.app

	do_checkIfExist mpv-git bin/mpv/bin/mpv
fi

cd $LOCALDESTDIR || exit

echo -ne "\033]0;strip binaries\007"
echo
echo "-------------------------------------------------------------------------------"
echo
FILES=`find bin -type f -mmin -600 ! \( -name '*-config' -o -name '.DS_Store' -o -name '*.lua' -o -name '*.conf' -o -name '*.png' -o -name '*.desktop' \)`

for f in $FILES; do
 strip $f
 echo "strip $f done..."
done

echo -ne "\033]0;deleting source folders\007"
echo
echo "deleting source folders..."
echo
find $LOCALBUILDDIR -mindepth 1 -maxdepth 1 -type d ! \( -name '*-git' -o -name '*-svn' -o -name '*-hg' \) -print0 | xargs -0 rm -rf
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
