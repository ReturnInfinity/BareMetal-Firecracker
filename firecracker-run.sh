#!/bin/sh
set -eu

SOCKET=/run/firecracker.socket
KERNEL="$PWD/sys/baremetal.elf"
DISK="$PWD/disk.img"

# Remove stale socket
sudo rm -f "$SOCKET"

# Configure and start the VM in the background once the socket appears.
# Firecracker must run in the foreground to keep full stdin/stdout access
# for the serial console — backgrounding it cuts off stdin.
(
	while [ ! -S "$SOCKET" ]; do
		sleep 0.05
	done
	sudo chmod 666 "$SOCKET"

	curl -sf --unix-socket "$SOCKET" -X PUT 'http://localhost/boot-source' \
		-H 'Content-Type: application/json' \
		-d "{ \"kernel_image_path\": \"$KERNEL\", \"boot_args\": \"\" }" > /dev/null

	curl -sf --unix-socket "$SOCKET" -X PUT 'http://localhost/machine-config' \
		-H 'Content-Type: application/json' \
		-d '{ "vcpu_count": 1, "mem_size_mib": 4 }' > /dev/null

	curl -sf --unix-socket "$SOCKET" -X PUT 'http://localhost/network-interfaces/eth0' \
		-H 'Content-Type: application/json' \
		-d '{ "iface_id": "eth0", "host_dev_name": "tap0", "guest_mac": "02:FC:AB:CD:EF:01" }' > /dev/null

	curl -sf --unix-socket "$SOCKET" -X PUT 'http://localhost/drives/rootfs' \
		-H 'Content-Type: application/json' \
		-d "{ \"drive_id\": \"rootfs\", \"path_on_host\": \"$DISK\", \"is_root_device\": true, \"is_read_only\": false }" > /dev/null

	curl -sf --unix-socket "$SOCKET" -X PUT 'http://localhost/actions' \
		-H 'Content-Type: application/json' \
		-d '{ "action_type": "InstanceStart" }' > /dev/null
) &

# Run Firecracker in the foreground so the serial console has full stdin/stdout
exec sudo firecracker --api-sock "$SOCKET" --log-path /dev/null
