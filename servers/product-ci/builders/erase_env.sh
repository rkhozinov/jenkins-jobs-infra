#!/bin/bash
set -ex

source /home/jenkins/venv-nailgun-tests/bin/activate

ENV_NAME=$ENV_PREFIX.$BUILD_NUMBER.$BUILD_ID
ENV_NAME=${ENV_NAME:0:68}
dos.py erase $ENV_NAME
