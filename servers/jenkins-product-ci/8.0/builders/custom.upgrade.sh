#!/bin/bash

set -ex

export PATH=/bin:/usr/bin:/sbin:/usr/sbin:${PATH}

PROD_VER=$(grep 'PRODUCT_VERSION:=' config.mk | cut -d= -f2)

export ISO_NAME="fuel-gerrit-${PROD_VER}-${BUILD_NUMBER}-${BUILD_ID}"
export UPGRADE_TARBALL_NAME="fuel-gerrit-${PROD_VER}-upgrade-${BUILD_NUMBER}-${BUILD_ID}"

export BUILD_DIR="${WORKSPACE}/../tmp/${JOB_NAME}/build"
export LOCAL_MIRROR="${WORKSPACE}/../tmp/${JOB_NAME}/local_mirror"

export ARTS_DIR="${WORKSPACE}/artifacts"
rm -rf "${ARTS_DIR}"

export DEPS_DIR="${BUILD_DIR}/deps"
rm -rf "${DEPS_DIR}"

# Checking gerrit commits for fuel-main
if [ "${FUELMAIN_COMMIT}" != "master" ] ; then
    git checkout "${FUELMAIN_COMMIT}"
fi

# Checking gerrit commits for fuel-main
if [ "${fuelmain_gerrit_commit}" != "none" ] ; then
  for commit in ${fuelmain_gerrit_commit} ; do
    git fetch https://review.openstack.org/openstack/fuel-main "${commit}" && git cherry-pick FETCH_HEAD || false
  done
fi

export NAILGUN_GERRIT_COMMIT="${nailgun_gerrit_commit}"
export ASTUTE_GERRIT_COMMIT="${astute_gerrit_commit}"
export OSTF_GERRIT_COMMIT="${ostf_gerrit_commit}"
export FUELLIB_GERRIT_COMMIT="${fuellib_gerrit_commit}"
export PYTHON_FUELCLIENT_GERRIT_COMMIT="${python_fuelclient_gerrit_commit}"
export FUEL_AGENT_GERRIT_COMMIT="${fuel_agent_gerrit_commit}"
export FUEL_NAILGUN_AGENT_GERRIT_COMMIT="${fuel_nailgun_agent_gerrit_commit}"
export CREATEMIRROR_GERRIT_COMMIT="${createmirror_gerrit_commit}"
export FUELMENU_GERRIT_COMMIT="${fuelmenu_gerrit_commit}"

######## Get node location to choose closer mirror ###############
# We are building everything with USE_MIRROR=none

# Let's try use closest perestroika mirror location
LOCATION_FACT=$(facter --external-dir /etc/facter/facts.d/ location)
LOCATION=${LOCATION_FACT:-msk}

case "${LOCATION}" in
    srt)
        LATEST_MIRROR_ID_URL=http://osci-mirror-srt.srt.mirantis.net
        ;;
    msk)
        LATEST_MIRROR_ID_URL=http://osci-mirror-msk.msk.mirantis.net
        ;;
    hrk)
        LATEST_MIRROR_ID_URL=http://osci-mirror-kha.kha.mirantis.net
        ;;
    poz|bud|bud-ext|cz)
        LATEST_MIRROR_ID_URL=http://mirror.seed-cz1.fuel-infra.org
        ;;
    mnv)
        LATEST_MIRROR_ID_URL=http://mirror.seed-us1.fuel-infra.org
        ;;
    *)
        LATEST_MIRROR_ID_URL=http://osci-mirror-msk.msk.mirantis.net
esac

# define closest stable ubuntu mirror snapshot
LATEST_TARGET_UBUNTU=$(curl -sSf "${LATEST_MIRROR_ID_URL}/mos-repos/ubuntu/8.0.target.txt" | head -1)
# since in fuel-main MIRROR_MOS_UBUNTU?=perestroika-repo-tst.infra.mirantis.net, we need to remove http://
export MIRROR_MOS_UBUNTU="${LATEST_MIRROR_ID_URL#http://}"
export MIRROR_MOS_UBUNTU_ROOT="/mos-repos/ubuntu/${LATEST_TARGET_UBUNTU}"

# define closest stable centos mirror snapshot
# http://perestroika-repo-tst.infra.mirantis.net/mos-repos/centos/$(PRODUCT_NAME)$(PRODUCT_VERSION)-centos6-fuel/os/x86_64
LATEST_TARGET_CENTOS=$(curl -sSf "${LATEST_MIRROR_ID_URL}/mos-repos/centos/mos8.0-centos6-fuel/os.target.txt" | head -1)
export MIRROR_FUEL="${LATEST_MIRROR_ID_URL}/mos-repos/centos/mos8.0-centos6-fuel/${LATEST_TARGET_CENTOS}/x86_64"

echo "Using mirror: ${USE_MIRROR} with ${MIRROR_MOS_UBUNTU}${MIRROR_MOS_UBUNTU_ROOT} and ${MIRROR_FUEL}"


process_artifacts() {
    local ARTIFACT="$1"
    test -f "$ARTIFACT" || return 1

    local HOSTNAME=`hostname -f`
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
    local MAGNET_LINK=`seedclient.py -v -u -f "$LOCAL_STORAGE"/"$ARTIFACT" --tracker-url="${TRACKER_URL}" --http-root="${HTTP_ROOT}" || true`
    local STORAGES=($(echo "${HTTP_ROOT}" | tr ',' '\n'))
    local HTTP_LINK="${STORAGES}/${ARTIFACT}"
    local HTTP_TORRENT="${HTTP_LINK}.torrent"

    cat > $ARTIFACT.data.txt <<EOF
ARTIFACT=$ARTIFACT
HTTP_LINK=$HTTP_LINK
HTTP_TORRENT=$HTTP_TORRENT
MAGNET_LINK=$MAGNET_LINK
EOF

    cat >$ARTIFACT.data.html <<EOF
<h1>$ARTIFACT</h1>
<a href=\"$HTTP_LINK\">HTTP link</a><br>
<a href=\"$HTTP_TORRENT\">Torrent file</a><br>
<a href=\"$MAGNET_LINK\">Magnet link</a><br>
EOF

}

#########################################

echo "STEP 0. Clean before start"
make deep_clean

#########################################

echo "STEP 1. Make everything"
make ${make_args} iso upgrade-lrzip version-yaml openstack-yaml

#########################################

echo "STEP 2. Publish everything"

export LOCAL_STORAGE='/var/www/fuelweb-iso'
export HTTP_ROOT="http://`hostname -f`/fuelweb-iso"
export TRACKER_URL='http://tracker01-bud.infra.mirantis.net:8080/announce,http://tracker01-mnv.infra.mirantis.net:8080/announce,http://tracker01-msk.infra.mirantis.net:8080/announce'

cd "${ARTS_DIR}"
for artifact in $(ls fuel-*)
do
  begin=`date +%s`
  process_artifacts $artifact $LOCAL_STORAGE $TRACKER_URL $HTTP_ROOT
  echo "Time taken: $((`date +%s` - $begin))"
done

cd "${WORKSPACE}"

echo FUELMAIN_GERRIT_COMMIT="${fuelmain_gerrit_commit}" > "${ARTS_DIR}/gerrit_commits.txt"
echo NAILGUN_GERRIT_COMMIT="${nailgun_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo ASTUTE_GERRIT_COMMIT="${astute_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo OSTF_GERRIT_COMMIT="${ostf_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo FUELLIB_GERRIT_COMMIT="${fuellib_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo PYTHON_FUELCLIENT_GERRIT_COMMIT="${python_fuelclient_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo FUEL_AGENT_GERRIT_COMMIT="${fuel_agent_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo FUEL_NAILGUN_AGENT_GERRIT_COMMIT="${fuel_nailgun_agent_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo CREATEMIRROR_GERRIT_COMMIT="${createmirror_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"
echo FUELMENU_GERRIT_COMMIT="${fuelmenu_gerrit_commit}" >> "${ARTS_DIR}/gerrit_commits.txt"

cp "${LOCAL_MIRROR}"/*changelog "${ARTS_DIR}/" || true
cp "${BUILD_DIR}/iso/isoroot/version.yaml" "${WORKSPACE}/version.yaml.txt" || true
(cd "${BUILD_DIR}/iso/isoroot" && find . | sed -s 's/\.\///') > "${WORKSPACE}/listing.txt" || true

grep MAGNET_LINK "${ARTS_DIR}"/fuel-*.iso.data.txt > "${WORKSPACE}/magnet_link.txt"
grep MAGNET_LINK "${ARTS_DIR}"/fuel-*upgrade-*.data.txt > "${WORKSPACE}/upgrade_magnet_link.txt"

#########################################

echo "STEP 3. Generate build description"

UPGRADE_MAGNET_LINK=$(grep MAGNET_LINK "${ARTS_DIR}"/*upgrade-*.data.txt | sed 's/MAGNET_LINK=//')
UPGRADE_HTTP_LINK=$(grep HTTP_LINK "${ARTS_DIR}"/*upgrade-*.data.txt | sed 's/HTTP_LINK=//')
UPGRADE_HTTP_TORRENT=$(grep HTTP_TORRENT "${ARTS_DIR}"/*upgrade-*.data.txt | sed 's/HTTP_TORRENT=//')

echo "<a href=${UPGRADE_HTTP_LINK}>UPGD download link</a> <a href=${UPGRADE_HTTP_TORRENT}>UPGD torrent link</a><br>${UPGRADE_MAGNET_LINK}<br>"

echo "BUILD FINISHED."
