#!/bin/sh
# firecracker.sh - Manage a BareMetal Firecracker VM
#
# Usage: firecracker.sh <command> [args]
#
# Commands:
#	start		Configure and start the VM (sets up kernel, disk, network, and launches instance)
#	status		Check if the VM is currently running
#	send <text>	Send a line of text to the VM serial console followed by Enter
#	output		Print the VM serial console log
#	attach		Attach to the interactive screen session for the VM console
#	stop		Send Ctrl+Alt+Del to gracefully shut down the VM
#	help		Display help info
#
# Configuration (edit variables below):
#	SOCKET		Unix socket path used by the Firecracker API
#	KERNEL		Path to the BareMetal ELF kernel image
#	DISK		Path to the disk image
#	SESSION		Screen session name
#	LOG		Path to the serial console log file
set -eu

SOCKET=/run/firecracker.socket
KERNEL="$PWD/sys/baremetal.elf"
DISK="$PWD/disk.img"
SESSION=fc-vm
LOG=/tmp/fc-serial.log

# Prepare arguments
cmd="${1:-}" # first argument is the subcommand (default: empty)
[ "$#" -gt 0 ] && shift # remove subcommand so "$@" holds remaining args

case "$cmd" in
	start)
		sudo rm -f "$SOCKET"
		rm -f "$LOG"

		# Kill any leftover session from a previous run
		screen -S "$SESSION" -X quit 2>/dev/null || true

		# Start Firecracker in a detached screen session with output logging
		screen -L -Logfile "$LOG" -dmS "$SESSION" \
			sudo firecracker --api-sock "$SOCKET" --log-path /dev/null

		# Flush screen log immediately instead of the default 10s interval
		screen -S "$SESSION" -X logfile flush 0

		# Wait for socket
		while [ ! -S "$SOCKET" ]; do sleep 0.05; done
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

		echo "VM started. Log: $LOG"
		;;

	send)
		# Send a line of text to the VM serial console followed by Enter
		screen -S "$SESSION" -X stuff "$(printf '%s\r' "${1:-}")"
		;;

	output)
		# Dump full output log
		tr -d '\r' < "$LOG" 2>/dev/null || echo "(no output yet)"
		;;

	attach)
		# Attach to the screen session for interactive use
		if screen -list "$SESSION" > /dev/null 2>&1; then
			screen -S "$SESSION" -X caption always "[BareMetal Firecracker] Detach: Ctrl+A then D"
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
		echo "  output             Print the VM serial console log"
		echo "  attach             Attach to the interactive screen session"
		echo "  stop               Gracefully shut down the VM (Ctrl+Alt+Del)"
		echo "  help               Show this help screen"
		echo ""
		echo "Configuration (edit variables in script):"
		echo "  SOCKET  $SOCKET"
		echo "  KERNEL  $KERNEL"
		echo "  DISK    $DISK"
		echo "  SESSION $SESSION"
		echo "  LOG     $LOG"
		;;

	*)
		echo "Unknown command: $cmd"
		echo "Run '$0 help' for usage."
		exit 1
		;;
esac

# //EOF
