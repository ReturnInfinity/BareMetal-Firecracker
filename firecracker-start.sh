#!/bin/sh
set -eu

SOCKET=/run/firecracker.socket
KERNEL="$PWD/sys/baremetal.elf"
DISK="$PWD/disk.img"

sudo chmod 777 "$SOCKET"

curl --unix-socket "$SOCKET" -i -X PUT 'http://localhost/boot-source' \
	-H 'Content-Type: application/json' \
	-d "{ \"kernel_image_path\": \"$KERNEL\", \"boot_args\": \"\" }"

curl --unix-socket "$SOCKET" -i -X PUT 'http://localhost/machine-config' \
	-H 'Content-Type: application/json' \
	-d '{ "vcpu_count": 1, "mem_size_mib": 4 }'

curl --unix-socket "$SOCKET" -i -X PUT 'http://localhost/network-interfaces/eth0' \
	-H 'Content-Type: application/json' \
	-d '{ "iface_id": "eth0", "host_dev_name": "tap0", "guest_mac": "02:FC:AB:CD:EF:01" }'

curl --unix-socket "$SOCKET" -i -X PUT 'http://localhost/drives/rootfs' \
	-H 'Content-Type: application/json' \
	-d "{ \"drive_id\": \"rootfs\", \"path_on_host\": \"$DISK\", \"is_root_device\": true, \"is_read_only\": false }"

curl --unix-socket "$SOCKET" -i -X PUT 'http://localhost/actions' \
	-H 'Content-Type: application/json' \
	-d '{ "action_type": "InstanceStart" }'
