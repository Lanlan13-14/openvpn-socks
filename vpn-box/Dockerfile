FROM alpine:3.20

ARG SING_BOX_VERSION=1.12.0
ARG TARGETARCH=amd64

RUN apk add --no-cache \
    bash \
    curl \
    ca-certificates \
    iproute2 \
    nftables \
    iptables \
    dnsmasq \
    openvpn \
    easy-rsa \
    gettext \
    openssl \
    tar

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) SB_ARCH="amd64" ;; \
      arm64) SB_ARCH="arm64" ;; \
      *) echo "unsupported arch: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    curl -L -o /tmp/sing-box.tar.gz \
      "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${SB_ARCH}.tar.gz"; \
    mkdir -p /tmp/sing-box; \
    tar -xzf /tmp/sing-box.tar.gz -C /tmp/sing-box --strip-components=1; \
    mv /tmp/sing-box/sing-box /usr/local/bin/sing-box; \
    chmod +x /usr/local/bin/sing-box; \
    rm -rf /tmp/sing-box /tmp/sing-box.tar.gz

COPY entrypoint.sh /entrypoint.sh
COPY openvpn /openvpn-defaults
COPY sing-box /sing-box
COPY dnsmasq /dnsmasq
COPY nft /nft

RUN chmod +x /entrypoint.sh && mkdir -p /etc/openvpn /etc/sing-box /openvpn /env

ENTRYPOINT ["/entrypoint.sh"]
