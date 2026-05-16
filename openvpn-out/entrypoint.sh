#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

load_env_file() {
  local file="$1"
  if [ -f "$file" ]; then
    set -a
    . "$file"
    set +a
  fi
}

wait_interface() {
  local dev="$1"
  local timeout="${2:-20}"
  local i=0
  while [ "$i" -lt "$timeout" ]; do
    if ip link show "$dev" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

wait_ipv4() {
  local dev="$1"
  local ipaddr="$2"
  local timeout="${3:-20}"
  local i=0
  while [ "$i" -lt "$timeout" ]; do
    if ip -4 addr show dev "$dev" | grep -q "${ipaddr}/"; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

cleanup_legacy_rules() {
  log "[0] cleaning old vpn-box/openvpn-out routing rules..."
  while ip rule del fwmark "${MARK}" table "${TABLE_ID}" 2>/dev/null; do :; done
  while ip rule del from "${OVPN_CIDR}" table "${TABLE_ID}" 2>/dev/null; do :; done
  ip route flush table "${TABLE_ID}" 2>/dev/null || true
  iptables -t mangle -D PREROUTING -j VPN_BOX_TPROXY 2>/dev/null || true
  iptables -t mangle -F VPN_BOX_TPROXY 2>/dev/null || true
  iptables -t mangle -X VPN_BOX_TPROXY 2>/dev/null || true

  local rule delete_rule
  while iptables -t mangle -S PREROUTING | grep -q -- "-j TPROXY .*--on-port ${TPROXY_PORT}"; do
    rule=$(iptables -t mangle -S PREROUTING | grep -- "-j TPROXY .*--on-port ${TPROXY_PORT}" | head -n 1)
    delete_rule=${rule/-A PREROUTING/-D PREROUTING}
    iptables -t mangle $delete_rule 2>/dev/null || break
  done

  while iptables -t nat -S PREROUTING | grep -q -- "--dport 53 .*REDIRECT .*--to-ports 1053"; do
    rule=$(iptables -t nat -S PREROUTING | grep -- "--dport 53 .*REDIRECT .*--to-ports 1053" | head -n 1)
    delete_rule=${rule/-A PREROUTING/-D PREROUTING}
    iptables -t nat $delete_rule 2>/dev/null || break
  done
}

log "[1] loading env..."
load_env_file /env/openvpn.env
load_env_file /env/proxy.env
load_env_file /env/runtime.env

: "${OVPN_PROTO:=udp}"
: "${OVPN_PORT:=1194}"
: "${OVPN_DEV:=ovpn0}"
: "${OVPN_DNS:=auto}"
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
: "${OVPN_PRESERVE_TEMPLATE:=0}"

: "${PROXY_TYPE:=socks}"
: "${PROXY_HOST:?missing PROXY_HOST}"
: "${PROXY_PORT:?missing PROXY_PORT}"
: "${PROXY_USER:=}"
: "${PROXY_PASS:=}"
: "${PROXY_PASSWORD:=${PROXY_PASS}}"
: "${PROXY_METHOD:=2022-blake3-aes-128-gcm}"
: "${PROXY_UDP:=true}"
: "${PROXY_TLS_SERVER_NAME:=}"
: "${PROXY_TLS_INSECURE:=0}"
: "${PROXY_TLS_ALPN:=}"

: "${TABLE_ID:=100}"
: "${TABLE_PRIORITY:=10000}"
: "${MARK:=1}"
: "${TPROXY_PORT:=7893}"
: "${TPROXY_BACKEND:=tun}"
: "${FULL_PROXY:=1}"
: "${SING_BOX_LOG_LEVEL:=warning}"
: "${SING_TUN_NAME:=sb-tun0}"
: "${SING_TUN_ADDRESS:=172.19.0.1/30}"
: "${SING_TUN_DNS_ADDRESS:=172.19.0.2}"
: "${SING_TUN_MTU:=1500}"
: "${SING_TUN_STACK:=mixed}"
: "${DNS_SERVER_TYPE:=https}"
: "${DNS_SERVER:=1.1.1.1}"
: "${DNS_SERVER_PORT:=443}"
: "${DNS_PATH:=/dns-query}"
: "${DNS_TLS_SERVER_NAME:=cloudflare-dns.com}"
: "${DNS_TLS_INSECURE:=0}"
: "${DNS_TLS_ALPN:=}"
: "${DNS_STRATEGY:=prefer_ipv4}"
: "${DNS_DETOUR:=proxy}"
: "${DNSMASQ_ENABLED:=1}"
: "${DNSMASQ_PORT:=53}"
: "${DNSMASQ_UPSTREAM:=${SING_TUN_DNS_ADDRESS}#53}"
: "${DNSMASQ_CACHE_SIZE:=0}"
: "${DNSMASQ_LOG_QUERIES:=0}"
: "${ENABLE_DIAGNOSTICS:=0}"
: "${PROXY_CHECK_URL:=https://www.cloudflare.com/cdn-cgi/trace}"

if [ "${OVPN_DNS}" = "auto" ] || [ -z "${OVPN_DNS}" ]; then
  if [ "${DNSMASQ_ENABLED}" = "1" ] || [ "${DNSMASQ_ENABLED}" = "true" ]; then
    OVPN_DNS="${OVPN_SERVER_IP}"
  else
    OVPN_DNS="${SING_TUN_DNS_ADDRESS}"
  fi
fi

export OVPN_PROTO OVPN_PORT OVPN_DEV OVPN_DNS OVPN_NETWORK OVPN_NETMASK OVPN_CIDR OVPN_SERVER_IP OVPN_MAX_CLIENTS OVPN_DUPLICATE_CN OVPN_CLIENT_TO_CLIENT OVPN_CLIENT_NAME OVPN_SERVER_ADDR
export OVPN_CIPHER OVPN_DATA_CIPHERS OVPN_AUTH OVPN_VERB OVPN_DUPLICATE_CN_CONFIG OVPN_CLIENT_TO_CLIENT_CONFIG OVPN_PRESERVE_TEMPLATE
export PROXY_TYPE PROXY_HOST PROXY_PORT PROXY_USER PROXY_PASS PROXY_PASSWORD PROXY_METHOD PROXY_UDP PROXY_TLS_SERVER_NAME PROXY_TLS_INSECURE PROXY_TLS_ALPN
export TABLE_ID TABLE_PRIORITY MARK TPROXY_PORT TPROXY_BACKEND FULL_PROXY SING_BOX_LOG_LEVEL SING_TUN_NAME SING_TUN_ADDRESS SING_TUN_DNS_ADDRESS SING_TUN_MTU SING_TUN_STACK
export DNS_SERVER_TYPE DNS_SERVER DNS_SERVER_PORT DNS_PATH DNS_TLS_SERVER_NAME DNS_TLS_INSECURE DNS_TLS_ALPN DNS_STRATEGY DNS_DETOUR DNSMASQ_ENABLED DNSMASQ_PORT DNSMASQ_UPSTREAM DNSMASQ_CACHE_SIZE DNSMASQ_LOG_QUERIES ENABLE_DIAGNOSTICS PROXY_CHECK_URL

cleanup_legacy_rules

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

if [ "${OVPN_PRESERVE_TEMPLATE}" != "1" ] && [ "${OVPN_PRESERVE_TEMPLATE}" != "true" ]; then
  cp /openvpn-defaults/server.conf.tpl "${OPENVPN_DIR}/server.conf.tpl"
elif [ ! -f "${OPENVPN_DIR}/server.conf.tpl" ]; then
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
  EASYRSA_PKI="$PKI_DIR" EASYRSA_REQ_CN="openvpn-out-ca" "$easyrsa_bin" --batch build-ca nopass
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
python3 /render_configs.py "$SING_BOX_CONF"
if [ "${DNSMASQ_ENABLED}" = "1" ] || [ "${DNSMASQ_ENABLED}" = "true" ]; then
  envsubst < /dnsmasq/dnsmasq.conf.tpl > /tmp/dnsmasq.conf
fi

echo "[4.1] generated sing-box config:" \
  && sed -E 's/("password"[[:space:]]*:[[:space:]]*)"[^"]*"/\1"***"/; s/("username"[[:space:]]*:[[:space:]]*)"[^"]*"/\1"***"/' "$SING_BOX_CONF" || true

log "[5] generating OpenVPN server config..."
envsubst < "${OPENVPN_DIR}/server.conf.tpl" > "$SERVER_CONF"
log "[5.1] generated OpenVPN server config:"
sed 's/^/  /' "$SERVER_CONF" || true

log "[6] enabling kernel forwarding..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null || log "warning: failed to set net.ipv4.ip_forward; make sure host enables IPv4 forwarding"

log "[7] starting sing-box TUN..."
sing-box run -c "$SING_BOX_CONF" &
SING_BOX_PID=$!
if ! wait_interface "$SING_TUN_NAME" 20; then
  log "sing-box TUN interface ${SING_TUN_NAME} was not created"
  exit 1
fi

log "[8] starting openvpn..."
openvpn --config "$SERVER_CONF" &
OPENVPN_PID=$!
if ! wait_ipv4 "$OVPN_DEV" "$OVPN_SERVER_IP" 30; then
  log "OpenVPN interface ${OVPN_DEV} did not get ${OVPN_SERVER_IP}"
  exit 1
fi

log "[9] configuring OpenVPN client policy route to sing-box TUN..."
while ip rule del from "${OVPN_CIDR}" table "${TABLE_ID}" 2>/dev/null; do :; done
ip route flush table "${TABLE_ID}" 2>/dev/null || true
ip route replace "${OVPN_CIDR}" dev "${OVPN_DEV}" table "${TABLE_ID}"
ip route replace default dev "${SING_TUN_NAME}" table "${TABLE_ID}"
ip rule add from "${OVPN_CIDR}" table "${TABLE_ID}" priority "${TABLE_PRIORITY}"

DNSMASQ_PID=""
if [ "${DNSMASQ_ENABLED}" = "1" ] || [ "${DNSMASQ_ENABLED}" = "true" ]; then
  log "[10] starting dnsmasq..."
  dnsmasq --no-daemon --conf-file=/tmp/dnsmasq.conf &
  DNSMASQ_PID=$!
fi

if [ "${ENABLE_DIAGNOSTICS}" = "1" ] || [ "${ENABLE_DIAGNOSTICS}" = "true" ]; then
  log "[diag] ip addr ${SING_TUN_NAME}"; ip addr show dev "${SING_TUN_NAME}" || true
  log "[diag] ip addr ${OVPN_DEV}"; ip addr show dev "${OVPN_DEV}" || true
  log "[diag] ip rule"; ip rule || true
  log "[diag] route table ${TABLE_ID}"; ip route show table "${TABLE_ID}" || true
  log "[diag] main route for sing-box TUN"; ip route | grep "${SING_TUN_NAME}" || true
  log "[diag] mangle PREROUTING"; iptables -t mangle -S PREROUTING || true
  log "[diag] nat PREROUTING"; iptables -t nat -S PREROUTING || true
  [ -f /tmp/dnsmasq.conf ] && { log "[diag] dnsmasq config"; cat /tmp/dnsmasq.conf; }
  (
    sleep 2
    log "[diag] checking outbound via curl..."
    case "${PROXY_TYPE}" in
      anytls)
        curl -fsS --connect-timeout 5 --max-time 12 --anyauth "${PROXY_CHECK_URL}" || true
        ;;
      *)
        curl -fsS --connect-timeout 5 --max-time 12 \
          --socks5-hostname "${PROXY_USER:+${PROXY_USER}:${PROXY_PASS}@}${PROXY_HOST}:${PROXY_PORT}" \
          "${PROXY_CHECK_URL}" || log "[diag] SOCKS5 outbound check failed"
        ;;
    esac
    if [ "${DNSMASQ_ENABLED}" = "1" ] || [ "${DNSMASQ_ENABLED}" = "true" ]; then
      log "[diag] checking dnsmasq query..."
      nslookup example.com "${OVPN_SERVER_IP}" || log "[diag] dnsmasq query failed"
    fi
  ) &
fi

wait -n "$SING_BOX_PID" "$OPENVPN_PID" ${DNSMASQ_PID:+"$DNSMASQ_PID"}
log "one process exited, stopping container..."
kill "$SING_BOX_PID" "$OPENVPN_PID" ${DNSMASQ_PID:+"$DNSMASQ_PID"} 2>/dev/null || true
wait || true
