FROM alpine:3.19

# =========================
# 安装依赖
# =========================
RUN apk add --no-cache \
    openvpn \
    bash \
    curl \
    iproute2 \
    iptables \
    unzip \
    iperf3 \
    bc \
    tcptraceroute \
    cronie \
    gettext

# =========================
# 安装 Xray
# =========================
RUN curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip \
    && unzip xray.zip \
    && mv xray /usr/local/bin/ \
    && chmod +x /usr/local/bin/xray \
    && rm -rf xray.zip

# =========================
# 安装 tcping
# =========================
RUN curl -L --retry 3 --retry-delay 2 \
    https://raw.githubusercontent.com/Lanlan13-14/System-Easy/refs/heads/main/tcping.sh \
    -o /usr/local/bin/tcping \
    && chmod +x /usr/local/bin/tcping

# =========================
# 复制配置和入口脚本
# =========================
COPY entrypoint.sh /entrypoint.sh
COPY xray.json /etc/xray.json

RUN chmod +x /entrypoint.sh

# =========================
# 默认环境变量
# =========================
ENV SOCKS_PORT=1080 \
    RESTART_INTERVAL_HOURS=0 \
    VPN_USERNAME= \
    VPN_PASSWORD= \
    SOCKS_USER= \
    SOCKS_PASS= \
    OVPN_FILE=

# =========================
# 启动
# =========================
CMD ["/entrypoint.sh"]