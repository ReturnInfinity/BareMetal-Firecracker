#!/bin/bash
# Sends a ping to the br0 bridge network.
set -euo pipefail

BRIDGE="br0"
COUNT="${1:-4}"

if ! ip link show "$BRIDGE" &>/dev/null; then
    echo "ERROR: $BRIDGE does not exist. Run mkbr0.sh first." >&2
    exit 1
fi

BRIDGE_IP=$(ip -4 addr show "$BRIDGE" | awk '/inet /{print $2; exit}')

if [ -z "$BRIDGE_IP" ]; then
    echo "ERROR: $BRIDGE has no IPv4 address assigned." >&2
    exit 1
fi

TARGET="${BRIDGE_IP%/*}"
GUEST_IP="${TARGET%.*}.$((${TARGET##*.} + 1))"

echo "Pinging $BRIDGE ($TARGET) — $COUNT packets"
ping -c "$COUNT" "$TARGET"

echo "Pinging guest ($GUEST_IP) — $COUNT packets"
ping -c "$COUNT" "$GUEST_IP"
