#!/usr/bin/env bash
set -e

# =========================
# 1️⃣ 选择 OpenVPN 配置文件
# =========================
echo "[1] 选择 OpenVPN 配置文件..."
if [ -n "$OVPN_FILE" ]; then
  CONFIG="/vpn/$OVPN_FILE"
else
  CONFIG=$(ls /vpn/*.ovpn 2>/dev/null | head -n 1)
fi

if [ ! -f "$CONFIG" ]; then
  echo "❌ 配置文件不存在: $CONFIG"
  ls -1 /vpn/*.ovpn 2>/dev/null || echo "无 .ovpn 文件"
  exit 1
fi
echo "✅ 使用配置文件: $CONFIG"

# =========================
# 2️⃣ OpenVPN 用户名密码
# =========================
AUTH_FILE="/tmp/auth.txt"
if [ -n "$VPN_USERNAME" ] && [ -n "$VPN_PASSWORD" ]; then
  echo "[2] 启用 OpenVPN 用户名密码认证"
  printf "%s\n%s\n" "$VPN_USERNAME" "$VPN_PASSWORD" > "$AUTH_FILE"
  chmod 600 "$AUTH_FILE"

  if grep -q "^auth-user-pass" "$CONFIG"; then
    sed -i "s|^auth-user-pass.*|auth-user-pass $AUTH_FILE|" "$CONFIG"
  else
    echo "auth-user-pass $AUTH_FILE" >> "$CONFIG"
  fi
else
  echo "[2] 未提供 OpenVPN 用户名密码"
fi

# =========================
# 3️⃣ Xray 配置（可选 SOCKS 用户认证）
# =========================
SOCKS_PORT=${SOCKS_PORT:-1080}

if [ -n "$SOCKS_USER" ] && [ -n "$SOCKS_PASS" ]; then
  echo "[3] 启用 SOCKS5 用户认证"
  cat > /tmp/xray.json <<EOF
{
  "inbounds": [
    {
      "port": $SOCKS_PORT,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "$SOCKS_USER",
            "pass": "$SOCKS_PASS"
          }
        ],
        "udp": true,
        "userLevel": 0
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF
  XRAY_CONFIG="/tmp/xray.json"
else
  echo "[3] 使用默认 Xray 配置（无认证）"
  XRAY_CONFIG="/etc/xray.json"
fi

# =========================
# 4️⃣ 定期重启（可选）
# =========================
if [ -n "$RESTART_INTERVAL_HOURS" ] && [ "$RESTART_INTERVAL_HOURS" -gt 0 ]; then
  echo "[4] 设置定期重启：每 $RESTART_INTERVAL_HOURS 小时"
  apk add --no-cache cronie
  echo "0 */$RESTART_INTERVAL_HOURS * * * root /sbin/reboot" > /etc/crontabs/root
  crond
fi

# =========================
# 5️⃣ 启动 OpenVPN & Xray
# =========================
(
  echo "[5] 等待 VPN 连接 (tun0)..."
  while ! ip a | grep -q tun0; do sleep 1; done

  echo "[6] 设置默认路由走 VPN"
  ip route del default || true
  ip route add default dev tun0

  echo "[7] 启动 Xray..."
  exec xray -config "$XRAY_CONFIG"
) &

# OpenVPN 前台运行（关键！保持容器不退出）
exec openvpn --config "$CONFIG" \
  --resolv-retry infinite \
  --persist-key \
  --persist-tun \
  --keepalive 10 60 \
  --verb 3