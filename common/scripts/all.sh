#!/bin/bash

set -ex

export PATH=/bin:/usr/bin:/sbin:/usr/sbin:${PATH}

PROD_VER=$(grep '^PRODUCT_VERSION' config.mk | cut -d= -f2)

export PRODUCT_VERSION="$PROD_VER"
export ISO_NAME="fuel-${ISO_ID}-${BUILD_NUMBER}-${BUILD_TIMESTAMP}"

export BUILD_DIR="${WORKSPACE}/../tmp/${JOB_NAME}/build"
export LOCAL_MIRROR="${WORKSPACE}/../tmp/${JOB_NAME}/local_mirror"

export ARTS_DIR="${WORKSPACE}/artifacts"
rm -rf "${ARTS_DIR}"

######## Get node location to choose closer mirror ###############
# Let's try use closest perestroika mirror location

LOCATION_FACT=$(facter --external-dir /etc/facter/facts.d/ location)
LOCATION=${LOCATION_FACT:-bud}

case "${LOCATION}" in
    srt)
        CLOSEST_MIRROR_URL="http://osci-mirror-srt.srt.mirantis.net"
        ;;
    msk)
        CLOSEST_MIRROR_URL="http://osci-mirror-msk.msk.mirantis.net"
        ;;
    hrk)
        CLOSEST_MIRROR_URL="http://osci-mirror-kha.kha.mirantis.net"
        ;;
    poz|bud|bud-ext|cz)
        CLOSEST_MIRROR_URL="http://mirror.seed-cz1.fuel-infra.org"
        ;;
    scc)
        CLOSEST_MIRROR_URL="http://mirror.seed-us1.fuel-infra.org"
        ;;
    *)
        CLOSEST_MIRROR_URL="http://osci-mirror-msk.msk.mirantis.net"
esac

export MIRROR_UBUNTU="${CLOSEST_MIRROR_URL#http://}" # Upstream ubuntu mirror

if test -z "$MIRROR_MOS_UBUNTU"; then
    export MIRROR_MOS_UBUNTU="${CLOSEST_MIRROR_URL#http://}"
fi

# define closest stable ubuntu mirror snapshot
LATEST_TARGET_UBUNTU=$(curl -sSf "http://${MIRROR_MOS_UBUNTU}/${MOS_UBUNTU_ROOT}/${MOS_UBUNTU_TARGET}" | head -1)

export MIRROR_MOS_UBUNTU_ROOT="${MOS_UBUNTU_ROOT}/${LATEST_TARGET_UBUNTU}"

# define closest stable centos mirror snapshot
LATEST_TARGET_CENTOS=$(curl -sSf "${CLOSEST_MIRROR_URL}/${MOS_CENTOS_ROOT}/os.target.txt" | head -1)

export MIRROR_FUEL="${CLOSEST_MIRROR_URL}/${MOS_CENTOS_ROOT}/${LATEST_TARGET_CENTOS}/x86_64"

echo "Using mirror: ${USE_MIRROR} with ${MIRROR_MOS_UBUNTU}${MIRROR_MOS_UBUNTU_ROOT} and ${MIRROR_FUEL}"

process_artifacts() {
    local ARTIFACT="$1"
    test -f "$ARTIFACT" || return 1

    local HOSTNAME=$(hostname -f)
    local LOCAL_STORAGE="$2"
    local TRACKER_URL="$3"
    local HTTP_ROOT="$4"

    echo "MD5SUM is:"
    md5sum $ARTIFACT

    echo "SHA1SUM is:"
    sha1sum $ARTIFACT

    mkdir -p $LOCAL_STORAGE
    mv $ARTIFACT $LOCAL_STORAGE

    # seedclient.py comes from python-seed devops package
    local MAGNET_LINK=$(seedclient.py -v -u -f "$LOCAL_STORAGE"/"$ARTIFACT" --tracker-url="${TRACKER_URL}" --http-root="${HTTP_ROOT}" || true)
    local STORAGES=($(echo "${HTTP_ROOT}" | tr ',' '\n'))
    local HTTP_LINK="${STORAGES}/${ARTIFACT}"
    local HTTP_TORRENT="${HTTP_LINK}.torrent"

    cat > $ARTIFACT.data.txt <<EOF
ARTIFACT=$ARTIFACT
HTTP_LINK=$HTTP_LINK
HTTP_TORRENT=$HTTP_TORRENT
MAGNET_LINK=$MAGNET_LINK
EOF

}

#########################################

echo "STEP 0. Clean before start"
make deep_clean

rm -rf /var/tmp/yum-${USER}-*

#########################################

echo "STEP 1. Make everything"

make $make_args iso listing

#########################################

echo "STEP 2. Publish everything"

export LOCAL_STORAGE='/var/www/fuelweb-iso'
export HTTP_ROOT="http://$(hostname -f)/fuelweb-iso"
export TRACKER_URL='http://tracker01-bud.infra.mirantis.net:8080/announce,http://tracker01-scc.infra.mirantis.net:8080/announce,http://tracker01-msk.infra.mirantis.net:8080/announce'

cd "${ARTS_DIR}"
for artifact in $(ls fuel-*)
do
  process_artifacts $artifact $LOCAL_STORAGE $TRACKER_URL $HTTP_ROOT
done

cp "${LOCAL_MIRROR}"/*changelog "${ARTS_DIR}/" || true
cp "${BUILD_DIR}/listing-build.txt" "${ARTS_DIR}/listing-build.txt" || true
cp "${BUILD_DIR}/listing-local-mirror.txt" "${ARTS_DIR}/listing-local-mirror.txt" || true
cp "${BUILD_DIR}/listing-package-changelog.txt" "${ARTS_DIR}/listing-package-changelog.txt" || true
(cd "${BUILD_DIR}/iso/isoroot" && find . | sed -s 's/\.\///') > "${ARTS_DIR}/listing.txt" || true

grep MAGNET_LINK "${ARTS_DIR}"/*iso.data.txt > "${ARTS_DIR}/magnet_link.txt"

# Generate build description
ISO_MAGNET_LINK=$(grep MAGNET_LINK "${ARTS_DIR}"/*iso.data.txt | sed 's/MAGNET_LINK=//')
ISO_HTTP_LINK=$(grep HTTP_LINK "${ARTS_DIR}"/*iso.data.txt | sed 's/HTTP_LINK=//')
ISO_HTTP_TORRENT=$(grep HTTP_TORRENT "${ARTS_DIR}"/*iso.data.txt | sed 's/HTTP_TORRENT=//')

echo "<a href=${ISO_HTTP_LINK}>ISO download link</a> <a href=${ISO_HTTP_TORRENT}>ISO torrent link</a><br>${ISO_MAGNET_LINK}<br>"

#########################################

echo "STEP 3. Clean after build"

cd ${WORKSPACE}

make deep_clean

#########################################