#!/bin/bash
# Creates br0 bridge with tap0 in promiscuous mode.
#
# Wired host NIC: enslaves the NIC to the bridge for full L2 visibility.
# Wi-Fi host NIC: cannot be enslaved (802.11 station mode limitation);
#                 falls back to NAT so guests still have outbound connectivity.
set -euo pipefail

BRIDGE="br0"
TAP="tap0"
BRIDGE_IP="172.19.0.1/24"   # used only in NAT/Wi-Fi mode

HOST_IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}')

if [ -z "$HOST_IFACE" ]; then
    echo "ERROR: could not determine host network interface" >&2
    exit 1
fi

# Detect wireless interface (phy80211 symlink present in sysfs)
if [ -d "/sys/class/net/$HOST_IFACE/phy80211" ]; then
    WIFI=true
else
    WIFI=false
fi

echo "Host interface: $HOST_IFACE ($( $WIFI && echo wireless || echo wired ))"
echo "Bridge:         $BRIDGE"
echo "Tap:            $TAP"

# Create the bridge
sudo ip link add name "$BRIDGE" type bridge
sudo ip link set "$BRIDGE" promisc on
echo "Created $BRIDGE"

if $WIFI; then
    # Wi-Fi cannot be enslaved to a bridge — use NAT instead
    echo "Wi-Fi detected: using NAT mode (bridge isolated from $HOST_IFACE)"

    sudo ip addr add "$BRIDGE_IP" dev "$BRIDGE"
    sudo ip link set "$BRIDGE" up

    sudo sysctl -q net.ipv4.ip_forward=1

    sudo iptables -t nat -A POSTROUTING -o "$HOST_IFACE" -j MASQUERADE
    sudo iptables -A FORWARD -i "$BRIDGE" -o "$HOST_IFACE" -j ACCEPT
    sudo iptables -A FORWARD -i "$HOST_IFACE" -o "$BRIDGE" -m state --state RELATED,ESTABLISHED -j ACCEPT
    echo "NAT rules added (masquerade via $HOST_IFACE)"

    sudo dnsmasq \
        --port=0 \
        --interface="$BRIDGE" \
        --bind-interfaces \
        --dhcp-range=172.19.0.10,172.19.0.254,12h \
        --dhcp-option=option:router,172.19.0.1 \
        --dhcp-option=option:dns-server,1.1.1.1,8.8.8.8 \
        --pid-file=/var/run/dnsmasq-"$BRIDGE".pid
    echo "dnsmasq DHCP server started on $BRIDGE (172.19.0.10-254)"
else
    # Wired: enslave the NIC to the bridge for true L2 passthrough
    HOST_IP=$(ip -4 addr show "$HOST_IFACE" | awk '/inet /{print $2; exit}')
    HOST_GW=$(ip route show default dev "$HOST_IFACE" | awk '{print $3; exit}')

    sudo ip link set "$HOST_IFACE" promisc on
    sudo ip link set "$HOST_IFACE" master "$BRIDGE"
    echo "Added $HOST_IFACE to $BRIDGE"

    if [ -n "$HOST_IP" ]; then
        sudo ip addr del "$HOST_IP" dev "$HOST_IFACE" 2>/dev/null || true
        sudo ip addr add "$HOST_IP" dev "$BRIDGE"
        echo "Moved IP $HOST_IP to $BRIDGE"
    fi

    sudo ip link set "$BRIDGE" up

    if [ -n "$HOST_GW" ]; then
        if ! ip route show default | grep -q "dev $BRIDGE"; then
            sudo ip route add default via "$HOST_GW" dev "$BRIDGE" 2>/dev/null || true
            echo "Restored default route via $HOST_GW on $BRIDGE"
        fi
    fi
fi

# Create and attach the tap
sudo ip tuntap add dev "$TAP" mode tap
sudo ip link set "$TAP" promisc on
sudo ip link set "$TAP" master "$BRIDGE"
sudo ip link set "$TAP" up
echo "Created $TAP and attached to $BRIDGE"

echo "Done."
