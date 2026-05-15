port ${OVPN_PORT}
proto ${OVPN_PROTO}
dev ${OVPN_DEV}
dev-type tun
topology subnet

server ${OVPN_NETWORK} ${OVPN_NETMASK}

ca /openvpn/pki/ca.crt
cert /openvpn/pki/issued/server.crt
key /openvpn/pki/private/server.key
dh none
tls-groups secp256r1

tls-crypt /openvpn/pki/ta.key

push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS ${OVPN_DNS}"
max-clients ${OVPN_MAX_CLIENTS}
${OVPN_DUPLICATE_CN_CONFIG}
${OVPN_CLIENT_TO_CLIENT_CONFIG}

data-ciphers ${OVPN_DATA_CIPHERS}
data-ciphers-fallback ${OVPN_CIPHER}
auth ${OVPN_AUTH}

keepalive 10 120
persist-key
persist-tun

fast-io
sndbuf 0
rcvbuf 0

user nobody
group nobody

verb ${OVPN_VERB}
