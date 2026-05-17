# openvpn-out

单容器 OpenVPN Server + sing-box TUN + Mix outbound 镜像。

镜像名：`ghcr.io/lanlan13-14/openvpn-out`

## 架构

```text
OpenVPN client
  -> OpenVPN Server inside container, interface ovpn0
  -> policy route from OpenVPN CIDR
  -> sing-box TUN interface sb-tun0
  -> anytls / shadowsocks 2022 / SOCKS5 outbound
```

DNS 默认链路：

```text
OpenVPN client DNS
  -> OpenVPN gateway 10.8.0.1:53
  -> dnsmasq cache
  -> sing-box TUN DNS address 172.19.0.2:53
  -> sing-box DNS hijack (explicit 172.19.0.2:53 rule)
  -> Remote DNS (DoH / DoT / plain DNS, via dns.server detour=proxy)
  -> SOCKS5 outbound
```

本镜像默认使用 sing-box TUN 作为 datapath，支持普通 DNS、DoH、DoT、DoQ 等远程 DNS 形态。

## Docker Compose 部署

推荐使用 Docker Compose 部署。示例使用 bridge 模式，并在 Compose 文件里限制 Docker 日志大小。

创建目录：

```bash
mkdir -p /opt/openvpn-out/env /opt/openvpn-out/openvpn
cd /opt/openvpn-out
```

创建 `docker-compose.yml`：

```yaml
version: "3.9"

services:
  openvpn-out:
    image: ghcr.io/lanlan13-14/openvpn-out:latest
    container_name: openvpn-out
    restart: unless-stopped
    network_mode: bridge
    ports:
      - "1194:1194/udp"
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    devices:
      - /dev/net/tun
    sysctls:
      net.ipv6.conf.all.forwarding: "1"
      net.ipv6.conf.default.forwarding: "1"
    volumes:
      - ./env:/env:ro
      - ./openvpn:/openvpn
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

日志限制说明：

- `max-size: "10m"`：单个容器日志文件最大 10 MB。
- `max-file: "3"`：最多保留 3 个日志文件。
- 这样可以避免 debug 日志把磁盘写满。

创建 `env/openvpn.env`：

```env
OVPN_PROTO=udp
OVPN_PORT=1194
OVPN_DEV=ovpn0
OVPN_DNS=auto
OVPN_NETWORK=10.8.0.0
OVPN_NETMASK=255.255.255.0
OVPN_CIDR=10.8.0.0/24
OVPN_SERVER_IP=10.8.0.1
OVPN_MAX_CLIENTS=1024
OVPN_DUPLICATE_CN=0
OVPN_CLIENT_TO_CLIENT=0
OVPN_CLIENT_NAME=client
OVPN_SERVER_ADDR=server.example.com
OVPN_CIPHER=AES-128-GCM
OVPN_DATA_CIPHERS=AES-128-GCM:AES-256-GCM:CHACHA20-POLY1305
OVPN_AUTH=SHA256
OVPN_TUN_MTU=1400
OVPN_MSSFIX=1360
OVPN_VERB=3
OVPN_PRESERVE_TEMPLATE=0
IPV6_ENABLED=0
OVPN_IPV6_CIDR=fd42:42:42:42::/64
```

创建 `env/proxy.env`：

```env
PROXY_TYPE=socks
PROXY_HOST=proxy.example.com
PROXY_PORT=12240
PROXY_USER=user
PROXY_PASS=pass
PROXY_PASSWORD=
PROXY_METHOD=2022-blake3-aes-128-gcm
PROXY_UDP_OVER_TCP=true
PROXY_UOT=0
PROXY_UOT_VERSION=2
PROXY_PLUGIN=
PROXY_PLUGIN_OPTS=
PROXY_NETWORK=
PROXY_TLS_SERVER_NAME=
PROXY_TLS_INSECURE=0
PROXY_TLS_ALPN=
```

无认证 SOCKS5 时把 `PROXY_USER` 和 `PROXY_PASS` 留空即可。

创建 `env/runtime.env`：

```env
MARK=1
TABLE_ID=100
TABLE_PRIORITY=10000
TPROXY_PORT=7893
TPROXY_BACKEND=tun
FULL_PROXY=1
SING_BOX_LOG_LEVEL=warning
SING_TUN_NAME=sb-tun0
SING_TUN_ADDRESS=172.19.0.1/30
SING_TUN_ADDRESS6=fd42:42:42:43::1/126
SING_TUN_DNS_ADDRESS=172.19.0.2
SING_TUN_MTU=9000
SING_TUN_STACK=mixed
DNS_SERVER_TYPE=https
DNS_SERVER=1.1.1.1
DNS_SERVER_PORT=443
DNS_PATH=/dns-query
DNS_TLS_SERVER_NAME=cloudflare-dns.com
DNS_TLS_INSECURE=0
DNS_TLS_ALPN=
DNS_DETOUR=proxy
DNS_STRATEGY=prefer_ipv4
DNSMASQ_ENABLED=1
DNSMASQ_PORT=53
DNSMASQ_UPSTREAM=172.19.0.2#53
DNSMASQ_CACHE_SIZE=0
DNSMASQ_LOG_QUERIES=0
ENABLE_DIAGNOSTICS=0
PROXY_CHECK_URL=https://www.cloudflare.com/cdn-cgi/trace
PROXY_CHECK_IPV6_URL=https://[2606:4700:4700::1111]/cdn-cgi/trace
```

启动：

```bash
docker compose up -d
```

查看日志：

```bash
docker compose logs -f --tail=100
```

首次启动时会在挂载的 `./openvpn` 目录中自动生成：

```text
openvpn/
├── pki/
└── clients/
    └── client.ovpn
```

客户端配置文件会保存为：

```text
./openvpn/clients/client.ovpn
```

多个设备复用同一个 `.ovpn`：

```env
OVPN_DUPLICATE_CN=1
```

所有变量既可以写入 `env/*.env`，也可以通过 Compose `environment` 直接定义。


## DNS 配置组合教程

本镜像的 DNS 链路由三层变量共同决定：

1. `OVPN_DNS`：OpenVPN 推送给客户端的 DNS。默认 `auto`，即推送 `OVPN_SERVER_IP`（默认 `10.8.0.1`）。
2. `DNSMASQ_ENABLED`：是否在容器内用 dnsmasq 监听 `OVPN_SERVER_IP:DNSMASQ_PORT`，作为客户端 DNS 入口和缓存层。
3. `DNS_SERVER_TYPE` / `DNS_SERVER` / `DNS_DETOUR`：sing-box 最终访问的远程 DNS，以及 DNS 查询是否走代理。

推荐保持 `OVPN_DNS=auto`、`DNSMASQ_ENABLED=1`。这样客户端只需要使用 OpenVPN 推送的 `10.8.0.1`，容器会自动把 DNS 转到 sing-box TUN DNS 地址 `172.19.0.2:53`，再按远程 DNS 配置解析。

### 组合速查

| 场景 | 适合用途 | 关键配置 | 说明 |
| --- | --- | --- | --- |
| 默认 DoH + 走代理 + dnsmasq | 最推荐，避免本地 DNS 泄漏 | `OVPN_DNS=auto`、`DNSMASQ_ENABLED=1`、`DNS_SERVER_TYPE=https`、`DNS_DETOUR=proxy` | 客户端 DNS -> dnsmasq -> sing-box -> DoH 远端，DNS 请求走上游代理。 |
| DoT/DoQ + 走代理 | 想用 TLS/QUIC DNS | `DNS_SERVER_TYPE=tls` 或 `quic`、`DNS_SERVER_PORT=853`、`DNS_DETOUR=proxy` | DNS 加密并走上游代理。 |
| 普通 UDP/TCP DNS + 走代理 | 上游只提供 53 端口 DNS | `DNS_SERVER_TYPE=udp` 或 `tcp`、`DNS_SERVER_PORT=53`、`DNS_DETOUR=proxy` | DNS 本身不加密，但请求仍从代理出口发出。 |
| 远程 DNS 直连 | 只想代理业务流量，DNS 由宿主网络直连 | `DNS_DETOUR=direct` | 可能暴露 DNS 查询给宿主机所在网络，不建议在防泄漏场景使用。 |
| 不启用 dnsmasq | 需要客户端直接打到 sing-box DNS | `DNSMASQ_ENABLED=0`、`OVPN_DNS=172.19.0.2` | 仅在客户端能路由到 `172.19.0.2` 时使用；否则客户端会无法解析。 |
| 自定义客户端 DNS | 客户端使用外部 DNS | `OVPN_DNS=8.8.8.8` 等 | 会绕过容器内 dnsmasq/sing-box DNS 链路，可能 DNS 泄漏。 |
| IPv6 优先/仅 IPv6 | IPv6 出口测试 | `IPV6_ENABLED=1`、`DNS_STRATEGY=prefer_ipv6` 或 `ipv6_only` | 需要上游代理、远程 DNS、目标网络都支持 IPv6。 |

### 1. 推荐默认：DoH + 走代理 + dnsmasq

适合大多数部署，DNS 查询随代理出口走，客户端不会直接访问公网 DNS。

`env/openvpn.env`：

```env
OVPN_DNS=auto
OVPN_SERVER_IP=10.8.0.1
```

`env/runtime.env`：

```env
DNSMASQ_ENABLED=1
DNSMASQ_PORT=53
DNSMASQ_UPSTREAM=172.19.0.2#53
DNS_SERVER_TYPE=https
DNS_SERVER=1.1.1.1
DNS_SERVER_PORT=443
DNS_PATH=/dns-query
DNS_TLS_SERVER_NAME=cloudflare-dns.com
DNS_DETOUR=proxy
DNS_STRATEGY=prefer_ipv4
```

可替换为 Google DoH：

```env
DNS_SERVER_TYPE=https
DNS_SERVER=8.8.8.8
DNS_SERVER_PORT=443
DNS_PATH=/dns-query
DNS_TLS_SERVER_NAME=dns.google
DNS_DETOUR=proxy
```

### 2. DoT：DNS over TLS + 走代理

适合使用 853 端口 TLS DNS。

```env
OVPN_DNS=auto
DNSMASQ_ENABLED=1
DNSMASQ_UPSTREAM=172.19.0.2#53
DNS_SERVER_TYPE=tls
DNS_SERVER=1.1.1.1
DNS_SERVER_PORT=853
DNS_TLS_SERVER_NAME=cloudflare-dns.com
DNS_DETOUR=proxy
DNS_STRATEGY=prefer_ipv4
```

Google DoT 可改为：

```env
DNS_SERVER=8.8.8.8
DNS_TLS_SERVER_NAME=dns.google
```

### 3. DoQ：DNS over QUIC + 走代理

适合远程 DNS 支持 QUIC 的场景。

```env
OVPN_DNS=auto
DNSMASQ_ENABLED=1
DNSMASQ_UPSTREAM=172.19.0.2#53
DNS_SERVER_TYPE=quic
DNS_SERVER=1.1.1.1
DNS_SERVER_PORT=853
DNS_TLS_SERVER_NAME=cloudflare-dns.com
DNS_DETOUR=proxy
DNS_STRATEGY=prefer_ipv4
```

### 4. DoH3：HTTP/3 DNS + 走代理

适合远程 DNS 支持 HTTP/3 的场景。

```env
OVPN_DNS=auto
DNSMASQ_ENABLED=1
DNSMASQ_UPSTREAM=172.19.0.2#53
DNS_SERVER_TYPE=h3
DNS_SERVER=1.1.1.1
DNS_SERVER_PORT=443
DNS_PATH=/dns-query
DNS_TLS_SERVER_NAME=cloudflare-dns.com
DNS_DETOUR=proxy
DNS_STRATEGY=prefer_ipv4
```

### 5. 普通 UDP DNS + 走代理

适合上游只提供传统 DNS 的场景。DNS 协议本身不加密，但请求会从 `proxy` 出站发出。

```env
OVPN_DNS=auto
DNSMASQ_ENABLED=1
DNSMASQ_UPSTREAM=172.19.0.2#53
DNS_SERVER_TYPE=udp
DNS_SERVER=8.8.8.8
DNS_SERVER_PORT=53
DNS_TLS_SERVER_NAME=
DNS_PATH=
DNS_DETOUR=proxy
DNS_STRATEGY=prefer_ipv4
```

### 6. 普通 TCP DNS + 走代理

```env
OVPN_DNS=auto
DNSMASQ_ENABLED=1
DNSMASQ_UPSTREAM=172.19.0.2#53
DNS_SERVER_TYPE=tcp
DNS_SERVER=8.8.8.8
DNS_SERVER_PORT=53
DNS_TLS_SERVER_NAME=
DNS_PATH=
DNS_DETOUR=proxy
DNS_STRATEGY=prefer_ipv4
```

### 7. DNS 直连，不走代理

只建议在你明确希望 DNS 使用宿主机网络出口时使用。业务流量仍会按 sing-box 路由走 `proxy`，但 DNS 查询由 `direct` 出站发出。

```env
OVPN_DNS=auto
DNSMASQ_ENABLED=1
DNSMASQ_UPSTREAM=172.19.0.2#53
DNS_SERVER_TYPE=https
DNS_SERVER=1.1.1.1
DNS_SERVER_PORT=443
DNS_PATH=/dns-query
DNS_TLS_SERVER_NAME=cloudflare-dns.com
DNS_DETOUR=direct
DNS_STRATEGY=prefer_ipv4
```

### 8. 关闭 dnsmasq，客户端直接使用 sing-box DNS

仅在客户端能访问 `SING_TUN_DNS_ADDRESS` 时使用。默认地址 `172.19.0.2` 是 sing-box TUN DNS 劫持地址。

```env
DNSMASQ_ENABLED=0
SING_TUN_DNS_ADDRESS=172.19.0.2
OVPN_DNS=172.19.0.2
DNS_SERVER_TYPE=https
DNS_SERVER=1.1.1.1
DNS_SERVER_PORT=443
DNS_PATH=/dns-query
DNS_TLS_SERVER_NAME=cloudflare-dns.com
DNS_DETOUR=proxy
DNS_STRATEGY=prefer_ipv4
```

如果客户端无法解析域名，改回推荐链路：

```env
OVPN_DNS=auto
DNSMASQ_ENABLED=1
DNSMASQ_UPSTREAM=172.19.0.2#53
```

### 9. 自定义推送给客户端的 DNS

如果设置外部 DNS，例如：

```env
OVPN_DNS=8.8.8.8
DNSMASQ_ENABLED=1
```

客户端会直接使用 `8.8.8.8`，不会经过容器内 dnsmasq 和 sing-box DNS 配置。该模式可能造成 DNS 泄漏，只建议在你明确需要外部 DNS 时使用。

如果只想改 OpenVPN 网关地址，请保持 `OVPN_DNS=auto`，改 `OVPN_SERVER_IP` 即可：

```env
OVPN_SERVER_IP=10.9.0.1
OVPN_DNS=auto
```

### 10. IPv6 DNS 策略组合

开启 IPv6 后，DNS 解析策略可按需要调整：

```env
IPV6_ENABLED=1
DNS_STRATEGY=prefer_ipv6
```

常用取值：

| `DNS_STRATEGY` | 效果 |
| --- | --- |
| `prefer_ipv4` | 默认，A/AAAA 都可用时优先 IPv4。 |
| `prefer_ipv6` | A/AAAA 都可用时优先 IPv6。 |
| `ipv4_only` | 只查询/返回 IPv4。 |
| `ipv6_only` | 只查询/返回 IPv6。 |

`ipv6_only` 需要上游代理和目标站点都支持 IPv6，否则可能出现能连 VPN 但部分网站打不开。

### DNS 排查

1. 开启诊断日志：

```env
ENABLE_DIAGNOSTICS=1
SING_BOX_LOG_LEVEL=debug
DNSMASQ_LOG_QUERIES=1
```

2. 重启容器后查看日志：

```bash
docker compose logs -f --tail=200
```

3. 在客户端检查 DNS 是否为 OpenVPN 推送地址：

```bash
nslookup example.com 10.8.0.1
```

4. 如果使用 `DNS_DETOUR=proxy`，但上游代理不支持 UDP，优先使用 `DNS_SERVER_TYPE=https` 或 `tls`，避免传统 UDP DNS 失败。

## docker run 示例

```bash
docker run -d \
  --name openvpn-out \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --device /dev/net/tun \
  -v /root/ovpn:/openvpn \
  -e OVPN_PROTO=tcp \
  -e OVPN_PORT=18383 \
  -e OVPN_DEV=ovpn0 \
  -e OVPN_SERVER_ADDR=server.example.com \
  -e OVPN_DUPLICATE_CN=1 \
  -e PROXY_HOST=proxy.example.com \
  -e PROXY_PORT=12240 \
  -e PROXY_USER='user' \
  -e PROXY_PASS='pass' \
  -e PROXY_UDP_OVER_TCP=true \
  -e DNS_SERVER=1.1.1.1 \
  -e DNS_SERVER_PORT=443 \
  -e DNS_PATH=/dns-query \
  -e DNS_TLS_SERVER_NAME=cloudflare-dns.com \
  -e DNS_DETOUR=proxy \
  -e DNS_STRATEGY=prefer_ipv4 \
  -e DNSMASQ_ENABLED=1 \
  -e IPV6_ENABLED=1 \
  -e OVPN_IPV6_CIDR=fd42:42:42:42::/64 \
  -e SING_BOX_LOG_LEVEL=warning \
  --restart unless-stopped \
  ghcr.io/lanlan13-14/openvpn-out:latest
```

无认证 SOCKS5 时去掉 `PROXY_USER` / `PROXY_PASS`。

`PROXY_UDP_OVER_TCP` 控制 sing-box 的 `udp_over_tcp`，不是原生 UDP 开关。旧变量 `PROXY_UDP` 仍兼容，但推荐使用 `PROXY_UDP_OVER_TCP`。

### 1. 普通 SOCKS

```bash
docker run -d \
  --name openvpn-out \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --device /dev/net/tun \
  -v /root/openvpn-out:/openvpn \
  -e OVPN_SERVER_ADDR=server.example.com \
  -e OVPN_PORT=1194 \
  -e PROXY_TYPE=socks \
  -e PROXY_HOST=proxy.example.com \
  -e PROXY_PORT=12240 \
  -e PROXY_USER='user' \
  -e PROXY_PASS='pass' \
  -e PROXY_UDP_OVER_TCP=true \
  ghcr.io/lanlan13-14/openvpn-out:latest
```

### 2. 普通 SS + UoT

```bash
docker run -d \
  --name openvpn-out \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --device /dev/net/tun \
  -v /root/openvpn-out:/openvpn \
  -e OVPN_SERVER_ADDR=server.example.com \
  -e OVPN_PORT=1194 \
  -e PROXY_TYPE=shadowsocks \
  -e PROXY_HOST=proxy.example.com \
  -e PROXY_PORT=8388 \
  -e PROXY_METHOD=aes-128-gcm \
  -e PROXY_PASSWORD='ss-password' \
  -e PROXY_UOT=1 \
  -e PROXY_UOT_VERSION=2 \
  ghcr.io/lanlan13-14/openvpn-out:latest
```

### 3. SS2022 / AnyTLS 示例

SS2022：

```bash
docker run -d \
  --name openvpn-out \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --device /dev/net/tun \
  -v /root/openvpn-out:/openvpn \
  -e OVPN_SERVER_ADDR=server.example.com \
  -e OVPN_PORT=1194 \
  -e PROXY_TYPE=ss2022 \
  -e PROXY_HOST=proxy.example.com \
  -e PROXY_PORT=8388 \
  -e PROXY_METHOD=2022-blake3-aes-128-gcm \
  -e PROXY_PASSWORD='ss2022-password' \
  ghcr.io/lanlan13-14/openvpn-out:latest
```

AnyTLS：

```bash
docker run -d \
  --name openvpn-out \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --device /dev/net/tun \
  -v /root/openvpn-out:/openvpn \
  -e OVPN_SERVER_ADDR=server.example.com \
  -e OVPN_PORT=1194 \
  -e PROXY_TYPE=anytls \
  -e PROXY_HOST=proxy.example.com \
  -e PROXY_PORT=443 \
  -e PROXY_PASSWORD='anytls-password' \
  -e PROXY_TLS_SERVER_NAME=proxy.example.com \
  ghcr.io/lanlan13-14/openvpn-out:latest
```


所有变量既可以写入 `env/*.env`，也可以通过 `docker run -e` 或 Compose `environment` 直接定义。

### OpenVPN

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `OVPN_PROTO` | `udp` | OpenVPN 协议 |
| `OVPN_PORT` | `1194` | OpenVPN 端口 |
| `OVPN_DEV` | `ovpn0` | OpenVPN 服务端 tun 设备名 |
| `OVPN_DNS` | `auto` | 推送给客户端的 DNS；默认使用 `OVPN_SERVER_IP` |
| `OVPN_NETWORK` | `10.8.0.0` | VPN 网段 |
| `OVPN_NETMASK` | `255.255.255.0` | VPN 掩码 |
| `OVPN_CIDR` | `10.8.0.0/24` | VPN CIDR，用于策略路由 |
| `OVPN_SERVER_IP` | `10.8.0.1` | OpenVPN 网段网关 |
| `OVPN_MAX_CLIENTS` | `1024` | 最大客户端数量 |
| `OVPN_DUPLICATE_CN` | `0` | 设为 `1` 允许多个设备复用同一客户端证书 |
| `OVPN_CLIENT_TO_CLIENT` | `0` | 客户端互通开关 |
| `OVPN_CLIENT_NAME` | `client` | 自动生成的客户端名称 |
| `OVPN_SERVER_ADDR` | 自动公网 IP | 写入客户端配置的服务端地址 |
| `OVPN_CIPHER` | `AES-128-GCM` | fallback cipher |
| `OVPN_DATA_CIPHERS` | `AES-128-GCM:AES-256-GCM:CHACHA20-POLY1305` | DCO 友好的 AEAD cipher 列表 |
| `OVPN_AUTH` | `SHA256` | auth digest |
| `OVPN_TUN_MTU` | `1400` | OpenVPN TUN 设备 MTU，对应 `tun-mtu` |
| `OVPN_MSSFIX` | `1360` | OpenVPN TCP MSS 限制，对应 `mssfix`，用于降低路径 MTU 问题 |
| `OVPN_VERB` | `3` | OpenVPN 日志级别 |
| `OVPN_PRESERVE_TEMPLATE` | `0` | 默认覆盖挂载目录旧 `server.conf.tpl`，设为 `1` 保留用户自定义模板 |
| `IPV6_ENABLED` | `0` | IPv6 开关；设为 `1` 时启用 OpenVPN IPv6 地址池、sing-box TUN IPv6 地址和 IPv6 策略路由 |
| `OVPN_IPV6_CIDR` | `fd42:42:42:42::/64` | OpenVPN IPv6 ULA 地址池 |

### sing-box TUN / 路由

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `TPROXY_BACKEND` | `tun` | 保留兼容变量；当前默认 datapath 为 sing-box TUN |
| `PROXY_TYPE` | `socks` | 上游出站类型：`socks`、`anytls`、`shadowsocks`、`ss`、`ss2022` |
| `PROXY_PASSWORD` | 空 | AnyTLS / Shadowsocks 密码 |
| `PROXY_METHOD` | `2022-blake3-aes-128-gcm` | Shadowsocks 加密方法；非 2022 也可配置 |
| `PROXY_UOT` | `0` | 是否启用 UoT（UDP over TCP） |
| `PROXY_UOT_VERSION` | `2` | UoT 版本：`1` 或 `2` |
| `PROXY_PLUGIN` | 空 | Shadowsocks SIP003 插件名 |
| `PROXY_PLUGIN_OPTS` | 空 | Shadowsocks 插件参数 |
| `PROXY_NETWORK` | 空 | Shadowsocks 启用网络：`tcp,udp` |
| `PROXY_TLS_SERVER_NAME` | 空 | AnyTLS TLS SNI |
| `PROXY_TLS_INSECURE` | `0` | AnyTLS 是否忽略证书校验 |
| `PROXY_TLS_ALPN` | 空 | AnyTLS TLS ALPN，逗号分隔 |
| `TABLE_ID` | `100` | OpenVPN CIDR 策略路由表 |
| `TABLE_PRIORITY` | `10000` | 策略路由优先级 |
| `SING_TUN_NAME` | `sb-tun0` | sing-box TUN 接口名 |
| `SING_TUN_ADDRESS` | `172.19.0.1/30` | sing-box TUN IPv4 地址 |
| `SING_TUN_ADDRESS6` | `fd42:42:42:43::1/126` | sing-box TUN IPv6 地址，`IPV6_ENABLED=1` 时生效 |
| `SING_TUN_DNS_ADDRESS` | `172.19.0.2` | sing-box TUN DNS 劫持地址 |
| `SING_TUN_MTU` | `9000` | sing-box TUN MTU |
| `SING_TUN_STACK` | `mixed` | sing-box TUN stack：`system`、`gvisor`、`mixed` |

### SOCKS5 outbound

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PROXY_HOST` | 必填 | 上游 SOCKS5 地址 |
| `PROXY_PORT` | 必填 | 上游 SOCKS5 端口 |
| `PROXY_USER` | 空 | 上游 SOCKS5 用户名 |
| `PROXY_PASS` | 空 | 上游 SOCKS5 密码 |
| `PROXY_UDP_OVER_TCP` | `true` | 是否启用 sing-box `udp_over_tcp`；变量名更明确，旧变量 `PROXY_UDP` 仍兼容 |

### DNS

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `DNS_SERVER_TYPE` | `https` | 远程 DNS 服务器类型：`udp`、`tcp`、`tls`、`quic`、`https`、`h3` |
| `DNS_SERVER` | `1.1.1.1` | 远程 DNS 服务器地址 |
| `DNS_SERVER_PORT` | `443` | 远程 DNS 端口；普通 DNS 一般为 `53`，DoT/DoQ 常用 `853` |
| `DNS_PATH` | `/dns-query` | 远程 HTTPS/H3 DNS 路径 |
| `DNS_TLS_SERVER_NAME` | `cloudflare-dns.com` | TLS 相关 DNS 的 SNI / 证书域名 |
| `DNS_DETOUR` | `proxy` | DNS 查询出站：`proxy` 走上游，`direct` 直连；默认强制走代理 |
| `DNS_STRATEGY` | `prefer_ipv4` | `prefer_ipv4`、`prefer_ipv6`、`ipv4_only`、`ipv6_only` |
| `DNSMASQ_ENABLED` | `1` | 启用 dnsmasq 作为客户端 DNS 缓存层 |
| `DNSMASQ_PORT` | `53` | dnsmasq 监听端口 |
| `DNSMASQ_UPSTREAM` | `172.19.0.2#53` | dnsmasq 上游，默认 sing-box TUN DNS 地址 |
| `DNSMASQ_CACHE_SIZE` | `0` | dnsmasq 缓存条目数；默认 `0` 表示禁用缓存 |
| `DNSMASQ_LOG_QUERIES` | `0` | dnsmasq 查询日志开关 |

### 诊断

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SING_BOX_LOG_LEVEL` | `warning` | sing-box 日志级别 |
| `ENABLE_DIAGNOSTICS` | `0` | 设为 `1` 打印 sing-box 配置、接口、策略路由、iptables 规则并做 SOCKS/DoH 检测 |
| `PROXY_CHECK_URL` | `https://www.cloudflare.com/cdn-cgi/trace` | 诊断模式下测试 TCP 出站的 URL |
| `PROXY_CHECK_IPV6_URL` | `https://[2606:4700:4700::1111]/cdn-cgi/trace` | 诊断模式下测试 IPv6 目标出站的 URL；SOCKS 场景下不强制 curl 以 IPv6 连接 SOCKS 服务器 |

## br-lan 模式（OpenWrt / 路由器场景）

如果你的宿主机是 OpenWrt，或者希望服务跑在 `br-lan` 场景下，可以使用 **bridge 模式**：

1. 容器使用 `--network bridge`，不要用 `host`。
2. 通过 `-p` 把 OpenVPN 端口映射到宿主机 LAN 口可达地址。
3. 如果开启 `IPV6_ENABLED=1`，建议给容器增加 `--sysctl net.ipv6.conf.all.forwarding=1` 和 `--sysctl net.ipv6.conf.default.forwarding=1`。
4. 把 `OVPN_SERVER_ADDR` 设置为 `br-lan` 对应的 LAN IPv4 地址。
5. 确保路由器防火墙允许 `OVPN_PORT` 从 LAN 侧入站。
6. 如果宿主机本身就是网关，`dnsmasq` 仍然可以正常做客户端 DNS 缓存层。
7. 其他 OpenVPN / sing-box 环境变量保持不变。

示例：

```bash
docker run -d \
  --name openvpn-out \
  --network bridge \
  -p 1194:1194/udp \
  --sysctl net.ipv6.conf.all.forwarding=1 \
  --sysctl net.ipv6.conf.default.forwarding=1 \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --device /dev/net/tun \
  -v /root/openvpn-out:/openvpn \
  -e OVPN_SERVER_ADDR=192.168.1.1 \
  -e OVPN_PORT=1194 \
  -e IPV6_ENABLED=1 \
  -e OVPN_IPV6_CIDR=fd42:42:42:42::/64 \
  -e PROXY_TYPE=shadowsocks \
  -e PROXY_HOST=proxy.example.com \
  -e PROXY_PORT=8388 \
  -e PROXY_METHOD=2022-blake3-aes-128-gcm \
  -e PROXY_PASSWORD='your-password' \
  ghcr.io/lanlan13-14/openvpn-out:latest
```


OpenVPN 2.6 会在配置和宿主机内核支持时机会性使用 DCO。DCO 需要宿主机支持并加载 `ovpn-dco` 内核模块。

```bash
modprobe ovpn-dco
```

## 注意

- 推荐 `network_mode: host` / `--network host`。
- 需要 `NET_ADMIN` 和 `/dev/net/tun`。
- 当前 datapath 是 sing-box TUN：`OpenVPN ovpn0 -> ip rule from OVPN_CIDR -> sb-tun0 -> SOCKS5`。
- 容器启动会清理旧版 vpn-box 遗留的 TPROXY / DNS REDIRECT / fwmark 规则。
- 如果挂载目录已有旧 `server.conf.tpl`，默认会覆盖为镜像内新模板；如需保留自定义模板，设置 `OVPN_PRESERVE_TEMPLATE=1`。
