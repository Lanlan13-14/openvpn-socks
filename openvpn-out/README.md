# openvpn-out

单容器 OpenVPN Server + sing-box TUN + SOCKS5 outbound 镜像。

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

## 使用

```bash
cd openvpn-out
docker compose up -d --build
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

```bash
-e OVPN_DUPLICATE_CN=1
```

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
  -e PROXY_UDP=true \
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
  -e PROXY_UDP=true \
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
| `SING_TUN_MTU` | `1500` | sing-box TUN MTU |
| `SING_TUN_STACK` | `mixed` | sing-box TUN stack：`system`、`gvisor`、`mixed` |

### SOCKS5 outbound

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PROXY_HOST` | 必填 | 上游 SOCKS5 地址 |
| `PROXY_PORT` | 必填 | 上游 SOCKS5 端口 |
| `PROXY_USER` | 空 | 上游 SOCKS5 用户名 |
| `PROXY_PASS` | 空 | 上游 SOCKS5 密码 |
| `PROXY_UDP` | `true` | sing-box `udp_over_tcp` |

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
| `PROXY_CHECK_URL` | `https://www.cloudflare.com/cdn-cgi/trace` | 诊断模式下测试 SOCKS5 TCP 出站的 URL |

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
