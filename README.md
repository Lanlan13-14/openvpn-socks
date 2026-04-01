ovpn-socks5

一个基于 OpenVPN + Xray 的 SOCKS5 代理容器。
容器启动后自动连接 VPN，并提供 SOCKS5 代理服务。

---

✨ 特性

- 支持任意 ".ovpn" 配置文件名
- 支持手动指定配置文件（推荐）
- 自动等待 VPN 连接
- 自动切换默认路由
- 内置 Xray 提供 SOCKS5
- 支持 "latest" + 版本 tag

---

📦 镜像

ghcr.io/lanlan13-14/ovpn-socks5:latest
ghcr.io/lanlan13-14/ovpn-socks5:v1.0.0

---

📁 目录结构

/root/ovpn/
  ├── hk.ovpn
  ├── sg.ovpn
  ├── jp.ovpn

---

🚀 使用方法

方式一：指定配置文件（推荐）

docker run -d \
  --name ovpn-socks5 \
  --cap-add=NET_ADMIN \
  --device /dev/net/tun \
  -v /root/ovpn:/vpn \
  -e OVPN_FILE=hk.ovpn \
  -p 1080:1080 \
  ghcr.io/lanlan13-14/ovpn-socks5:latest

---

方式二：自动选择（不推荐）

docker run -d \
  --name ovpn-socks5 \
  --cap-add=NET_ADMIN \
  --device /dev/net/tun \
  -v /root/ovpn:/vpn \
  -p 1080:1080 \
  ghcr.io/lanlan13-14/ovpn-socks5:latest

👉 会自动选择 "/vpn" 目录下第一个 ".ovpn"

---

🔌 SOCKS5 连接

地址: 服务器IP
端口: 1080

---

⚙️ 环境变量

变量名| 说明
OVPN_FILE| 指定使用的 OpenVPN 配置文件

---

🧠 工作流程

1. 读取 "OVPN_FILE"
2. 启动 OpenVPN
3. 等待 "tun0" 建立
4. 默认路由切换到 VPN
5. 启动 Xray

---

⚠️ 注意事项

- 必须挂载 "/vpn"
- 必须开启：
  - "--cap-add=NET_ADMIN"
  - "/dev/net/tun"
- ".ovpn" 文件必须可用（包含认证）

---

🛠️ 常见问题

❌ 配置文件不存在

检查：

ls /root/ovpn

---

❌ 没有 tun0

确保容器参数包含：

--device /dev/net/tun
--cap-add=NET_ADMIN

---

📄 License

MIT