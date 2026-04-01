#!/usr/bin/env bash
set -e

echo "[1] 选择 OpenVPN 配置文件..."

# 优先使用环境变量
if [ -n "$OVPN_FILE" ]; then
  CONFIG="/vpn/$OVPN_FILE"
else
  CONFIG=$(ls /vpn/*.ovpn 2>/dev/null | head -n 1)
fi

# 检查文件是否存在
if [ ! -f "$CONFIG" ]; then
  echo "❌ 配置文件不存在: $CONFIG"
  echo "📂 当前可用配置文件："
  ls -1 /vpn/*.ovpn 2>/dev/null || echo "无 .ovpn 文件"
  exit 1
fi

echo "✅ 使用配置文件: $CONFIG"

echo "[2] 启动 OpenVPN..."
openvpn --config "$CONFIG" --daemon

echo "[3] 等待 VPN 连接 (tun0)..."
while ! ip a | grep -q tun0; do
  sleep 1
done

echo "[4] 设置默认路由走 VPN"
ip route del default || true
ip route add default dev tun0

echo "[5] 启动 Xray..."
exec xray -config /etc/xray.json