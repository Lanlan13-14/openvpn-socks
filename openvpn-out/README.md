# openvpn-out

单容器 OpenVPN Server + sing-box TUN + Mix outbound 镜像。

镜像名：`ghcr.io/lanlan13-14/openvpn-out`

`openvpn-out` 会在一个容器内启动 OpenVPN Server、dnsmasq 和 sing-box：OpenVPN 客户端连入后，客户端流量按来源网段策略路由到 sing-box TUN，再通过上游代理出站。默认上游是 SOCKS5，也支持 AnyTLS、Shadowsocks、SS2022 和 UoT。

## 工作链路

数据链路：

```text
OpenVPN client
  -> OpenVPN Server inside container, interface ovpn0
  -> policy route from OpenVPN CIDR
  -> sing-box TUN interface sb-tun0
  -> SOCKS5 / AnyTLS / Shadowsocks / SS2022 outbound
```

DNS 链路：

```text
OpenVPN client DNS
  -> OpenVPN gateway 10.8.0.1:53
  -> dnsmasq (cache disabled by default)
  -> sing-box TUN DNS address 172.19.0.2:53
  -> sing-box hijack-dns
  -> remote DNS server with detour=proxy
  -> outbound proxy
```

说明：

- `172.19.0.2` 是 sing-box TUN 内部 DNS 劫持目标地址，不是公网地址。
- `DNS_DETOUR=proxy` 会让 sing-box DNS 模块访问上游 DNS 时走代理。
- dnsmasq 默认 `cache-size=0`，不缓存 DNS。

## 快速部署：Docker Compose

推荐使用 Compose 部署，默认示例使用 bridge 模式并限制 Docker 日志大小。

```bash
mkdir -p /opt/openvpn-out
cd /opt/openvpn-out
curl -fsSLO https://raw.githubusercontent.com/Lanlan13-14/openvpn-socks/main/openvpn-out/docker-compose.yml
mkdir -p env openvpn
```

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
OVPN_DUPLICATE_CN=1
OVPN_SERVER_ADDR=server.example.com
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
PROXY_UDP=true
```

创建 `env/runtime.env`：

```env
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
DNS_DETOUR=proxy
DNS_STRATEGY=prefer_ipv4
DNSMASQ_ENABLED=1
DNSMASQ_PORT=53
DNSMASQ_UPSTREAM=172.19.0.2#53
DNSMASQ_CACHE_SIZE=0
DNSMASQ_LOG_QUERIES=0
ENABLE_DIAGNOSTICS=0
```

启动：

```bash
docker compose up -d
```

查看日志：

```bash
docker compose logs -f --tail=100
```

首次启动会在 `./openvpn` 目录生成：

```text
openvpn/
├── pki/
└── clients/
    └── client.ovpn
```

客户端配置文件路径：

```text
./openvpn/clients/client.ovpn
```

## Docker Compose 文件说明

仓库内置 `docker-compose.yml` 已包含日志限制：

```yaml
logging:
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"
```

这会把单个容器日志文件限制为 10 MB，最多保留 3 个文件，避免 debug 日志撑爆磁盘。

## docker run 部署示例

### bridge 模式（推荐用于 OpenWrt / br-lan 场景）

bridge 模式需要把 OpenVPN 端口映射出来。如果开启 IPv6，建议加上 IPv6 sysctl。

```bash
docker rm -f openvpn-out 2>/dev/null || true
docker pull ghcr.io/lanlan13-14/openvpn-out:latest

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
  -e OVPN_PROTO=udp \
  -e OVPN_PORT=1194 \
  -e OVPN_SERVER_ADDR=server.example.com \
  -e OVPN_DUPLICATE_CN=1 \
  -e PROXY_TYPE=socks \
  -e PROXY_HOST=proxy.example.com \
  -e PROXY_PORT=12240 \
  -e PROXY_USER='user' \
  -e PROXY_PASS='pass' \
  -e PROXY_UDP=true \
  -e DNS_SERVER_TYPE=https \
  -e DNS_SERVER=1.1.1.1 \
  -e DNS_SERVER_PORT=443 \
  -e DNS_PATH=/dns-query \
  -e DNS_TLS_SERVER_NAME=cloudflare-dns.com \
  -e DNS_DETOUR=proxy \
  -e DNSMASQ_CACHE_SIZE=0 \
  -e SING_TUN_MTU=9000 \
  --log-driver json-file \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  --restart unless-stopped \
  ghcr.io/lanlan13-14/openvpn-out:latest
```

### host 模式

host 模式不需要端口映射，适合普通 Linux 服务器直接监听宿主机端口：

```bash
docker run -d \
  --name openvpn-out \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --device /dev/net/tun \
  -v /root/openvpn-out:/openvpn \
  -e OVPN_PROTO=tcp \
  -e OVPN_PORT=18383 \
  -e OVPN_SERVER_ADDR=server.example.com \
  -e PROXY_TYPE=socks \
  -e PROXY_HOST=proxy.example.com \
  -e PROXY_PORT=12240 \
  -e PROXY_USER='user' \
  -e PROXY_PASS='pass' \
  --log-driver json-file \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  --restart unless-stopped \
  ghcr.io/lanlan13-14/openvpn-out:latest
```

## 出站类型示例

### 1. 普通 SOCKS5

```env
PROXY_TYPE=socks
PROXY_HOST=proxy.example.com
PROXY_PORT=12240
PROXY_USER=user
PROXY_PASS=pass
PROXY_UDP=true
```

### 2. 普通 Shadowsocks + UoT

```env
PROXY_TYPE=shadowsocks
PROXY_HOST=proxy.example.com
PROXY_PORT=8388
PROXY_METHOD=aes-128-gcm
PROXY_PASSWORD=ss-password
PROXY_UOT=1
PROXY_UOT_VERSION=2
```

### 3. SS2022

```env
PROXY_TYPE=ss2022
PROXY_HOST=proxy.example.com
PROXY_PORT=8388
PROXY_METHOD=2022-blake3-aes-128-gcm
PROXY_PASSWORD=ss2022-password
```

### 4. AnyTLS

```env
PROXY_TYPE=anytls
PROXY_HOST=proxy.example.com
PROXY_PORT=443
PROXY_PASSWORD=anytls-password
PROXY_TLS_SERVER_NAME=proxy.example.com
```

## IPv6

IPv6 默认关闭。开启方式：

```env
IPV6_ENABLED=1
OVPN_IPV6_CIDR=fd42:42:42:42::/64
SING_TUN_ADDRESS6=fd42:42:42:43::1/126
```

bridge 模式下建议同时给容器加：

```bash
--sysctl net.ipv6.conf.all.forwarding=1 \
--sysctl net.ipv6.conf.default.forwarding=1
```

如果宿主机也未开启 IPv6 转发，需要在宿主机执行：

```bash
sysctl -w net.ipv6.conf.all.forwarding=1
sysctl -w net.ipv6.conf.default.forwarding=1
```

诊断日志中如果出现：

```text
net.ipv6.conf.all.forwarding = 0
```

说明 IPv6 forwarding 没有生效。

## 环境变量

所有变量既可以写入 `env/*.env`，也可以通过 `docker run -e` 或 Compose `environment` 直接定义。

### OpenVPN

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `OVPN_PROTO` | `udp` | OpenVPN 协议 |
| `OVPN_PORT` | `1194` | OpenVPN 端口 |
| `OVPN_DEV` | `ovpn0` | OpenVPN 服务端 tun 设备名 |
| `OVPN_DNS` | `auto` | 推送给客户端的 DNS；默认使用 `OVPN_SERVER_IP` |
| `OVPN_NETWORK` | `10.8.0.0` | VPN IPv4 网段 |
| `OVPN_NETMASK` | `255.255.255.0` | VPN IPv4 掩码 |
| `OVPN_CIDR` | `10.8.0.0/24` | VPN IPv4 CIDR，用于策略路由 |
| `OVPN_SERVER_IP` | `10.8.0.1` | OpenVPN IPv4 网关 |
| `OVPN_MAX_CLIENTS` | `1024` | 最大客户端数量 |
| `OVPN_DUPLICATE_CN` | `0` | 设为 `1` 允许多个设备复用同一客户端证书 |
| `OVPN_CLIENT_TO_CLIENT` | `0` | 客户端互通开关 |
| `OVPN_CLIENT_NAME` | `client` | 自动生成的客户端名称 |
| `OVPN_SERVER_ADDR` | 自动公网 IP | 写入客户端配置的服务端地址 |
| `OVPN_CIPHER` | `AES-128-GCM` | fallback cipher |
| `OVPN_DATA_CIPHERS` | `AES-128-GCM:AES-256-GCM:CHACHA20-POLY1305` | DCO 友好的 AEAD cipher 列表 |
| `OVPN_AUTH` | `SHA256` | auth digest |
| `OVPN_VERB` | `3` | OpenVPN 日志级别 |
| `OVPN_PRESERVE_TEMPLATE` | `0` | 默认覆盖挂载目录旧 `server.conf.tpl`，设为 `1` 保留用户自定义模板 |
| `IPV6_ENABLED` | `0` | IPv6 开关 |
| `OVPN_IPV6_CIDR` | `fd42:42:42:42::/64` | OpenVPN IPv6 ULA 地址池 |

### sing-box TUN / 路由

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PROXY_TYPE` | `socks` | 上游出站类型：`socks`、`anytls`、`shadowsocks`、`ss`、`ss2022` |
| `PROXY_HOST` | 必填 | 上游地址 |
| `PROXY_PORT` | 必填 | 上游端口 |
| `PROXY_USER` | 空 | SOCKS5 用户名 |
| `PROXY_PASS` | 空 | SOCKS5 密码 |
| `PROXY_PASSWORD` | 空 | AnyTLS / Shadowsocks 密码 |
| `PROXY_METHOD` | `2022-blake3-aes-128-gcm` | Shadowsocks 加密方法 |
| `PROXY_UDP` | `true` | SOCKS5 `udp_over_tcp` 开关 |
| `PROXY_UOT` | `0` | Shadowsocks UoT 开关 |
| `PROXY_UOT_VERSION` | `2` | UoT 版本：`1` 或 `2` |
| `PROXY_PLUGIN` | 空 | Shadowsocks SIP003 插件名 |
| `PROXY_PLUGIN_OPTS` | 空 | Shadowsocks 插件参数 |
| `PROXY_NETWORK` | 空 | Shadowsocks 启用网络：`tcp,udp` |
| `PROXY_TLS_SERVER_NAME` | 空 | AnyTLS TLS SNI |
| `PROXY_TLS_INSECURE` | `0` | AnyTLS 是否忽略证书校验 |
| `PROXY_TLS_ALPN` | 空 | AnyTLS TLS ALPN，逗号分隔 |
| `TABLE_ID` | `100` | 策略路由表 |
| `TABLE_PRIORITY` | `10000` | 策略路由优先级 |
| `SING_TUN_NAME` | `sb-tun0` | sing-box TUN 接口名 |
| `SING_TUN_ADDRESS` | `172.19.0.1/30` | sing-box TUN IPv4 地址 |
| `SING_TUN_ADDRESS6` | `fd42:42:42:43::1/126` | sing-box TUN IPv6 地址，`IPV6_ENABLED=1` 时生效 |
| `SING_TUN_DNS_ADDRESS` | `172.19.0.2` | sing-box TUN DNS 劫持地址 |
| `SING_TUN_MTU` | `9000` | sing-box TUN MTU |
| `SING_TUN_STACK` | `mixed` | sing-box TUN stack：`system`、`gvisor`、`mixed` |

### DNS

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `DNS_SERVER_TYPE` | `https` | 远程 DNS 服务器类型：`udp`、`tcp`、`tls`、`quic`、`https`、`h3` |
| `DNS_SERVER` | `1.1.1.1` | 远程 DNS 服务器地址 |
| `DNS_SERVER_PORT` | `443` | 远程 DNS 端口；普通 DNS 一般为 `53`，DoT/DoQ 常用 `853` |
| `DNS_PATH` | `/dns-query` | 远程 HTTPS/H3 DNS 路径 |
| `DNS_TLS_SERVER_NAME` | `cloudflare-dns.com` | TLS 相关 DNS 的 SNI / 证书域名 |
| `DNS_DETOUR` | `proxy` | DNS 查询出站：`proxy` 走上游，`direct` 直连 |
| `DNS_STRATEGY` | `prefer_ipv4` | `prefer_ipv4`、`prefer_ipv6`、`ipv4_only`、`ipv6_only` |
| `DNSMASQ_ENABLED` | `1` | 启用 dnsmasq 作为客户端 DNS 层 |
| `DNSMASQ_PORT` | `53` | dnsmasq 监听端口 |
| `DNSMASQ_UPSTREAM` | `172.19.0.2#53` | dnsmasq 上游，默认 sing-box TUN DNS 地址 |
| `DNSMASQ_CACHE_SIZE` | `0` | dnsmasq 缓存条目数；默认 `0` 表示禁用缓存 |
| `DNSMASQ_LOG_QUERIES` | `0` | dnsmasq 查询日志开关 |

### 诊断

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SING_BOX_LOG_LEVEL` | `warning` | sing-box 日志级别 |
| `ENABLE_DIAGNOSTICS` | `0` | 设为 `1` 打印配置、接口、路由和出站检测信息 |
| `PROXY_CHECK_URL` | `https://www.cloudflare.com/cdn-cgi/trace` | 诊断模式下测试 TCP 出站的 URL |
| `PROXY_CHECK_IPV6_URL` | `https://[2606:4700:4700::1111]/cdn-cgi/trace` | 诊断模式下测试 IPv6 目标出站的 URL |

## 注意事项

- 必须提供 `NET_ADMIN` 和 `/dev/net/tun`。
- 推荐限制容器日志大小，尤其开启 `SING_BOX_LOG_LEVEL=debug` 或 `ENABLE_DIAGNOSTICS=1` 时。
- bridge 模式需要映射 OpenVPN 端口；host 模式不需要 `-p`。
- 如果挂载目录已有旧 `server.conf.tpl`，默认会覆盖为镜像内新模板；如需保留自定义模板，设置 `OVPN_PRESERVE_TEMPLATE=1`。
- 容器启动会清理旧版 vpn-box 遗留的 TPROXY / DNS REDIRECT / fwmark 规则。
