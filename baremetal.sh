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
#	mem [mib]	Show hot-plug memory status, or set how much the guest may plug (MiB)
#	stop		Send Ctrl+Alt+Del to gracefully shut down the VM
#	help		Display help info
#
# Configuration (edit variables below):
#	SOCKET		Unix socket path used by the Firecracker API
#	KERNEL		Path to the BareMetal ELF kernel image
#	DISK		Path to the disk image
#	MEMSIZE		VM boot memory size in MiB (must fit the kernel+app ELF)
#	DISKSIZE	Size of the disk image, created on first start (e.g. 512M)
#	SESSION		Screen session name
#	VMLOG		Path to the VM serial console log file
#	VMLOGPOS	Path to the output read-position tracking file
#	FCLOG		Path to the firecracker log file
#	MEMHOTPLUG_EN	1 to attach a virtio-mem device so the guest can grow its RAM on demand
#	MEMHOTPLUG_MAX	Hot-pluggable memory ceiling in MiB; also handed to the guest as its plug budget at start
#	MEMHOTPLUG_BLOCK Hot-plug block size in MiB (power of 2, minimum 2)
#	MEMHOTPLUG_SLOT	KVM memory slot size in MiB (power of 2, >= block size)
set -eu

SOCKET=/tmp/firecracker.socket
KERNEL="$PWD/sys/baremetal.elf"
DISK="$PWD/disk.img"
CPUCOUNT=1
MEMSIZE=4 # As of last webserver.py test Python needed at least 28MiB
DISKSIZE=512M
SESSION=fc-vm
FCLOG="/tmp/fc.log"
VMLOG=/tmp/fc-vm.log
VMLOGPOS=/tmp/fc-vm.log.pos
MEMHOTPLUG_EN=1
MEMHOTPLUG_MAX=1024 # Guest RAM can grow to MEMSIZE + this. Only what the app actually touches costs host memory
MEMHOTPLUG_BLOCK=2
MEMHOTPLUG_SLOT=128 # 128 is the minimum for KVM

# Prepare arguments
cmd="${1:-}" # first argument is the subcommand (default: empty)
[ "$#" -gt 0 ] && shift # remove subcommand so "$@" holds remaining args

# PUT to the Firecracker API. Unlike a plain `curl -f`, this reports the
# API's error body (e.g. "not enough memory to load the kernel") and kills
# the leftover firecracker session instead of leaving it running while the
# script exits silently.
fc_put() {
	path="$1"
	body="$2"
	tmp=$(mktemp)
	status=$(curl -s -o "$tmp" -w '%{http_code}' --unix-socket "$SOCKET" -X PUT "http://localhost$path" \
		-H 'Content-Type: application/json' -d "$body")
	case "$status" in
		2??)
			rm -f "$tmp"
			;;
		*)
			msg=$(sed -n 's/.*"fault_message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$tmp")
			[ -n "$msg" ] || msg=$(cat "$tmp")
			rm -f "$tmp"
			echo "Error: Firecracker API PUT $path failed (HTTP $status): $msg" >&2
			screen -S "$SESSION" -X quit > /dev/null 2>&1 || true
			rm -f "$SOCKET"
			exit 1
			;;
	esac
}

# Set how much hot-plug memory the guest may plug (virtio-mem's
# requested_size). Firecracker boots with this at 0 and NACKs any plug
# beyond it, so without this the guest's GROW_MEMORY calls always come
# back empty. It also rejects the PATCH until the guest's virtio-mem
# driver has activated the device -- a few ms into boot -- hence the
# retry loop, which gives up (with a warning, not a failure) after ~5s.
fc_mem_request() {
	mib="$1"
	tries=0
	while :; do
		tmp=$(mktemp)
		status=$(curl -s -o "$tmp" -w '%{http_code}' --unix-socket "$SOCKET" -X PATCH 'http://localhost/hotplug/memory' \
			-H 'Content-Type: application/json' -d "{ \"requested_size_mib\": $mib }")
		case "$status" in
			2??)
				rm -f "$tmp"
				return 0
				;;
		esac
		tries=$((tries + 1))
		if [ "$tries" -ge 100 ]; then
			msg=$(sed -n 's/.*"fault_message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$tmp")
			rm -f "$tmp"
			echo "Warning: could not set hot-plug requested_size_mib=$mib (HTTP $status): $msg" >&2
			return 1
		fi
		rm -f "$tmp"
		sleep 0.05
	done
}

case "$cmd" in
	start)
		# MEMSIZE must fit the kernel ELF plus ~2MiB of loader/boot
		# overhead, or firecracker's InstanceStart fails with "Unable
		# to read kernel image" once the ELF no longer fits in guest
		# memory. Check this up front instead of letting firecracker
		# fail after it's already running.
		if [ ! -f "$KERNEL" ]; then
			echo "Error: kernel image not found at $KERNEL" >&2
			exit 1
		fi
		kernel_size=$(wc -c < "$KERNEL")
		min_mib=$(( (kernel_size + 1048575) / 1048576 + 2 ))
		if [ "$MEMSIZE" -lt "$min_mib" ]; then
			echo "Error: MEMSIZE=${MEMSIZE}MiB is too small for $KERNEL ($kernel_size bytes); needs at least ${min_mib}MiB" >&2
			exit 1
		fi

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

		# Wait for socket, but bail out if firecracker exits (or never
		# starts) instead of waiting forever
		tries=0
		while [ ! -S "$SOCKET" ]; do
			if ! screen -list "$SESSION" > /dev/null 2>&1; then
				echo "Error: firecracker exited before creating its API socket. Check $FCLOG for details." >&2
				exit 1
			fi
			tries=$((tries + 1))
			if [ "$tries" -ge 200 ]; then
				echo "Error: timed out waiting for firecracker API socket $SOCKET" >&2
				screen -S "$SESSION" -X quit > /dev/null 2>&1 || true
				exit 1
			fi
			sleep 0.05
		done

		# Set Firecracker kernel and boot args
		boot_args=""
		[ "$#" -gt 0 ] && boot_args="args=\`$*\`"
		fc_put '/boot-source' "{ \"kernel_image_path\": \"$KERNEL\", \"boot_args\": \"$boot_args\" }"

		# Set Firecracker CPU and MEM
		fc_put '/machine-config' "{ \"vcpu_count\": $CPUCOUNT, \"mem_size_mib\": $MEMSIZE }"

		# Set Firecracker network
		if ip link show tap0 > /dev/null 2>&1; then
		fc_put '/network-interfaces/eth0' '{ "iface_id": "eth0", "host_dev_name": "tap0", "guest_mac": "02:FC:AB:CD:EF:01" }'
		fi

		# Set Firecracker storage
		fc_put '/drives/rootfs' "{ \"drive_id\": \"rootfs\", \"path_on_host\": \"$DISK\", \"is_root_device\": true, \"is_read_only\": false }"

		# Set Firecracker hotplug memory
		if [ "$MEMHOTPLUG_EN" -eq 1 ]; then
		fc_put '/hotplug/memory' "{ \"total_size_mib\": $MEMHOTPLUG_MAX, \"block_size_mib\": $MEMHOTPLUG_BLOCK, \"slot_size_mib\": $MEMHOTPLUG_SLOT }"
		fi

		# Start Firecracker VM
		fc_put '/actions' '{ "action_type": "InstanceStart" }'

		echo "BareMetal VM started. VM Log: $VMLOG, Firecracker Log: $FCLOG"

		# Hand the guest its hot-plug budget (see fc_mem_request). The
		# kernel's virtio-mem driver plugs blocks from it lazily as the
		# app's allocations outgrow the boot RAM
		if [ "$MEMHOTPLUG_EN" -eq 1 ]; then
			fc_mem_request "$MEMHOTPLUG_MAX" || true
		fi

		;;

	mem)
		# Show the hot-plug memory state, optionally after setting how
		# much the guest may plug (MiB, a multiple of MEMHOTPLUG_BLOCK,
		# at most MEMHOTPLUG_MAX). Lowering it below what is already
		# plugged has no effect: BareMetal never unplugs memory
		if [ "$#" -gt 0 ]; then
			fc_mem_request "$1"
		fi
		curl -sf --unix-socket "$SOCKET" 'http://localhost/hotplug/memory' || echo "Error: no hot-plug memory device (VM not running, or MEMHOTPLUG_EN=0)" >&2
		echo

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
		echo "  mem [mib]          Show hot-plug memory status, or set how much the guest may plug"
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
		echo "  MEMHOTPLUG_EN    $MEMHOTPLUG_EN"
		echo "  MEMHOTPLUG_MAX   $MEMHOTPLUG_MAX"
		echo "  MEMHOTPLUG_BLOCK $MEMHOTPLUG_BLOCK"
		echo "  MEMHOTPLUG_SLOT  $MEMHOTPLUG_SLOT"

		;;

	*)
		echo "Unknown command: $cmd"
		echo "Run '$0 help' for usage."
		exit 1

		;;
esac

# //EOF
