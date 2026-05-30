#!/bin/sh
set -eu

SOCKET=/run/firecracker.socket

curl --unix-socket "$SOCKET" -i -X PUT 'http://localhost/actions' \
	-H 'Content-Type: application/json' \
	-d '{ "action_type": "SendCtrlAltDel" }'
