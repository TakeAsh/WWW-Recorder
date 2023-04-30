#!/bin/bash

SCRIPT_DIR=$(cd $(dirname $0); pwd)
UNIT_DIR=/usr/lib/systemd/system

pushd ${SCRIPT_DIR}
systemctl stop *.timer
systemctl stop *.service
systemctl disable *.timer
systemctl disable *.service
rm ${UNIT_DIR}/WwwRecorder-*
popd
