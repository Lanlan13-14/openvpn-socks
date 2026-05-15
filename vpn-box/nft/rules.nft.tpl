flush table inet vpn_box_mangle

table inet vpn_box_mangle {
  chain prerouting {
    type filter hook prerouting priority mangle; policy accept;

    iifname != "${OVPN_DEV}" return
    ip daddr ${OVPN_CIDR} return
    udp dport ${DNSMASQ_PORT} return
    tcp dport ${DNSMASQ_PORT} return
    ip protocol { tcp, udp } meta mark set ${MARK} tproxy to :${TPROXY_PORT}
  }
}
