#!/usr/bin/env bash
set -e

echo "[1] 启动 OpenVPN..."
openvpn --config /vpn/client.ovpn --daemon

# 等 tun0 出现
echo "[2] 等待 VPN 连接..."
while ! ip a | grep -q tun0; do
  sleep 1
done

echo "[3] 设置默认路由走 VPN"
ip route del default || true
ip route add default dev tun0

echo "[4] 启动 Xray..."
exec xray -config /etc/xray.json