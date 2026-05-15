#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

load_env_file() {
  local file="$1"
  if [ -f "$file" ]; then
    set -a
    source "$file"
    set +a
  fi
}

log "[1] loading env..."
load_env_file /env/openvpn.env
load_env_file /env/proxy.env
load_env_file /env/runtime.env

: "${OVPN_PROTO:=udp}"
: "${OVPN_PORT:=1194}"
: "${OVPN_DEV:=ovpn0}"
: "${OVPN_DNS:=1.1.1.1}"
: "${OVPN_NETWORK:=10.8.0.0}"
: "${OVPN_NETMASK:=255.255.255.0}"
: "${OVPN_CIDR:=10.8.0.0/24}"
: "${OVPN_SERVER_IP:=10.8.0.1}"
: "${OVPN_MAX_CLIENTS:=1024}"
: "${OVPN_DUPLICATE_CN:=0}"
: "${OVPN_CLIENT_TO_CLIENT:=0}"
: "${OVPN_CLIENT_NAME:=client}"
: "${OVPN_SERVER_ADDR:=}"
: "${OVPN_CIPHER:=AES-128-GCM}"
: "${OVPN_DATA_CIPHERS:=AES-128-GCM:AES-256-GCM:CHACHA20-POLY1305}"
: "${OVPN_AUTH:=SHA256}"
: "${OVPN_VERB:=3}"

: "${PROXY_HOST:?missing PROXY_HOST}"
: "${PROXY_PORT:?missing PROXY_PORT}"
: "${PROXY_USER:=}"
: "${PROXY_PASS:=}"
: "${PROXY_UDP:=true}"

: "${MARK:=1}"
: "${TABLE_ID:=100}"
: "${TPROXY_PORT:=7893}"
: "${TPROXY_BACKEND:=iptables}"
: "${FULL_PROXY:=1}"
: "${SING_BOX_LOG_LEVEL:=warning}"
: "${DNS_SERVER:=1.1.1.1}"
: "${DNS_SERVER_PORT:=443}"
: "${DNS_PATH:=/dns-query}"
: "${DNS_TLS_SERVER_NAME:=cloudflare-dns.com}"
: "${DNS_STRATEGY:=prefer_ipv4}"
: "${DNS_LISTEN:=127.0.0.1}"
: "${DNS_PORT:=1053}"

export OVPN_PROTO OVPN_PORT OVPN_DEV OVPN_DNS OVPN_NETWORK OVPN_NETMASK OVPN_CIDR OVPN_SERVER_IP OVPN_MAX_CLIENTS OVPN_DUPLICATE_CN OVPN_CLIENT_TO_CLIENT OVPN_CLIENT_NAME OVPN_SERVER_ADDR
export OVPN_CIPHER OVPN_DATA_CIPHERS OVPN_AUTH OVPN_VERB OVPN_DUPLICATE_CN_CONFIG OVPN_CLIENT_TO_CLIENT_CONFIG
export PROXY_HOST PROXY_PORT PROXY_USER PROXY_PASS PROXY_UDP
export MARK TABLE_ID TPROXY_PORT FULL_PROXY TPROXY_BACKEND SING_BOX_LOG_LEVEL DNS_SERVER DNS_SERVER_PORT DNS_PATH DNS_TLS_SERVER_NAME DNS_STRATEGY DNS_LISTEN DNS_PORT

if [ "${OVPN_DNS}" = "auto" ] || [ -z "${OVPN_DNS}" ]; then
  OVPN_DNS="${OVPN_SERVER_IP}"
  export OVPN_DNS
fi
if [ "${OVPN_DUPLICATE_CN}" = "1" ] || [ "${OVPN_DUPLICATE_CN}" = "true" ]; then
  OVPN_DUPLICATE_CN_CONFIG="duplicate-cn"
else
  OVPN_DUPLICATE_CN_CONFIG=""
fi
if [ "${OVPN_CLIENT_TO_CLIENT}" = "1" ] || [ "${OVPN_CLIENT_TO_CLIENT}" = "true" ]; then
  OVPN_CLIENT_TO_CLIENT_CONFIG="client-to-client"
else
  OVPN_CLIENT_TO_CLIENT_CONFIG=""
fi
export OVPN_DUPLICATE_CN_CONFIG OVPN_CLIENT_TO_CLIENT_CONFIG

OPENVPN_DIR=/openvpn
PKI_DIR="${OPENVPN_DIR}/pki"
CLIENTS_DIR="${OPENVPN_DIR}/clients"
SERVER_CONF=/etc/openvpn/server.conf
SING_BOX_CONF=/etc/sing-box/config.json

mkdir -p "$OPENVPN_DIR" "$CLIENTS_DIR" /etc/openvpn /etc/sing-box

if [ ! -f "${OPENVPN_DIR}/server.conf.tpl" ]; then
  cp /openvpn-defaults/server.conf.tpl "${OPENVPN_DIR}/server.conf.tpl"
fi

make_pki() {
  log "[2] generating OpenVPN PKI in mounted directory..."
  local easyrsa_bin="/usr/share/easy-rsa/easyrsa"
  if [ ! -x "$easyrsa_bin" ]; then
    easyrsa_bin=$(command -v easyrsa)
  fi
  mkdir -p "$PKI_DIR"
  EASYRSA_PKI="$PKI_DIR" "$easyrsa_bin" --batch init-pki
  EASYRSA_PKI="$PKI_DIR" EASYRSA_REQ_CN="vpn-box-ca" "$easyrsa_bin" --batch build-ca nopass
  EASYRSA_PKI="$PKI_DIR" "$easyrsa_bin" --batch build-server-full server nopass
  EASYRSA_PKI="$PKI_DIR" "$easyrsa_bin" --batch build-client-full "${OVPN_CLIENT_NAME}" nopass
  openvpn --genkey secret "$PKI_DIR/ta.key"
}

if [ ! -f "$PKI_DIR/ca.crt" ] || [ ! -f "$PKI_DIR/issued/server.crt" ] || [ ! -f "$PKI_DIR/private/server.key" ] || [ ! -f "$PKI_DIR/ta.key" ]; then
  make_pki
else
  log "[2] existing OpenVPN PKI found, skip generation"
fi

if [ -z "$OVPN_SERVER_ADDR" ]; then
  OVPN_SERVER_ADDR=$(curl -fsS --max-time 5 https://api.ipify.org || hostname -i | awk '{print $1}')
  export OVPN_SERVER_ADDR
fi

make_client_profile() {
  local client="$1"
  local ovpn="${CLIENTS_DIR}/${client}.ovpn"
  if [ -f "$ovpn" ]; then
    log "[3] existing client profile found: $ovpn"
    return
  fi
  log "[3] generating client profile: $ovpn"
  {
    echo "client"
    echo "dev tun"
    echo "proto ${OVPN_PROTO}"
    echo "remote ${OVPN_SERVER_ADDR} ${OVPN_PORT}"
    echo "resolv-retry infinite"
    echo "nobind"
    echo "persist-key"
    echo "persist-tun"
    echo "remote-cert-tls server"
    echo "auth ${OVPN_AUTH}"
    echo "data-ciphers ${OVPN_DATA_CIPHERS}"
    echo "data-ciphers-fallback ${OVPN_CIPHER}"
    echo "verb 3"
    echo "key-direction 1"
    echo "<ca>"
    cat "$PKI_DIR/ca.crt"
    echo "</ca>"
    echo "<cert>"
    sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "$PKI_DIR/issued/${client}.crt"
    echo "</cert>"
    echo "<key>"
    cat "$PKI_DIR/private/${client}.key"
    echo "</key>"
    echo "<tls-crypt>"
    cat "$PKI_DIR/ta.key"
    echo "</tls-crypt>"
  } > "$ovpn"
  chmod 600 "$ovpn"
}

if [ ! -f "$PKI_DIR/issued/${OVPN_CLIENT_NAME}.crt" ] || [ ! -f "$PKI_DIR/private/${OVPN_CLIENT_NAME}.key" ]; then
  log "[3] generating extra client certificate: ${OVPN_CLIENT_NAME}"
  easyrsa_bin="/usr/share/easy-rsa/easyrsa"
  if [ ! -x "$easyrsa_bin" ]; then
    easyrsa_bin=$(command -v easyrsa)
  fi
  EASYRSA_PKI="$PKI_DIR" "$easyrsa_bin" --batch build-client-full "${OVPN_CLIENT_NAME}" nopass
fi
make_client_profile "$OVPN_CLIENT_NAME"

log "[4] generating runtime configs..."
envsubst < "${OPENVPN_DIR}/server.conf.tpl" > "$SERVER_CONF"
if [ -n "$PROXY_USER" ] || [ -n "$PROXY_PASS" ]; then
  envsubst < /sing-box/config.auth.tpl.json > "$SING_BOX_CONF"
else
  envsubst < /sing-box/config.noauth.tpl.json > "$SING_BOX_CONF"
fi
envsubst < /nft/rules.nft.tpl > /tmp/rules.nft

log "[5] enabling routing..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null || true
sysctl -w net.ipv4.conf.all.route_localnet=1 >/dev/null || true
iptables -t nat -D PREROUTING -i "${OVPN_DEV}" -p udp --dport 53 -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null || true
iptables -t nat -D PREROUTING -i "${OVPN_DEV}" -p tcp --dport 53 -j REDIRECT --to-ports "${DNS_PORT}" 2>/dev/null || true
iptables -t nat -D PREROUTING -i "${OVPN_DEV}" -p udp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null || true
iptables -t nat -D PREROUTING -i "${OVPN_DEV}" -p tcp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null || true

log "[6] loading transparent proxy rules..."
if [ "${TPROXY_BACKEND}" = "nft" ]; then
  if ! nft -f /tmp/rules.nft; then
    log "nftables failed; set TPROXY_BACKEND=iptables or run container with --privileged if your host/kernel blocks nft"
    exit 1
  fi
else
  iptables -t mangle -D PREROUTING -i "${OVPN_DEV}" -p tcp -j MARK --set-mark "${MARK}" 2>/dev/null || true
  iptables -t mangle -D PREROUTING -i "${OVPN_DEV}" -p udp -j MARK --set-mark "${MARK}" 2>/dev/null || true
  iptables -t mangle -D PREROUTING -i "${OVPN_DEV}" -p tcp -j TPROXY --on-port "${TPROXY_PORT}" --tproxy-mark "${MARK}" 2>/dev/null || true
  iptables -t mangle -D PREROUTING -i "${OVPN_DEV}" -p udp -j TPROXY --on-port "${TPROXY_PORT}" --tproxy-mark "${MARK}" 2>/dev/null || true
  iptables -t mangle -A PREROUTING -i "${OVPN_DEV}" -p tcp ! -d "${OVPN_CIDR}" ! --dport 53 -j TPROXY --on-port "${TPROXY_PORT}" --tproxy-mark "${MARK}"
  iptables -t mangle -A PREROUTING -i "${OVPN_DEV}" -p udp ! -d "${OVPN_CIDR}" ! --dport 53 -j TPROXY --on-port "${TPROXY_PORT}" --tproxy-mark "${MARK}"
fi

log "[7] configuring policy routing..."
ip rule add fwmark "${MARK}" table "${TABLE_ID}" 2>/dev/null || true
ip route add local 0.0.0.0/0 dev lo table "${TABLE_ID}" 2>/dev/null || true

log "[8] starting sing-box..."
sing-box run -c "$SING_BOX_CONF" &
SING_BOX_PID=$!

log "[9] starting openvpn..."
openvpn --config "$SERVER_CONF" &
OPENVPN_PID=$!

wait -n "$SING_BOX_PID" "$OPENVPN_PID"
log "one process exited, stopping container..."
kill "$SING_BOX_PID" "$OPENVPN_PID" 2>/dev/null || true
wait || true
