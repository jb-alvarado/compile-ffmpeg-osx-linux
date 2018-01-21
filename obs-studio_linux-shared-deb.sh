#!/bin/bash

cpuCount=6
compile="false"
buildFFmpeg="false"

LOCALBUILDDIR=$PWD/build
LOCALDESTDIR=/usr/local
export LOCALBUILDDIR LOCALDESTDIR

PKG_CONFIG_PATH="${LOCALDESTDIR}/lib/pkgconfig"
CPPFLAGS="-I${LOCALDESTDIR}/include"
CFLAGS="-I${LOCALDESTDIR}/include -mtune=generic -O2 -pipe"
CXXFLAGS="${CFLAGS}"
LDFLAGS="-L${LOCALDESTDIR}/lib -pipe"
export PKG_CONFIG_PATH CPPFLAGS CFLAGS CXXFLAGS LDFLAGS

[ -d $LOCALBUILDDIR ] || mkdir $LOCALBUILDDIR

# get git clone, or update
do_git() {
    local gitURL="$1"
    local gitFolder="$2"
    local gitDepth="$3"
    local gitVar="$4"
    echo -ne "\033]0;compile $gitFolder\007"
    if [ ! -d $gitFolder ]; then
        if [[ $gitDepth == "noDepth" ]]; then
            git clone $gitVar $gitURL $gitFolder
        else
            git clone --depth 1 $gitURL $gitFolder
        fi
        compile="true"
        cd $gitFolder
    else
        cd $gitFolder
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
        cd $svnFolder
    else
        cd $svnFolder
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
        cd $hgFolder
    else
        cd $hgFolder
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

    local response_code=$(curl --retry 20 --retry-max-time 5 -L -k -f -w "%{response_code}" -o "$archive" "$url")

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
    if [ -f "$LOCALBUILDDIR/$fileName" ]; then
        echo -
        echo -------------------------------------------------
        echo "build $packetName done..."
        echo -------------------------------------------------
        echo -
    else
        echo -------------------------------------------------
        echo "Build $packetName failed..."
        echo "Delete the source folder under '$LOCALBUILDDIR' and start again,"
        echo "or if you know there is no dependences hit enter for continue it."
        read -p ""
        sleep 5
    fi
}

buildProcess() {
    sudo apt install sudo checkinstall

    cd $LOCALBUILDDIR
    echo "-------------------------------------------------------------------------------"
    echo
    echo "compile global tools"
    echo
    echo "-------------------------------------------------------------------------------"

    if [ -f "$LOCALDESTDIR/bin/nasm" ]; then
        echo -------------------------------------------------
        echo "nasm-2.13.01 is already compiled"
        echo -------------------------------------------------
    else
        echo -ne "\033]0;compile nasm 64Bit\007"

        do_wget "http://www.nasm.us/pub/nasm/releasebuilds/2.13.01/nasm-2.13.01.tar.gz" nasm-2.13.01.tar.gz

        ./configure --prefix=$LOCALDESTDIR

        make -j $cpuCount
        sudo make install
    fi

    cd $LOCALBUILDDIR

    do_git "https://github.com/sekrit-twc/zimg.git" zimg-git noDepth

    if [[ $compile == "true" ]]; then
        if [ -d $LOCALDESTDIR/include/zimg.h ]; then
            make distclean
            make clean
        fi
        ./autogen.sh

        ./configure --prefix=$LOCALDESTDIR --disable-static --enable-shared

        make -j $cpuCount
        sudo checkinstall --maintainer="$USER" --pkgname=zimg --fstrans=no --backup=no --pkgversion="$(date +%Y-%m-%d)-git" --deldoc=yes -y

        mv *.deb ..

        do_checkIfExist zimg-git "zimg_$(date +%Y-%m-%d)-git-1_amd64.deb"
    else
        echo -------------------------------------------------
        echo "zimg-git is already up to date"
        echo -------------------------------------------------
    fi


    echo "-------------------------------------------------------------------------------"
    echo
    echo "compile global tools done..."
    echo
    echo "-------------------------------------------------------------------------------"

    cd $LOCALBUILDDIR
    echo "-------------------------------------------------------------------------------"
    echo
    echo "compile audio tools"
    echo
    echo "-------------------------------------------------------------------------------"

    do_git "https://github.com/mstorsjo/fdk-aac" fdk-aac-git

    if [[ $compile == "true" ]]; then
        if [[ ! -f ./configure ]]; then
            ./autogen.sh
        else
            sudo make uninstall
            make clean
        fi

        ./configure --prefix=$LOCALDESTDIR --enable-shared=yes --enable-static=no

        make -j $cpuCount
        sudo checkinstall --maintainer="$USER" --pkgname=fdk-aac --fstrans=no --backup=no --pkgversion="$(date +%Y-%m-%d)-git" --deldoc=yes -y

        mv *.deb ..

        do_checkIfExist fdk-aac-git "fdk-aac_$(date +%Y-%m-%d)-git-1_amd64.deb"
        compile="false"
    else
        echo -------------------------------------------------
        echo "fdk-aac is already up to date"
        echo -------------------------------------------------
    fi

    echo "-------------------------------------------------------------------------------"
    echo
    echo "compile audio tools done..."
    echo
    echo "-------------------------------------------------------------------------------"

    cd $LOCALBUILDDIR
    sleep 3
    echo "-------------------------------------------------------------------------------"
    echo
    echo "compile video tools"
    echo
    echo "-------------------------------------------------------------------------------"

    cd $LOCALBUILDDIR

    if [ -f "$LOCALDESTDIR/include/DeckLinkAPI.h" ]; then
        echo -------------------------------------------------
        echo "DeckLinkAPI is already downloaded"
        echo -------------------------------------------------
    else
        echo -ne "\033]0;download DeckLinkAPI\007"

        mkdir -p decklink/usr/local/include
        cp ../decklink-nix/* decklink/usr/local/include/
        mkdir decklink/DEBIAN
		cat <<EOT >> decklink/DEBIAN/control
Package: decklink-dev-inc
Version: 10.9.5
Section: base
Priority: optional
Architecture: amd64
Maintainer: local maintanier<local@example.org>
Description: Decklink Includes, needing for ffmpeg

EOT

        dpkg-deb --build decklink
				sudo dpkg -i decklink.deb

        if [ ! -f "$LOCALDESTDIR/include/DeckLinkAPI.h" ]; then
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

    #------------------------------------------------
    # final tools
    #------------------------------------------------

    cd $LOCALBUILDDIR

    do_git "https://github.com/mirror/x264.git" x264-git noDepth

    if [[ $compile == "true" ]]; then
        echo -ne "\033]0;compile x264-git\007"

        if [ -f "libx264.a" ]; then
            make distclean
        fi

        ./configure --prefix=$LOCALDESTDIR --enable-shared

        make -j $cpuCount
        sudo sudo checkinstall --maintainer="$USER" --pkgname=x264 --fstrans=no --backup=no --pkgversion="$(date +%Y-%m-%d)-git" --deldoc=yes -y

        mv *.deb ..

        do_checkIfExist x264-git "x264_$(date +%Y-%m-%d)-git-1_amd64.deb"
        compile="false"
        buildFFmpeg="true"
    else
        echo -------------------------------------------------
        echo "x264 is already up to date"
        echo -------------------------------------------------
    fi

    cd $LOCALBUILDDIR

    do_hg "https://bitbucket.org/multicoreware/x265" x265-hg

    if [[ $compile == "true" ]]; then
        cd build/linux
        rm -rf *

        cmake ../../source -DCMAKE_INSTALL_PREFIX=$LOCALDESTDIR -DENABLE_SHARED:BOOLEAN=ON -DCMAKE_CXX_FLAGS_RELEASE:STRING="-O3 -DNDEBUG $CXXFLAGS"

        make -j $cpuCount
        sudo checkinstall --maintainer="$USER" --pkgname=x265 --fstrans=no --backup=no --pkgversion="$(date +%Y-%m-%d)-git" --deldoc=yes -y

        mv *.deb ../..

        do_checkIfExist x265-git "x265_$(date +%Y-%m-%d)-git-1_amd64.deb"
        compile="false"
        buildFFmpeg="true"
    else
        echo -------------------------------------------------
        echo "x265 is already up to date"
        echo -------------------------------------------------
    fi

    cd $LOCALBUILDDIR
    echo "-------------------------------------------------------------------------------"
    echo "compile ffmpeg"
    echo "-------------------------------------------------------------------------------"

    do_git "https://github.com/FFmpeg/FFmpeg.git" ffmpeg-git

    if [[ $compile == "true" ]] || [[ $buildFFmpeg == "true" ]] || [[ ! -f $LOCALDESTDIR/bin/ffmpeg ]]; then


        if [ -f "config.mak" ]; then
            make distclean
        fi

        ./configure --prefix=$LOCALDESTDIR --enable-shared --disable-debug --disable-doc \
        --enable-gpl --enable-version3 --enable-runtime-cpudetect --enable-avfilter \
        --enable-nonfree --enable-decklink --enable-opengl \
        --enable-libzimg --enable-libfdk-aac \
        --enable-libx264 --enable-libx265

        make -j $cpuCount
        sudo checkinstall --maintainer="$USER" --pkgname=ffmpeg --fstrans=no --backup=no --pkgversion="$(date +%Y-%m-%d)-git" --requires="libsdl2-dev" --deldoc=yes -y

        mv *.deb ..

        do_checkIfExist ffmpeg-git "ffmpeg_$(date +%Y-%m-%d)-git-1_amd64.deb"

        compile="false"
    else
        echo -------------------------------------------------
        echo "ffmpeg is already up to date"
        echo -------------------------------------------------
    fi

    cd $LOCALBUILDDIR

    do_git "https://github.com/jp9000/obs-studio.git" obs-studio-git noDepth --recursive

    if [[ $compile == "true" ]]; then
        mkdir build && cd build
        cmake -DUNIX_STRUCTURE=1 -DCMAKE_INSTALL_PREFIX=$LOCALDESTDIR ..
        make -j $cpuCount
        sudo checkinstall --maintainer="$USER" --pkgname=obs-studio --fstrans=no --backup=no \
        --pkgversion="$(date +%Y-%m-%d)-git" \
        --requires="libv4l-dev,libxcb-xinerama0,libxcb-xinerama0,libcurl4-openssl-dev,libqt5widgets5" --deldoc=yes -y

        mv *.deb ..

        do_checkIfExist obs-studio-git "obs-studio_$(date +%Y-%m-%d)-git-1_amd64.deb"
        compile="false"
    else
        echo -------------------------------------------------
        echo "ops-studio is already up to date"
        echo -------------------------------------------------
    fi

    cd $LOCALBUILDDIR

    sudo chown $USER. *.deb
    sudo ldconfig

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
