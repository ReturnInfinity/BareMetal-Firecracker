#!/bin/sh
set -eu

curl --unix-socket /run/firecracker.socket -i -X PUT 'http://localhost/actions' -H 'Content-Type: application/json' -d '{ "action_type": "SendCtrlAltDel" }'
