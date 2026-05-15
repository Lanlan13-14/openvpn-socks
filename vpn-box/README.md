# ovpn-socks-out

单容器 OpenVPN Server + sing-box TProxy + SOCKS5 outbound 镜像。

镜像名：`ghcr.io/lanlan13-14/ovpn-socks-out`

## 架构

```text
OpenVPN client
  -> OpenVPN Server inside container
  -> client DNS points to OpenVPN gateway
  -> sing-box DNS remote resolver via SOCKS5
  -> nftables TPROXY
  -> sing-box tproxy inbound
  -> upstream SOCKS5 outbound
```


## 目录

```text
vpn-box/
├── Dockerfile
├── docker-compose.yml
├── entrypoint.sh
├── openvpn/
│   └── server.conf.tpl
├── sing-box/
│   ├── config.auth.tpl.json
│   └── config.noauth.tpl.json
├── nft/
│   └── rules.nft.tpl
└── env/
    ├── openvpn.env
    ├── proxy.env
    └── runtime.env
```

## 使用

```bash
cd vpn-box

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

如果需要指定客户端名称：

```bash
docker run ... -e OVPN_CLIENT_NAME=phone ...
```

则生成：

```text
./openvpn/clients/phone.ovpn
```

如果需要让多个设备直接复用同一个 `.ovpn` 文件，可设置：

```bash
-e OVPN_DUPLICATE_CN=1
```

该模式会在 OpenVPN 服务端开启 `duplicate-cn`，方便多个设备使用同一客户端证书同时连接。

## docker run 示例

无认证 SOCKS5：

```bash
docker run -d \
  --name vpn-box \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --device /dev/net/tun \
  -v "$PWD/openvpn:/openvpn" \
  -e PROXY_HOST=1.2.3.4 \
  -e PROXY_PORT=1080 \
  -e PROXY_UDP=true \
  -e DNS_STRATEGY=prefer_ipv4 \
  -e DNS_SERVER=1.1.1.1 \
  -e DNS_TLS_SERVER_NAME=cloudflare-dns.com \
  -e DNS_PATH=/dns-query \
  -e OVPN_DEV=ovpn0 \
  ghcr.io/lanlan13-14/ovpn-socks-out:latest
```

有认证 SOCKS5：

```bash
docker run -d \
  --name vpn-box \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --device /dev/net/tun \
  -v "$PWD/openvpn:/openvpn" \
  -e PROXY_HOST=1.2.3.4 \
  -e PROXY_PORT=1080 \
  -e PROXY_USER=user \
  -e PROXY_PASS=pass \
  -e PROXY_UDP=true \
  -e DNS_STRATEGY=prefer_ipv4 \
  -e DNS_SERVER=1.1.1.1 \
  -e DNS_TLS_SERVER_NAME=cloudflare-dns.com \
  -e DNS_PATH=/dns-query \
  -e OVPN_DEV=ovpn0 \
  ghcr.io/lanlan13-14/ovpn-socks-out:latest
```

## 环境变量

所有变量既可以写入 `env/*.env`，也可以通过 `docker run -e` 或 Compose `environment` 直接定义。

### OpenVPN

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `OVPN_PROTO` | `udp` | OpenVPN 协议 |
| `OVPN_PORT` | `1194` | OpenVPN 端口 |
| `OVPN_DEV` | `ovpn0` | OpenVPN 服务端 tun 设备名；模板使用 `dev-type tun`，因此这里可用 `ovpn0` 避免 host network 下 `tun0` 冲突 |
| `OVPN_DNS` | `auto` | 推送给客户端的 DNS；`auto` 表示使用 `OVPN_SERVER_IP`，即 OpenVPN 网段网关 |
| `OVPN_NETWORK` | `10.8.0.0` | VPN 网段 |
| `OVPN_NETMASK` | `255.255.255.0` | VPN 掩码 |
| `OVPN_CIDR` | `10.8.0.0/24` | nft 排除的 VPN CIDR |
| `OVPN_SERVER_IP` | `10.8.0.1` | OpenVPN 网段网关，也是默认 DNS 地址 |
| `OVPN_MAX_CLIENTS` | `1024` | 最大客户端数量 |
| `OVPN_DUPLICATE_CN` | `0` | 保留变量；设置为 `1` 时用于允许多个设备复用同一客户端证书 |
| `OVPN_CLIENT_TO_CLIENT` | `0` | 保留变量；客户端互通开关 |
| `OVPN_CLIENT_NAME` | `client` | 自动生成的客户端名称 |
| `OVPN_SERVER_ADDR` | 自动公网 IP | 写入客户端配置的服务端地址 |
| `OVPN_CIPHER` | `AES-128-GCM` | fallback cipher |
| `OVPN_DATA_CIPHERS` | `AES-128-GCM:AES-256-GCM:CHACHA20-POLY1305` | DCO 友好的 AEAD cipher 列表 |
| `OVPN_AUTH` | `SHA256` | auth digest |
| `OVPN_VERB` | `3` | OpenVPN 日志级别 |

### SOCKS5 outbound

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PROXY_HOST` | 必填 | 上游 SOCKS5 地址 |
| `PROXY_PORT` | 必填 | 上游 SOCKS5 端口 |
| `PROXY_USER` | 空 | 上游 SOCKS5 用户名 |
| `PROXY_PASS` | 空 | 上游 SOCKS5 密码 |
| `PROXY_UDP` | `true` | sing-box `udp_over_tcp` |

当 `PROXY_USER` 或 `PROXY_PASS` 任一非空时，入口脚本使用 `config.auth.tpl.json`；否则使用 `config.noauth.tpl.json`。

## DNS 远程解析

默认 `OVPN_DNS=auto`，OpenVPN 会向客户端推送 OpenVPN 网段网关 `OVPN_SERVER_IP` 作为 DNS。来自 OpenVPN 设备的 TCP/UDP 流量，包括 53 端口 DNS，统一经 TPROXY 送入 sing-box；sing-box 根据官方 1.12 迁移文档先执行 `sniff`，识别 `protocol=dns` 后使用 `hijack-dns` 交给 DNS 模块，再通过新 DNS server 格式的 DoH 服务器 `DNS_SERVER` + `DNS_PATH`，并经 `proxy` SOCKS5 outbound 发起远程解析。默认使用 `DNS_SERVER=1.1.1.1` 和 `DNS_TLS_SERVER_NAME=cloudflare-dns.com`，避免 DoH 服务器域名解析引导循环。

可通过 `DNS_STRATEGY` 控制查询结果偏好：

```bash
-e DNS_STRATEGY=prefer_ipv4
-e DNS_STRATEGY=prefer_ipv6
-e DNS_STRATEGY=ipv4_only
-e DNS_STRATEGY=ipv6_only
```

### Runtime

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `MARK` | `1` | TPROXY fwmark |
| `TABLE_ID` | `100` | 策略路由表 |
| `TPROXY_PORT` | `7893` | sing-box tproxy 监听端口 |
| `TPROXY_BACKEND` | `iptables` | 透明代理规则后端：默认 `iptables`，可改为 `nft` |
| `FULL_PROXY` | `1` | 保留变量，默认全代理 |
| `SING_BOX_LOG_LEVEL` | `warning` | sing-box 日志级别 |
| `DNS_SERVER` | `1.1.1.1` | 远程 DoH DNS 服务器地址；默认用 Cloudflare IP，避免解析 DoH 域名时发生引导循环 |
| `DNS_SERVER_PORT` | `443` | 远程 DoH DNS 端口 |
| `DNS_PATH` | `/dns-query` | 远程 DoH DNS 路径 |
| `DNS_TLS_SERVER_NAME` | `cloudflare-dns.com` | DoH TLS SNI / 证书域名 |
| `DNS_STRATEGY` | `prefer_ipv4` | DNS 结果策略：`prefer_ipv4`、`prefer_ipv6`、`ipv4_only`、`ipv6_only` |
| `DNS_LISTEN` | `127.0.0.1` | sing-box 本地 DNS 接收地址 |
| `DNS_PORT` | `1053` | 保留变量，当前 DNS 通过 TPROXY/hijack-dns 处理 |
| `ENABLE_DIAGNOSTICS` | `0` | 设置为 `1` 时启动时打印 sing-box 配置、ip rule、策略路由和 iptables 规则，便于排查 |

## OpenVPN DCO

OpenVPN 2.6 会在配置和宿主机内核支持时机会性使用 DCO。DCO 需要：

- 宿主机支持并加载 `ovpn-dco` 内核模块；
- 使用 AEAD cipher，例如 `AES-128-GCM`、`AES-256-GCM`、`CHACHA20-POLY1305`；
- 不使用压缩等 DCO 不支持的配置。

容器无法替宿主机安装或加载内核模块。宿主机可尝试：

```bash
modprobe ovpn-dco
```

## 注意

- 推荐 `network_mode: host` / `--network host`。
- 需要 `NET_ADMIN` 和 `/dev/net/tun`。
- 默认 `OVPN_DEV=ovpn0`，避免 host network 下与宿主机或残留 OpenVPN 的 `tun0` 冲突；如果确实需要可用 `-e OVPN_DEV=xxx` 自定义。
- 默认使用 iptables TPROXY，避免部分 Alpine/nftables/宿主机组合下 `nft -f` 崩溃；如需 nft，可设置 `TPROXY_BACKEND=nft`。
- 上游 SOCKS5 必须支持 UDP，否则 UDP 业务不可用。
- Docker daemon 如需完全避免网络规则干预，可在宿主机 Docker 配置中设置 `iptables: false`，这不是容器内配置。
