# OVPN-SOCKS5 Docker 镜像

这是一个将 **OpenVPN 转 SOCKS5（支持 UDP）** 的 Docker 镜像。  
使用 OpenVPN 配置文件启动 VPN，并自动运行 Xray 提供 SOCKS5 代理。

镜像地址（GHCR）：

ghcr.io/lanlan13-14/ovpn-socks5:v1.0.0

---

## ⚡ 功能

- 将 OpenVPN 连接转为 SOCKS5 代理
- 支持 UDP 流量
- 自动设置默认路由走 VPN
- 集成 Xray，用作本地代理
- 容器化运行，方便部署

---

## 🛠️ 使用方法

### 1. 准备 OpenVPN 配置文件

在宿主机创建目录：

```bash
mkdir -p /root/ovpn

将你的 OpenVPN 配置文件放入：

/root/ovpn/client.ovpn

如果 OpenVPN 需要用户名密码，可创建 auth.txt：

/root/ovpn/auth.txt

内容示例：

username
password

并在 .ovpn 文件中引用：

auth-user-pass /vpn/auth.txt


---

2. 启动容器

docker run -d \
  --name ovpn-socks5 \
  --cap-add=NET_ADMIN \
  --device /dev/net/tun \
  -v /root/ovpn:/vpn \
  -p 1080:1080 \
  ghcr.io/lanlan13-14/ovpn-socks5:v1.0.0

说明：

--cap-add=NET_ADMIN + --device /dev/net/tun → TUN 权限

-v /root/ovpn:/vpn → 挂载本地 OpenVPN 配置文件

-p 1080:1080 → 映射容器 SOCKS5 端口到宿主机



---

3. 验证

查看容器日志：

docker logs -f ovpn-socks5

确认 OpenVPN 已成功连接，并且 Xray 已启动 SOCKS5 服务。

测试 SOCKS5 代理：

curl --socks5 127.0.0.1:1080 ifconfig.me


---

4. 停止/重启

停止容器：

docker stop ovpn-socks5
docker rm ovpn-socks5

重启容器：

docker start ovpn-socks5


---

⚠️ 注意事项

1. 镜像只提供工具，必须挂载 .ovpn 配置文件


2. 容器默认将所有流量通过 VPN


3. 如果 OpenVPN 需要用户名密码，必须挂载 auth.txt 并在配置中引用


4. 镜像内固定读取 /vpn/client.ovpn，可通过修改 entrypoint 支持环境变量指定文件名

