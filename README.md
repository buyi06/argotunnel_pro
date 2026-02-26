# ArgoTunnel Pro

一键部署 Cloudflare Tunnel + Xray 代理服务，支持 VLESS/VMess 协议。

## 特性

- ✅ **一键安装**：全自动安装 cloudflared 和 xray
- ✅ **多协议支持**：VLESS、VMess
- ✅ **智能 IP 优选**：自动选择最优 CF 边缘 IP
- ✅ **Systemd 管理**：服务开机自启，日志清晰
- ✅ **错误恢复**：严格错误处理，失败有提示
- ✅ **多系统支持**：Ubuntu、CentOS、Debian、Arch 等

## 快速开始

### 1. 下载脚本

```bash
curl -fsSL https://raw.githubusercontent.com/buyi06/argotunnel_pro/main/argotunnel_pro.sh -o argotunnel_pro.sh
chmod +x argotunnel_pro.sh
```

### 2. 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/buyi06/argotunnel_pro/main/argotunnel_pro.sh -o argotunnel_pro.sh
sudo chmod +x argotunnel_pro.sh
sudo ./argotunnel_pro.sh
```

### 2. 运行脚本（交互式菜单）

```bash
sudo ./argotunnel_pro.sh
```

脚本会显示管理菜单，选择对应操作：
- 1 - 安装/重装服务
- 2 - 查看服务状态
- 3 - 查看节点链接
- 4 - 卸载服务
- 5 - 退出

### 3. 直接命令（无菜单）

```bash
sudo ./argotunnel_pro.sh install   # 安装
sudo ./argotunnel_pro.sh status    # 查看状态
sudo ./argotunnel_pro.sh links     # 查看链接
sudo ./argotunnel_pro.sh uninstall # 卸载
```

### 4. 在线执行

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/buyi06/argotunnel_pro/main/argotunnel_pro.sh)
```

### 3. 获取配置

安装完成后，配置信息保存在：
- `/opt/argotunnel/etc/client.json` - 客户端配置
- `/opt/argotunnel/out/` - 导出的配置文件

## 环境变量配置

可以通过环境变量预配置参数：

```bash
export DOMAIN="your-domain.com"
export XRAY_PROTOCOL="vless"
export TUNNEL_NAME="mytunnel"
export EDGE_IP_VERSION="4"
export CF_PROTOCOL="quic"

sudo ./argotunnel_pro.sh
```

### 支持的环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DOMAIN` | - | 必填，你的域名 |
| `XRAY_PROTOCOL` | `vmess` | 协议：`vmess` 或 `vless` |
| `TUNNEL_NAME` | 从域名生成 | Tunnel 名称 |
| `EDGE_IP_VERSION` | `auto` | CF 边缘 IP 版本：`auto`/`4`/`6` |
| `CF_PROTOCOL` | `auto` | CF 连接协议：`auto`/`quic`/`http2` |
| `NO_COLOR` | `0` | 禁用颜色输出：`0`/`1` |

## 系统要求

- **必须**：systemd（用于服务管理）
- **依赖**：curl、unzip、ca-certificates
- **权限**：root 权限

## 支持的系统

| 系统 | 包管理器 | 状态 |
|------|----------|------|
| Ubuntu/Debian | apt | ✅ 完全支持 |
| CentOS/RHEL | yum/dnf | ✅ 完全支持 |
| Arch Linux | pacman | ✅ 完全支持 |
| Alpine | apk | ✅ 完全支持 |
| openSUSE | zypper | ✅ 完全支持 |

## 命令行选项

```bash
sudo ./argotunnel_pro.sh [命令]
```

### 可用命令

- `install` - 安装/重装服务
- `status` - 查看服务状态
- `links` - 查看节点链接
- `uninstall` - 卸载服务
- `menu` - 显示交互式菜单（默认）
- `help` - 显示帮助信息

### 主要功能

- **安装**：完整安装并配置服务
- **卸载**：清理所有相关文件和服务
- **状态查看**：实时查看服务运行状态
- **链接管理**：获取和查看客户端配置

### 查看状态

```bash
# 查看服务状态
sudo systemctl status argotunnel-cloudflared
sudo systemctl status argotunnel-xray

# 查看日志
sudo journalctl -u argotunnel-cloudflared -f
sudo journalctl -u argotunnel-xray -f
```

## 目录结构

```
/opt/argotunnel/
├── bin/
│   ├── cloudflared    # Cloudflare Tunnel 二进制
│   └── xray          # Xray 代理二进制
├── etc/
│   ├── config.yaml   # Cloudflare Tunnel 配置
│   ├── xray.json     # Xray 配置
│   └── client.json   # 客户端配置（供参考）
├── out/
│   ├── vless.json    # VLESS 客户端配置
│   └── vmess.json    # VMess 客户端配置
└── var/
    └── tunnel.json   # Tunnel 信息备份
```

## 故障排除

### 常见问题

1. **域名未解析**
   - 确保域名已托管到 Cloudflare
   - DNS 记录已正确配置

2. **服务启动失败**
   ```bash
   # 查看详细错误日志
   sudo journalctl -u argotunnel-cloudflared -u argotunnel-xray --no-pager -n 200
   ```

3. **连接不稳定**
   - 尝试设置 `EDGE_IP_VERSION=4` 强制使用 IPv4
   - 尝试设置 `CF_PROTOCOL=quic` 使用 QUIC 协议

4. **Tunnel 创建失败**
   - 检查 Cloudflare 账户权限
   - 确保没有同名 tunnel

### 手动干预

如果自动配置失败，可以手动修改配置：

```bash
# 编辑 tunnel 配置
sudo nano /opt/argotunnel/etc/config.yaml

# 编辑 xray 配置
sudo nano /opt/argotunnel/etc/xray.json

# 重启服务
sudo systemctl restart argotunnel-cloudflared
sudo systemctl restart argotunnel-xray
```

## 安全建议

1. **定期更新**
   ```bash
   sudo ./argotunnel_pro.sh
   ```

2. **使用强密码**
   - Xray 默认生成随机 UUID，确保其随机性

3. **监控日志**
   - 定期检查异常访问日志

## 开发

### 脚本结构

- **严格模式**：`set -Eeuo pipefail` 确保错误立即退出
- **错误处理**：`trap on_err ERR` 捕获错误并提示
- **模块化设计**：功能分离，易于维护

### 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

MIT License

## 支持

如有问题，请提交 [GitHub Issue](https://github.com/buyi06/argotunnel_pro/issues)。