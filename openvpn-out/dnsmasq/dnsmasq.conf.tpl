port=${DNSMASQ_PORT}
listen-address=${OVPN_SERVER_IP}
bind-interfaces
no-resolv
no-hosts
cache-size=${DNSMASQ_CACHE_SIZE}
server=${DNSMASQ_UPSTREAM}
log-queries=${DNSMASQ_LOG_QUERIES}
