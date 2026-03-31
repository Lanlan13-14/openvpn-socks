FROM alpine:3.19

RUN apk add --no-cache \
    openvpn \
    bash \
    curl \
    iproute2 \
    iptables

# 安装 Xray
RUN curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip \
    && unzip xray.zip \
    && mv xray /usr/local/bin/ \
    && chmod +x /usr/local/bin/xray \
    && rm -rf xray.zip

COPY entrypoint.sh /entrypoint.sh
COPY xray.json /etc/xray.json

RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]