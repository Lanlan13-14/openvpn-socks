ovpn-socks5

一个基于 OpenVPN + Xray 的 SOCKS5 代理容器。  
容器启动后自动连接 VPN，并提供稳定的 SOCKS5 代理服务。

---

✨ 特性

- ✅ 支持任意 .ovpn 配置文件名  
- ✅ 支持手动指定配置文件（推荐）  
- ✅ 支持 OpenVPN 用户名 / 密码认证（环境变量）  
- ✅ 自动等待 VPN 连接（tun0）  
- ✅ 自动切换默认路由到 VPN  
- ✅ OpenVPN 前台运行 + 自动重连（高稳定）  
- ✅ 内置 Xray 提供 SOCKS5（支持 TCP/UDP）  
- ✅ 支持通过环境变量自定义端口、用户名/密码  
- ✅ 支持定期重启（环境变量控制）  

---

📦 镜像
```
ghcr.io/lanlan13-14/ovpn-socks5:latest
```
---

🚀 使用方法

方式一：指定配置文件（推荐）

```bash
docker run -d \
--name ovpn-socks5 \
--cap-add=NET_ADMIN \
--device /dev/net/tun \
-v /root/ovpn:/vpn \
-e OVPN_FILE=hk.ovpn \
-p 1080:1080 \
-p 1080:1080/udp \
--restart always \
ghcr.io/lanlan13-14/ovpn-socks5:latest
```

方式二：自动选择（不推荐）

```bash
docker run -d \
--name ovpn-socks5 \
--cap-add=NET_ADMIN \
--device /dev/net/tun \
-v /root/ovpn:/vpn \
-p 1080:1080 \
-p 1080:1080/udp \
--restart always \
ghcr.io/lanlan13-14/ovpn-socks5:latest
```

> 👉 会自动选择 /vpn 目录下第一个 .ovpn 文件

---

🔐 使用账号密码认证

如果你的 VPN 需要用户名和密码：

```bash
docker run -d \
--name ovpn-socks5 \
--cap-add=NET_ADMIN \
--device /dev/net/tun \
-v /root/ovpn:/vpn \
-e OVPN_FILE=hk.ovpn \
-e VPNUSERNAME=yourusername \
-e VPNPASSWORD=yourpassword \
-p 1080:1080 \
-p 1080:1080/udp \
--restart always \
ghcr.io/lanlan13-14/ovpn-socks5:latest
```

✔ 行为说明

容器会自动：

- 创建认证文件 /tmp/auth.txt  
- 自动注入或替换 auth-user-pass /tmp/auth.txt  
- 无需手动修改 .ovpn

---

🔌 SOCKS5 连接

| 项目       | 值 |
|-----------|-----|
| 地址       | 服务器 IP |
| 端口       | 1080（可通过环境变量 SOCKS_PORT 自定义） |
| 用户认证   | 默认匿名，可通过环境变量 SOCKSUSER 和 SOCKSPASS 设置账号密码 |
| UDP       | 支持 |

---

⚙️ 环境变量

| 变量名 | 说明 |
|--------|------|
| OVPN_FILE | 指定 OpenVPN 配置文件 |
| VPN_USERNAME | VPN 用户名（可选） |
| VPN_PASSWORD | VPN 密码（可选） |
| SOCKS_PORT | SOCKS5 端口（默认 1080） |
| SOCKS_USER | SOCKS5 用户名（可选） |
| SOCKS_PASS | SOCKS5 密码（可选） |
| RESTARTINTERVALHOURS | 容器自动重启间隔，0 表示禁用 |

---

🧠 工作流程

1. 读取 OVPN_FILE  
2. 自动处理账号密码（如提供）  
3. 启动 OpenVPN（前台运行）  
4. 等待 tun0 建立  
5. 默认路由切换到 VPN  
6. 启动 Xray 提供 SOCKS5  

---

🔄 自动重连机制

本项目使用 OpenVPN 内置重连机制：

```bash
--keepalive 10 60 --resolv-retry infinite --persist-tun
```

✔ 行为

| 场景                     | 结果 |
|--------------------------|-----|
| 网络抖动                  | 自动恢复 |
| VPN 服务器短暂断线         | 自动重连 |
| DNS 失败                  | 无限重试 |
| OpenVPN 崩溃               | 容器退出 → Docker 重启 |

> 👉 建议必须使用 --restart always  

---

🐳 docker-compose 示例

```yaml
version: '3.8'

services:
  ovpn-socks5:
    image: ghcr.io/lanlan13-14/ovpn-socks5:latest
    container_name: ovpn-socks5
    restart: always
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    volumes:
      - /root/ovpn:/vpn
    environment:
      - OVPN_FILE=hk.ovpn
      - VPNUSERNAME=yourusername
      - VPNPASSWORD=yourpassword
      - SOCKS_PORT=1080
      - SOCKS_USER=socksuser
      - SOCKS_PASS=sockspass
      - RESTARTINTERVALHOURS=24
    ports:
      - "1080:1080"
      - "1080:1080/udp"
```

---

⚠️ 注意事项

- 必须挂载 "/vpn"
- 必须开启：
  - "--cap-add=NET_ADMIN"
  - "/dev/net/tun"
- ".ovpn" 文件必须可用
- 若使用账号密码，不需要手动修改配置
- SOCKS5 默认匿名访问，如需认证请设置 SOCKSUSER 和 SOCKSPASS
- 定期重启通过 RESTARTINTERVALHOURS 环境变量控制

---

🛠️ 常见问题

❌ 配置文件不存在

```bash
ls /root/ovpn
```

❌ 没有 tun0  
确保容器参数包含：

```bash
--device /dev/net/tun
--cap-add=NET_ADMIN
```

❌ VPN 已连接但无法上网  
可能原因：

- ".ovpn" 未推送路由
- DNS 未配置
- 服务器限制

❌ SOCKS5 无法连接

```bash
docker logs ovpn-socks5
```