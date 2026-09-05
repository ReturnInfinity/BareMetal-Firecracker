#!/bin/sh
# baremetal.sh - Manage a BareMetal Firecracker VM
#
# Usage: ./baremetal.sh <command> [args]
#
# Requires the current user to be in the 'kvm' group (one-time setup):
#   sudo usermod -aG kvm $USER   # then log out and back in
#
# Commands:
#	start		Configure and start the VM (sets up kernel, disk, network, and launches instance)
#	status		Check if the VM is currently running
#	send <text>	Send a line of text to the VM serial console followed by Enter
#	output		Print VM serial console output since last run
#	attach		Attach to the interactive screen session for the VM console
#	stop		Send Ctrl+Alt+Del to gracefully shut down the VM
#	help		Display help info
#
# Configuration (edit variables below):
#	SOCKET		Unix socket path used by the Firecracker API
#	KERNEL		Path to the BareMetal ELF kernel image
#	DISK		Path to the disk image
#	MEMSIZE		VM memory size in MiB
#	DISKSIZE	Size of the disk image, created on first start (e.g. 512M)
#	SESSION		Screen session name
#	VMLOG		Path to the VM serial console log file
#	VMLOGPOS	Path to the output read-position tracking file
#	FCLOG		Path to the firecracker log file
set -eu

SOCKET=/tmp/firecracker.socket
KERNEL="$PWD/sys/baremetal.elf"
DISK="$PWD/disk.img"
MEMSIZE=4 # As of last webserver.py test Python needed at least 28MiB
DISKSIZE=512M
SESSION=fc-vm
FCLOG="/tmp/fc.log"
VMLOG=/tmp/fc-vm.log
VMLOGPOS=/tmp/fc-vm.log.pos

# Prepare arguments
cmd="${1:-}" # first argument is the subcommand (default: empty)
[ "$#" -gt 0 ] && shift # remove subcommand so "$@" holds remaining args

case "$cmd" in
	start)
		rm -f "$SOCKET"
		rm -f "$FCLOG"
		rm -f "$VMLOG"
		rm -f "$VMLOGPOS"

		# Create the disk image if it doesn't already exist -- a plain
		# zeroed (sparse) file, not an ext2 filesystem: BMFS (see
		# BareMetal-AppPort/port/bmfs.c) treats this as raw sectors it
		# lays its own superblock/directory table/file data across
		# directly, with no filesystem of its own underneath.
		# Formatting it with mkfs.ext2 would leave non-zero ext2
		# metadata sitting in the exact sectors BMFS uses for its own
		# superblock/directory table, which BMFS then misreads as
		# pre-existing (garbage) directory entries -- corrupting block
		# allocation for the first file any app creates.
		if [ ! -f "$DISK" ]; then
			echo "Creating $DISKSIZE disk image at $DISK"
			truncate -s "$DISKSIZE" "$DISK"
		fi

		# Kill any leftover session from a previous run
		screen -S "$SESSION" -X quit > /dev/null 2>&1 || true

		# Start Firecracker in a detached screen session with output logging
		screen -L -Logfile "$VMLOG" -dmS "$SESSION" \
			firecracker --api-sock "$SOCKET" --log-path "$FCLOG"

		# Flush screen log immediately instead of the default 10s interval
		screen -S "$SESSION" -X logfile flush 0

		# Wait for socket
		while [ ! -S "$SOCKET" ]; do sleep 0.05; done

		# Set Firecracker kernel and boot args
		boot_args=""
		[ "$#" -gt 0 ] && boot_args="args=\`$*\`"
		curl -sf --unix-socket "$SOCKET" -X PUT 'http://localhost/boot-source' \
			-H 'Content-Type: application/json' \
			-d "{ \"kernel_image_path\": \"$KERNEL\", \"boot_args\": \"$boot_args\" }" > /dev/null

		# Set Firecracker CPU and MEM
		curl -sf --unix-socket "$SOCKET" -X PUT 'http://localhost/machine-config' \
			-H 'Content-Type: application/json' \
			-d "{ \"vcpu_count\": 1, \"mem_size_mib\": $MEMSIZE }" > /dev/null

		# Set Firecracker network
		if ip link show tap0 > /dev/null 2>&1; then
		curl -sf --unix-socket "$SOCKET" -X PUT 'http://localhost/network-interfaces/eth0' \
			-H 'Content-Type: application/json' \
			-d '{ "iface_id": "eth0", "host_dev_name": "tap0", "guest_mac": "02:FC:AB:CD:EF:01" }' > /dev/null
		fi

		# Set Firecracker storage
		curl -sf --unix-socket "$SOCKET" -X PUT 'http://localhost/drives/rootfs' \
			-H 'Content-Type: application/json' \
			-d "{ \"drive_id\": \"rootfs\", \"path_on_host\": \"$DISK\", \"is_root_device\": true, \"is_read_only\": false }" > /dev/null

		# Start Firecracker VM
		curl -sf --unix-socket "$SOCKET" -X PUT 'http://localhost/actions' \
			-H 'Content-Type: application/json' \
			-d '{ "action_type": "InstanceStart" }' > /dev/null

		echo "BareMetal VM started. VM Log: $VMLOG, Firecracker Log: $FCLOG"

		;;

	send)
		# Send a line of text to the VM serial console followed by Enter
		screen -S "$SESSION" -X stuff "$(printf '%s\r' "$*")"

		;;

	output)
		# Print new output since the last time this command was run
		# Use --full to print the entire log
		if [ ! -f "$VMLOG" ]; then
			echo "(no output yet)"
		elif [ "${1:-}" = "--full" ]; then
			tr -d '\r' < "$VMLOG"
		else
			pos=1
			[ -f "$VMLOGPOS" ] && pos=$(cat "$VMLOGPOS")
			tail -c "+$pos" "$VMLOG" | tr -d '\r'
			printf '%s\n' "$(($(wc -c < "$VMLOG") - 1))" > "$VMLOGPOS"
			printf '\n'
		fi

		;;

	attach)
		# Attach to the screen session for interactive use
		if screen -list "$SESSION" > /dev/null 2>&1; then
			screen -S "$SESSION" -X caption always "%{= 30}[BareMetal Firecracker] Detach: Ctrl+A, D"
		fi
		screen -r "$SESSION"

		;;

	status)
		if [ -S "$SOCKET" ] && curl -sf --unix-socket "$SOCKET" 'http://localhost/machine-config' > /dev/null 2>&1; then
			echo "VM is running"
		else
			echo "VM is not running"
		fi

		;;

	stop)
		# Stop Firecracker VM
		curl -sf --unix-socket "$SOCKET" -X PUT 'http://localhost/actions' \
			-H 'Content-Type: application/json' \
			-d '{ "action_type": "SendCtrlAltDel" }' > /dev/null

		;;

	help|"")
		echo "Usage: $0 <command> [args]"
		echo ""
		echo "Commands:"
		echo "  start              Configure and start the VM"
		echo "  status             Check if the VM is currently running"
		echo "  send <text>        Send a line of text to the VM serial console"
		echo "  output [--full]    Print new VM serial console output (--full for entire log)"
		echo "  attach             Attach to the interactive screen session"
		echo "  stop               Gracefully shut down the VM (Ctrl+Alt+Del)"
		echo "  help               Show this help screen"
		echo ""
		echo "Configuration (edit variables in script):"
		echo "  SOCKET   $SOCKET"
		echo "  KERNEL   $KERNEL"
		echo "  DISK     $DISK"
		echo "  MEMSIZE  $MEMSIZE"
		echo "  DISKSIZE $DISKSIZE"
		echo "  SESSION  $SESSION"
		echo "  VMLOG    $VMLOG"
		echo "  FCLOG    $FCLOG"

		;;

	*)
		echo "Unknown command: $cmd"
		echo "Run '$0 help' for usage."
		exit 1

		;;
esac

# //EOF
