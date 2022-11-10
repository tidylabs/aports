#!/bin/sh

set -e

: ${SUDO=$(command -v doas || command -v sudo || echo doas)}

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

if [ ! -d "${CBUILDROOT}" ]; then
    echo "Creating sysroot in ${CBUILDROOT}"

    # initalize sysroot
    abuild-apk add \
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
fi

echo "Building cross-compiler"

# build and install cross binutils (--with-sysroot)
APKBUILD="${APORTSDIR}/main/binutils/APKBUILD" \
BOOTSTRAP=nobase \
abuild -F -r

# full cross GCC
APKBUILD="${APORTSDIR}/main/gcc/APKBUILD" \
BOOTSTRAP=nobase \
EXTRADEPENDS_TARGET="musl-dev" \
LANG_ADA=false \
abuild -F -r

# cross build-base
APKBUILD="${APORTSDIR}/main/build-base/APKBUILD" \
BOOTSTRAP=nobase \
abuild -F -r

# add links for ccache
if [ -e /usr/lib/ccache/bin ]; then
    echo "Linking cross-compiler (for ccache)"
    for link in gcc g++ cpp c++; do
        ${SUDO} ln -sfv /usr/bin/ccache "/usr/lib/ccache/bin/${CTARGET}-${link}"
    done
fi

echo "To install the cross-compiler use 'apk add --repository \"${REPODEST}main\" build-base-${CTARGET_ARCH}'"
echo "To build Alpine packages for '${CTARGET_ARCH}' use 'EXTRADEPENDS_HOST=\"libgcc libstdc++ musl-dev\" CHOST=\"${CTARGET_ARCH}\" abuild -r'"
echo "To explicitly install cross-build libraries use 'apk --arch \"${CTARGET_ARCH}\" --root \"${CBUILDROOT}\" add --no-scripts <pkg>'"
