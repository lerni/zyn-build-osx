#!/bin/bash

# This script builds an OSX version of zynaddsubfx
# (http://zynaddsubfx.sourceforge.net)
# and all its build-dependencies from scratch.
#
# It requires a working c-compiler with C++11 support,
# bash, sed, curl, make and git
#
# It can be run by a 'normal user' (no sudo required).
#
# The script is suitable for headless (automatic) builds, but
# note that the last step: building the DMG requires
# a "Finder" process. The user needs to be graphically
# logged in (but can be an inactive user, switch-user)
#

#### some influential environment variables:

## we keep a copy of the sources here:
: ${SRCDIR=/var/tmp/src_cache}
## actual build location
: ${BUILDD=$HOME/src/zyn_build}
## target install dir (chroot-like)
: ${PREFIX=$HOME/src/zyn_stack}
## where the resulting .dmg ends up
: ${OUTDIR="/tmp/"}
## concurrency
: ${MAKEFLAGS="-j4"}
## if the NOSTACK environment var is not empty, skip re-building the stack if it has been built before
: ${NOSTACK=""}
## semicolon separated list of fat-binary architectures, ppc;i386;x86_64
: ${ARCHITECTURES="i386;x86_64"}


pushd "`/usr/bin/dirname \"$0\"`" > /dev/null; this_script_dir="`pwd`"; popd > /dev/null

################################################################################
#### set compiler flags depending on build-host

case `sw_vers -productVersion | cut -d'.' -f1,2` in
	"10.10")
		echo "Yosemite"
		GLOBAL_CPPFLAGS="-Wno-error=unused-command-line-argument"
		GLOBAL_CFLAGS="-O3 -Wno-error=unused-command-line-argument -mmacosx-version-min=10.9 -DMAC_OS_X_VERSION_MAX_ALLOWED=1090"
		GLOBAL_CXXFLAGS="-O3 -Wno-error=unused-command-line-argument -mmacosx-version-min=10.9 -DMAC_OS_X_VERSION_MAX_ALLOWED=1090"
		GLOBAL_LDFLAGS="-mmacosx-version-min=10.9 -DMAC_OS_X_VERSION_MAX_ALLOWED=1090 -headerpad_max_install_names"
		;;
	*)
		echo "**UNTESTED OSX VERSION**"
		echo "if it works, please report back :)"
		ARCHITECTURES="i386;x86_64"
		OSXARCH="-arch i386 -arch x86_64"
		GLOBAL_CPPFLAGS="-mmacosx-version-min=10.5 -DMAC_OS_X_VERSION_MAX_ALLOWED=1090"
		GLOBAL_CFLAGS="-O3 -mmacosx-version-min=10.5 -DMAC_OS_X_VERSION_MAX_ALLOWED=1090"
		GLOBAL_CXXFLAGS="-O3 -mmacosx-version-min=10.5 -DMAC_OS_X_VERSION_MAX_ALLOWED=1090"
		GLOBAL_LDFLAGS="-mmacosx-version-min=10.5 -DMAC_OS_X_VERSION_MAX_ALLOWED=1090 -headerpad_max_install_names"
		;;
esac

if test -z "$OSXARCH"; then
	OLDIFS=$IFS
	IFS=';'
	for arch in $ARCHITECTURES; do
		OSXARCH="$OSXARCH -arch $arch"
	done
	echo "SET ARCH:  $OSXARCH"
	IFS=$OLDIFS
fi

################################################################################
set -e

unset PKG_CONFIG_PATH
export PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig
export PREFIX
export SRCDIR

export PATH=${PREFIX}/bin:/usr/local/git/bin/:/usr/bin:/bin:/usr/sbin:/sbin


################################################################################
###  COMPILE THE BUILD-DEPENDENCIES  -> NOSTACK
################################################################################

## if the NOSTACK environment is not empty, skip re-building the stack
## if it has been built before
if test ! -f "${PREFIX}/zyn_stack_complete" -o -z "$NOSTACK"; then


## Start with a clean slate
rm -rf ${BUILDD}
rm -rf ${PREFIX}

mkdir -p ${SRCDIR}
mkdir -p ${PREFIX}
mkdir -p ${BUILDD}

################################################################################

function autoconfconf {
set -e
echo "======= $(pwd) ======="
	CPPFLAGS="-I${PREFIX}/include${GLOBAL_CPPFLAGS:+ $GLOBAL_CPPFLAGS}" \
	CFLAGS="${OSXARCH}${GLOBAL_CFLAGS:+ $GLOBAL_CFLAGS}" \
	CXXFLAGS="${OSXARCH}${GLOBAL_CXXFLAGS:+ $GLOBAL_CXXFLAGS}" \
	LDFLAGS="${OSXARCH}${GLOBAL_LDFLAGS:+ $GLOBAL_LDFLAGS}" \
	./configure --disable-dependency-tracking --prefix=$PREFIX $@
}

function autoconfbuild {
set -e
	autoconfconf $@
	make $MAKEFLAGS
	make install
}

function download {
	echo "--- Downloading.. $2"
	test -f ${SRCDIR}/$1 || curl -L -o ${SRCDIR}/$1 $2
}

function src {
	download ${1}.${2} $3
	cd ${BUILDD}
	rm -rf $1
	tar xf ${SRCDIR}/${1}.${2}
	cd $1
}

################################################################################

src m4-1.4.17 tar.gz http://ftp.gnu.org/gnu/m4/m4-1.4.17.tar.gz
./configure --prefix=$PREFIX
make && make install

src pkg-config-0.28 tar.gz http://pkgconfig.freedesktop.org/releases/pkg-config-0.28.tar.gz
./configure --prefix=$PREFIX --with-internal-glib
make $MAKEFLAGS
make install

src autoconf-2.69 tar.xz http://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz
autoconfbuild
hash autoconf
hash autoreconf

src automake-1.14 tar.gz http://ftp.gnu.org/gnu/automake/automake-1.14.tar.gz
autoconfbuild
hash automake

src libtool-2.4 tar.gz http://ftp.gnu.org/gnu/libtool/libtool-2.4.tar.gz
autoconfbuild
hash libtoolize

src make-4.1 tar.gz http://ftp.gnu.org/gnu/make/make-4.1.tar.gz
autoconfbuild
hash make

src cmake-2.8.12.2 tar.gz http://www.cmake.org/files/v2.8/cmake-2.8.12.2.tar.gz
./bootstrap --prefix=$PREFIX
make $MAKEFLAGS
make install

################################################################################

src zlib-1.2.7 tar.gz ftp://ftp.simplesystems.org/pub/libpng/png/src/history/zlib/zlib-1.2.7.tar.gz
CFLAGS="${GLOBAL_CFLAGS}" \
LDFLAGS="${GLOBAL_LDFLAGS}" \
./configure --archs="$OSXARCH" --prefix=$PREFIX
make $MAKEFLAGS
make install


################################################################################
## we only want jack headers - not the complete jack installation, sadly upsteam
## only provides a osx installer (which needs admin privileges and drops things
## to /usr/local/ --- this is a re-pack of the relevant files from there.
download jack_osx_dev.tar.gz http://robin.linuxaudio.org/jack_osx_dev.tar.gz
cd "$PREFIX"
tar xzf ${SRCDIR}/jack_osx_dev.tar.gz
"$PREFIX"/update_pc_prefix.sh


################################################################################
## does not build cleanly with multiarch (little/big endian),
## TODO build separate dylibs (one for every arch) then lipo combine them and 
## ifdef the mixed header. 
## it's optional for zynaddsubfx, since zyn needs C++11 and there's no
## easy way to build PPC binaries with a C++11 compiler we don't care..

src portaudio tgz http://portaudio.com/archives/pa_stable_v19_20140130.tgz
if ! echo "$OSXARCH" | grep -q "ppc"; then
	autoconfbuild --enable-mac-universal --enable-static=no
fi

################################################################################

## portmidi needs a bit of convincing..
download portmidi-src-217.zip http://sourceforge.net/projects/portmedia/files/portmidi/217/portmidi-src-217.zip/download
cd ${BUILDD}
rm -rf portmidi
unzip ${SRCDIR}/portmidi-src-217.zip
cd portmidi
## XXX pass this via cmake args somehow, yet the 'normal' way for cmake does not
## seem to apply...  whatever. sed to he rescue
# -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=10.5 -DCMAKE_OSX_ARCHITECTURES="i386;x86_64"
if ! echo "$OSXARCH" | grep -q "i386"; then
sed -i '' 's/ i386//g' CMakeLists.txt
fi
if ! echo "$OSXARCH" | grep -q "ppc"; then
sed -i '' 's/ ppc//g' CMakeLists.txt
fi
if ! echo "$OSXARCH" | grep -q "x86_64"; then
sed -i '' 's/ x86_64//g' CMakeLists.txt
fi
## Argh! portmidi FORCE hardcodes the sysroot to 10.5
sed -i '' 's/CMAKE_OSX_SYSROOT /CMAKE_XXX_SYSROOT /g' ./pm_common/CMakeLists.txt
CFLAGS="${OSXARCH} ${GLOBAL_CFLAGS}" \
CXXFLAGS="${OSXARCH} ${GLOBAL_CXXFLAGS}" \
LDFLAGS="${OSXARCH} ${GLOBAL_LDFLAGS}" \
make -f pm_mac/Makefile.osx configuration=Release PF=${PREFIX} CMAKE_OSX_SYSROOT="-g"
## cd Release; make install # is also broken without sudo and with custom prefix
## so just deploy manually..
cp Release/libportmidi.dylib ${PREFIX}/lib/
install_name_tool -id ${PREFIX}/lib/libportmidi.dylib ${PREFIX}/lib/libportmidi.dylib
cp pm_common/portmidi.h ${PREFIX}/include
cp porttime/porttime.h ${PREFIX}/include

################################################################################

src liblo-0.28 tar.gz http://downloads.sourceforge.net/liblo/liblo-0.28.tar.gz
## clang/OSX is picky about abs()  -Werror,-Wabsolute-value
patch -p1 << EOF
--- a/src/message.c	2015-11-17 17:12:15.000000000 +0100
+++ b/src/message.c	2015-11-17 17:13:28.000000000 +0100
@@ -997,6 +997,6 @@
     if (d != end) {
         fprintf(stderr,
                 "liblo warning: type and data do not match (off by %d) in message %p\n",
-                abs((char *) d - (char *) end), m);
+                abs((int)((char *) d - (char *) end)), m);
     }
 }
EOF
autoconfbuild --disable-shared --enable-static

################################################################################

src freetype-2.5.3 tar.gz http://download.savannah.gnu.org/releases/freetype/freetype-2.5.3.tar.gz
autoconfbuild --with-harfbuzz=no --with-png=no --with-bzip2=no

################################################################################

src fftw-3.3.4 tar.gz http://www.fftw.org/fftw-3.3.4.tar.gz
autoconfbuild --with-our-malloc --disable-mpi

################################################################################

src mxml-2.9 tar.gz http://www.msweet.org/files/project3/mxml-2.9.tar.gz
## DSOFLAGS ? which standard did they read?
DSOFLAGS="${OSXARCH}${GLOBAL_LDFLAGS:+ $GLOBAL_LDFLAGS}" \
autoconfbuild --disable-shared --enable-static
## compiling the self-test & doc fails with multi-arch, so work around this
make libmxml.a
make -i install TARGETS=""

################################################################################

## project with tar-ball name != unzipped folder
download fltk-1.3.3-source.tar.gz http://fltk.org/pub/fltk/1.3.3/fltk-1.3.3-source.tar.gz
cd ${BUILDD}
rm -rf fltk-1.3.3
tar xzf ${SRCDIR}/fltk-1.3.3-source.tar.gz
cd fltk-1.3.3
autoconfbuild

## stack built complete
touch $PREFIX/zyn_stack_complete

################################################################################
fi  ## NOSTACK
################################################################################



################################################################################
## check out zyn from git, keep a local reference to speed up future clones

#REPO_URL=git://github.com/fundamental/zynaddsubfx.git
REPO_URL=git://git.code.sf.net/p/zynaddsubfx/code

if test ! -d ${SRCDIR}/zynaddsubfx.git.reference; then
	git clone --mirror ${REPO_URL} ${SRCDIR}/zynaddsubfx.git.reference
fi

cd ${BUILDD}
git clone -b dpf-plugin --single-branch --reference ${SRCDIR}/zynaddsubfx.git.reference ${REPO_URL} zynaddsubfx || true

cd zynaddsubfx
git submodule update --init|| true

## git pull, unless locally modified
if git diff-files --quiet --ignore-submodules -- && git diff-index --cached --quiet HEAD --ignore-submodules --; then
	git pull || true
	git submodule update || true
fi

## version string for bundle
VERSION=`git describe --tags | sed 's/-g[a-f0-9]*$//'`
if test -z "$VERSION"; then
	echo "*** Cannot query version information."
	exit 1
fi

################################################################################
## Prepare application bundle dir (for make install)

PRODUCT_NAME="ZynAddSubFx"
APPNAME="${PRODUCT_NAME}.app"

RSRC_DIR="$this_script_dir"

export BUNDLEDIR=`mktemp -d -t bundle`
trap "rm -rf $BUNDLEDIR" EXIT

TARGET_BUILD_DIR="${BUNDLEDIR}/${APPNAME}/"
TARGET_CONTENTS="${TARGET_BUILD_DIR}Contents/"

mkdir -p ${TARGET_CONTENTS}MacOS
mkdir -p ${TARGET_CONTENTS}Frameworks

#######################################################################################
## finally, configure and build zynaddsubfx

rm -rf build
mkdir -p build; cd build
cmake -DCMAKE_INSTALL_PREFIX=/ \
	-DCMAKE_BUILD_TYPE="None" \
	-DCMAKE_OSX_ARCHITECTURES="$ARCHITECTURES" \
	-DCMAKE_C_FLAGS="-I${PREFIX}/include $GLOBAL_CFLAGS" \
	-DCMAKE_CXX_FLAGS="-I${PREFIX}/include $GLOBAL_CXXFLAGS" \
	-DCMAKE_EXE_LINKER_FLAGS="-L$PREFIX/lib $GLOBAL_LDFLAGS" \
	-DCMAKE_SKIP_BUILD_RPATH=ON \
	-DNoNeonPlease=ON \
	..
make
DESTDIR=${TARGET_CONTENTS} make install

#######################################################################################
## fixup 'make install' for OSX application bundle

mv -v ${TARGET_CONTENTS}bin/zynaddsubfx ${TARGET_CONTENTS}MacOS/zynaddsubfx-bin
mv ${TARGET_CONTENTS}bin/zynaddsubfx-ext-gui ${TARGET_CONTENTS}lib/lv2/ZynAddSubFX.lv2/

mv -v ${TARGET_CONTENTS}share ${TARGET_CONTENTS}/Resources

mv -v ${TARGET_CONTENTS}/Resources/zynaddsubfx/banks ${TARGET_CONTENTS}/Resources/
mv -v ${TARGET_CONTENTS}/Resources/zynaddsubfx/examples ${TARGET_CONTENTS}/Resources/

rmdir ${TARGET_CONTENTS}/Resources/zynaddsubfx/
rmdir ${TARGET_CONTENTS}bin

mv  -v ${TARGET_CONTENTS}lib/lv2 ${BUNDLEDIR}/
mv  -v ${TARGET_CONTENTS}lib/vst ${BUNDLEDIR}/
rmdir ${TARGET_CONTENTS}lib

#######################################################################################
## finish OSX application bundle

echo "APPL~~~~" > ${TARGET_CONTENTS}PkgInfo

cat > ${TARGET_CONTENTS}Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>${PRODUCT_NAME}</string>
	<key>CFBundleName</key>
	<string>${PRODUCT_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleSignature</key>
	<string>~~~~</string>
	<key>CFBundleVersion</key>
	<string>1.0</string>
	<key>CFBundleIconFile</key>
	<string>${PRODUCT_NAME}</string>
	<key>CSResourcesFileMapped</key>
	<true/>
</dict>
</plist>
EOF

## ... and add a wrapper-script that checks for jack

cat > "${TARGET_CONTENTS}MacOS/${PRODUCT_NAME}" << EOF
#!/bin/sh

if test ! -x /usr/local/bin/jackd -a ! -x /usr/bin/jackd ; then
  /usr/bin/osascript -e '
    tell application "Finder"
    display dialog "You do not have JACK installed. ${PRODUCT_NAME} will not run without it. See http://jackaudio.org/ for info." buttons["OK"]
    end tell'
  exit 1
fi

progname="\$0"
curdir=\`dirname "\${progname}"\`
progbase=\`basename "\$progname"\`
execname=\${curdir}/\${progbase}-bin

if test -x "\$execname"; then
  cd "\${curdir}"
  exec "\${execname}" -a
fi
EOF

chmod +x "${TARGET_CONTENTS}MacOS/${PRODUCT_NAME}"

## copy the application icon
cp -vi ${RSRC_DIR}/${PRODUCT_NAME}.icns ${TARGET_CONTENTS}/Resources


##############################################################################
## add dependencies..

echo "bundle libraries ..."
while [ true ] ; do
	missing=false
	for file in ${TARGET_CONTENTS}MacOS/* ${TARGET_CONTENTS}Frameworks/*; do
		set +e # grep may return 1
		if ! file $file | grep -qs Mach-O ; then
			continue;
		fi
		deps=`otool -arch all -L $file \
			| awk '{print $1}' \
			| egrep "$PREFIX" \
			| grep -v 'libjack\.' \
			| sort | uniq`
		set -e
		for dep in $deps ; do
			base=`basename $dep`
			if ! test -f ${TARGET_CONTENTS}Frameworks/$base; then
				cp -v $dep ${TARGET_CONTENTS}Frameworks/
				missing=true
			fi
		done
	done
	if test x$missing = xfalse ; then
		break
	fi
done

echo "update executables ..."
for exe in ${TARGET_CONTENTS}MacOS/*; do
	set +e # grep may return 1
	if ! file $exe | grep -qs Mach-O ; then
		continue
	fi
	changes=""
	libs=`otool -arch all -L $exe \
		| awk '{print $1}' \
		| egrep "$PREFIX" \
		| grep -v 'libjack\.' \
		| sort | uniq`
	set -e
	for lib in $libs; do
		base=`basename $lib`
		changes="$changes -change $lib @executable_path/../Frameworks/$base"
	done
	if test "x$changes" != "x" ; then
		install_name_tool $changes $exe
	fi
done

echo "update libraries ..."
for dylib in ${TARGET_CONTENTS}Frameworks/*.dylib ; do
	# skip symlinks
	if test -L $dylib ; then
		continue
	fi
	strip -SXx $dylib

	# change all the dependencies
	changes=""
	libs=`otool -arch all -L $dylib \
		| awk '{print $1}' \
		| egrep "$PREFIX" \
		| grep -v 'libjack\.' \
		| sort | uniq`

	for lib in $libs; do
		base=`basename $lib`
		changes="$changes -change $lib @executable_path/../Frameworks/$base"
	done

	if test "x$changes" != x ; then
		if  install_name_tool $changes $dylib ; then
			:
		else
			exit 1
		fi
	fi

	# now the change what the library thinks its own name is
	base=`basename $dylib`
	install_name_tool -id @executable_path/../Frameworks/$base $dylib
done

echo "..all bundled up."


##############################################################################
## all done. now roll a DMG

UC_DMG="${OUTDIR}${PRODUCT_NAME}-${VERSION}.dmg"

DMGBACKGROUND=${RSRC_DIR}/dmgbg.png
VOLNAME=$PRODUCT_NAME-${VERSION}
EXTRA_SPACE_MB=5


DMGMEGABYTES=$[ `du -sck "${BUNDLEDIR}" | tail -n 1 | cut -f 1` * 1024 / 1048576 + $EXTRA_SPACE_MB ]
echo "DMG MB = " $DMGMEGABYTES

MNTPATH=`mktemp -d -t mntpath`
TMPDMG=`mktemp -t tmpdmg`
ICNSTMP=`mktemp -t appicon`

trap "rm -rf $MNTPATH $TMPDMG ${TMPDMG}.dmg $ICNSTMP $BUNDLEDIR" EXIT

rm -f $UC_DMG "$TMPDMG" "${TMPDMG}.dmg" "$ICNSTMP ${ICNSTMP}.icns ${ICNSTMP}.rsrc"
rm -rf "$MNTPATH"
mkdir -p "$MNTPATH"

TMPDMG="${TMPDMG}.dmg"

hdiutil create -megabytes $DMGMEGABYTES "$TMPDMG"
DiskDevice=$(hdid -nomount "$TMPDMG" | grep Apple_HFS | cut -f 1 -d ' ')
newfs_hfs -v "${VOLNAME}" "${DiskDevice}"
mount -t hfs -o nobrowse "${DiskDevice}" "${MNTPATH}"

cp -a "${TARGET_BUILD_DIR}" "${MNTPATH}/${APPNAME}"
cp -a "${BUNDLEDIR}/lv2" "${MNTPATH}/"
cp -a "${BUNDLEDIR}/vst" "${MNTPATH}/"

mkdir "${MNTPATH}/.background"
cp -vi ${DMGBACKGROUND} "${MNTPATH}/.background/dmgbg.png"

echo "setting DMG background ..."

if test $(sw_vers -productVersion | cut -d '.' -f 2) -lt 9; then
	# OSX ..10.8.X
	DISKNAME=${VOLNAME}
else
	# OSX 10.9.X and later
	DISKNAME=`basename "${MNTPATH}"`
fi

echo '
   tell application "Finder"
     tell disk "'${DISKNAME}'"
	   open
	   delay 1
	   set current view of container window to icon view
	   set toolbar visible of container window to false
	   set statusbar visible of container window to false
	   set the bounds of container window to {400, 200, 800, 580}
	   set theViewOptions to the icon view options of container window
	   set arrangement of theViewOptions to not arranged
	   set icon size of theViewOptions to 64
	   set background picture of theViewOptions to file ".background:dmgbg.png"
	   make new alias file at container window to POSIX file "/Applications" with properties {name:"Applications"}
	   set position of item "'${APPNAME}'" of container window to {100, 100}
	   set position of item "Applications" of container window to {310, 100}
	   set position of item "lv2" of container window to {100, 260}
	   set position of item "vst" of container window to {310, 260}
	   close
	   open
	   update without registering applications
	   delay 5
	   eject
     end tell
   end tell
' | osascript || {
	echo "Failed to set background/arrange icons"
	umount "${DiskDevice}" || true
	hdiutil eject "${DiskDevice}"
	exit 1
}

set +e
chmod -Rf go-w "${MNTPATH}"
set -e
sync

echo "unmounting the disk image ..."
## Umount the image ('eject' above may already have done that)
umount "${DiskDevice}" || true
hdiutil eject "${DiskDevice}" || true

## Create a read-only version, use zlib compression
echo "compressing Image ..."
hdiutil convert -format UDZO "${TMPDMG}" -imagekey zlib-level=9 -o "${UC_DMG}"
## Delete the temporary files
rm "$TMPDMG"
rm -rf "$MNTPATH"

echo "setting file icon ..."

cp ${RSRC_DIR}/${PRODUCT_NAME}.icns ${ICNSTMP}.icns
sips -i ${ICNSTMP}.icns
DeRez -only icns ${ICNSTMP}.icns > ${ICNSTMP}.rsrc
Rez -append ${ICNSTMP}.rsrc -o "$UC_DMG"
SetFile -a C "$UC_DMG"

rm ${ICNSTMP}.icns ${ICNSTMP}.rsrc
rm -rf $BUNDLEDIR

echo
echo "packaging succeeded:"
ls -l "$UC_DMG"
echo "Done."
