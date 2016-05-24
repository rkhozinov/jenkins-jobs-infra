#!/bin/bash
#
#   :mod: `build-mos-docs.sh` -- this script  builds  OpenStack documentation
#        for active branches and publishes it to ``http://docs.mirantis.com``
#   =========================================================================
#
#   .. module:: build-mos-docs.sh
#       :platform: Unix
#       :synopsys: this script creates OpenStack documentation for all active
#                  active branches and publishes it to dosc.mirantis.com
#   .. versionadded:: MOS-8.0
#   .. versionchanged:: MOS-9.0
#   .. author:: Lesya Novaselskaya <onovaselskaya@mirantis.com>
#
#
#   .. envvar::
#       :var WORKSPACE: build starter location, defaults to ``.``
#       :var VENV: build specific virtual environment path (deployed)
#       :var BRANCH_ID: Fuel QA build branch (deployed)
#       :var GERRIT_BRANCH: Fuel QA internal branch
#       :var DOCS_HOST: credentials used for publishing, default to
#                       ``docs@docs.fuel-infra.org`` (deployed)
#       :var DOCS_ROOT: path to documentation directory (deployed)
#
#   .. requirements::
#       * valid configuration YAML file: build-fuel-qa-docs.yaml
#
#   .. seealso::
#
#   .. warnings::

set -ex

echo "Description string: ${GERRIT_BRANCH}"

VENV="${WORKSPACE}_VENV"

virtualenv "${VENV}"
source "${VENV}/bin/activate" || exit 1

pip install -r requirements.txt

make clean html pdf

deactivate

# Publishing
# DOCS_HOST and DOCS_ROOT variables are injected
ssh "${DOCS_HOST}" "mkdir -p \${DOCS_ROOT}"

BRANCH_ID="${GERRIT_BRANCH##*/}"

DOCS_PATH="${DOCS_HOST}:${DOCS_ROOT}/fuel-${BRANCH_ID}"

rsync -rv --delete --exclude pdf/ _build/html/ "${DOCS_PATH}"
rsync -rv _build/pdf/ "${DOCS_PATH}/pdf/"
