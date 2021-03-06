#!/bin/bash

set -ex

JENKINS_TEST_BUILD_URL="${JENKINS_URL}job/${TEST_JOB}/lastSuccessfulBuild/"
ISO_BUILD_URL="$(curl -fsS ${JENKINS_TEST_BUILD_URL}artifact/iso_build_url.txt \
        | awk -F '[ =]' '{print $NF}')"

echo "Description string: ISO <a href=\"$ISO_BUILD_URL\">${ISO_BUILD_URL##*[a-z]/}</a>"

curl -O "${JENKINS_TEST_BUILD_URL}artifact/ubuntu_mirror_id.txt"
curl -O "${ISO_BUILD_URL}artifact/artifacts/magnet_link.txt"

cat magnet_link.txt > links.txt

cat ubuntu_mirror_id.txt >> links.txt
