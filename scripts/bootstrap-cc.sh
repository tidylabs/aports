#!/bin/sh

set -e

: ${SUDO=$([ $(id -u) -eq 0 ] || command -v doas || command -v sudo)}

# normalize architecture name
[ -n "${1}" ] && TARGETARCH="${1}"
case "${TARGETARCH}" in
	"amd64") TARGETARCH="x86_64" ;;
	"arm64") TARGETARCH="aarch64" ;;
esac
export CTARGET="${TARGETARCH}"

# get abuild configurables
[ -e /usr/share/abuild/functions.sh ] || die "abuild not found"
. /usr/share/abuild/functions.sh
[ -z "${CBUILDROOT}" ] && die "CBUILDROOT not set for '${TARGETARCH}'"
[ -e "${APORTSDIR}/main/build-base" ] || die "Unable to deduce aports checkout"

echo "Creating sysroot in ${CBUILDROOT}"

# initalize sysroot
${SUDO} apk add \
	--quiet \
	--initdb \
	--arch "${CTARGET_ARCH}" \
	--root "${CBUILDROOT}"

# copy repositories
${SUDO} cp -a /etc/apk/repositories "${CBUILDROOT}/etc/apk/."

# copy keys
${SUDO} cp -aR /etc/apk/keys "${CBUILDROOT}/etc/apk/."

# add alpine-keys (WARNING: --allow-untrusted)
${SUDO} apk add \
	--quiet \
	--arch "${CTARGET_ARCH}" \
	--root "${CBUILDROOT}" \
	--allow-untrusted \
	alpine-keys

echo "Building cross-compiler"

# build and install cross binutils (--with-sysroot)
APKBUILD="${APORTSDIR}/main/binutils/APKBUILD" \
BOOTSTRAP=nobase \
abuild -F -r -k

# full cross GCC
APKBUILD="${APORTSDIR}/main/gcc/APKBUILD" \
BOOTSTRAP=nobase \
EXTRADEPENDS_TARGET="musl-dev libucontext-dev" \
abuild -F -r -k

# cross build-base
APKBUILD="${APORTSDIR}/main/build-base/APKBUILD" \
BOOTSTRAP=nobase \
abuild -F -r -k

# add links for ccache
if [ -e /usr/lib/ccache/bin ]; then
	echo "Linking cross-compiler (for ccache)"
	for compiler in gcc g++ cpp c++; do
		${SUDO} ln -sfv /usr/bin/ccache \
			"/usr/lib/ccache/bin/${CTARGET}-${compiler}"
	done
fi

cat <<-EOF
To install the cross-compiler use \
'apk add --repository "${REPODEST}main" build-base-${CTARGET_ARCH}'
EOF

cat <<-EOF
To build Alpine packages for '${CTARGET_ARCH}' use \
'EXTRADEPENDS_HOST="libgcc libstdc++ musl-dev" \
CHOST="${CTARGET_ARCH}" abuild -r'
EOF

cat <<-EOF
To explicitly install cross-build libraries use \
'apk --arch "${CTARGET_ARCH}" --root "${CBUILDROOT}" add --no-scripts <pkg>'
EOF
