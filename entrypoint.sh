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

# =========================
# 🔐 账号密码支持
# =========================
AUTH_FILE="/tmp/auth.txt"

if [ -n "$VPN_USERNAME" ] && [ -n "$VPN_PASSWORD" ]; then
  echo "[2] 启用用户名密码认证"

  printf "%s\n%s\n" "$VPN_USERNAME" "$VPN_PASSWORD" > "$AUTH_FILE"
  chmod 600 "$AUTH_FILE"

  if grep -q "^auth-user-pass" "$CONFIG"; then
    echo "[INFO] 替换已有 auth-user-pass"
    sed -i "s|^auth-user-pass.*|auth-user-pass $AUTH_FILE|" "$CONFIG"
  else
    echo "[INFO] 添加 auth-user-pass"
    echo "auth-user-pass $AUTH_FILE" >> "$CONFIG"
  fi
else
  echo "[2] 未提供用户名密码"
fi

echo "[3] 启动 OpenVPN（前台 + 自动重连）..."

# 后台等待 tun0 并设置路由
(
  echo "[4] 等待 VPN 连接 (tun0)..."
  while ! ip a | grep -q tun0; do
    sleep 1
  done

  echo "[5] 设置默认路由走 VPN"
  ip route del default || true
  ip route add default dev tun0

  echo "[6] 启动 Xray..."
  exec xray -config /etc/xray.json
) &

# 👉 OpenVPN 前台运行（关键！）
exec openvpn --config "$CONFIG" \
  --resolv-retry infinite \
  --persist-key \
  --persist-tun \
  --keepalive 10 60 \
  --verb 3