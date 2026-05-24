#!/bin/bash
# Tears down br0 bridge, all attached tap devices, and NAT rules created by setup-bridge.sh.
set -euo pipefail

BRIDGE="br0"
HOST_IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}' || true)

# Remove TAP devices attached to the bridge
for TAP in $(ip link show master "$BRIDGE" 2>/dev/null | awk -F': ' '/^[0-9]+:/{print $2}'); do
    sudo ip link set "$TAP" nomaster
    sudo ip link set "$TAP" down
    sudo ip tuntap del dev "$TAP" mode tap
    echo "Removed $TAP"
done

# Tear down the bridge
if ip link show "$BRIDGE" &>/dev/null; then
    sudo ip link set "$BRIDGE" down
    sudo ip link del "$BRIDGE" type bridge
    echo "Removed $BRIDGE"
else
    echo "$BRIDGE not found, skipping"
fi

# Remove NAT/FORWARD rules if we can identify the host interface
if [ -n "$HOST_IFACE" ]; then
    sudo iptables -t nat -D POSTROUTING -o "$HOST_IFACE" -j MASQUERADE 2>/dev/null && echo "Removed MASQUERADE rule" || true
    sudo iptables -D FORWARD -i "$BRIDGE" -o "$HOST_IFACE" -j ACCEPT 2>/dev/null && echo "Removed FORWARD rule (br0 -> host)" || true
    sudo iptables -D FORWARD -i "$HOST_IFACE" -o "$BRIDGE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null && echo "Removed FORWARD rule (host -> br0)" || true
fi

echo "Done."
