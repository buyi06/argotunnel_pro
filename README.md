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

### 2. 运行安装

```bash
sudo ./argotunnel_pro.sh
```

脚本会引导你：
- 设置域名（必须有）
- 选择协议（VLESS/VMess）
- 自动配置 tunnel 和代理

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
sudo ./argotunnel_pro.sh [选项]
```

### 主要功能

- **安装**：默认行为，完整安装服务
- **卸载**：`sudo ./argotunnel_pro.sh uninstall`
- **重装**：先卸载再安装
- **更新**：更新 cloudflared 和 xray

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