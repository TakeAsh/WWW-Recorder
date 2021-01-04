#!/bin/bash
# WIP; Net-Recorder services are blocked by SELinux.

SCRIPT_DIR=$(cd $(dirname $0); pwd)
UNIT_DIR=/usr/lib/systemd/system

pushd ${UNIT_DIR}
for file in ${SCRIPT_DIR}/NetRecorder-*
do
  ln -s ${file}
done
chcon -t systemd_unit_file_t NetRecorder-*
systemctl daemon-reload
cd ${SCRIPT_DIR}
systemctl enable *.service
systemctl enable *.timer
systemctl start *.timer
popd
