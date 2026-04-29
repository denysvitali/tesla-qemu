#!/bin/bash
set -euo pipefail

TAP="${TAP:-tap0}"
HOST_CIDR="${HOST_CIDR:-192.168.90.5/24}"

if ! ip link show "$TAP" >/dev/null 2>&1; then
    sudo ip tuntap add dev "$TAP" mode tap
fi

sudo ip link set "$TAP" up

if ! ip addr show dev "$TAP" | grep -q "inet ${HOST_CIDR%/*}/"; then
    sudo ip addr add "$HOST_CIDR" dev "$TAP"
fi
