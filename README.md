# ArgoTunnel Pro

🚀 **企业级 Cloudflare Tunnel + Xray 代理解决方案**

ArgoTunnel Pro 是一个基于 Cloudflare Tunnel 和 Xray 的高性能代理解决方案，专为需要安全、稳定、高速网络访问的企业和开发者设计。通过 Cloudflare 全球边缘网络，为您的服务提供安全、高速的访问通道，支持 VLESS/VMess 协议，具备智能路由、自动故障转移和零配置部署特性。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Systemd](https://img.shields.io/badge/Systemd-enabled-blue.svg)](https://systemd.io/)

## ✨ 核心特性

### 🎯 **一键部署**
- 零依赖安装，自动处理所有配置
- 智能环境检测，支持主流 Linux 发行版
- 内置交互式菜单，操作直观便捷

### 🔒 **安全优先**
- TLS 1.3 端到端加密
- 自动 UUID 生成，避免密钥冲突
- Systemd 沙箱隔离，最小权限原则

### 🌐 **全球加速**
- Cloudflare Anycast 网络，200+ 边缘节点
- 智能路由选择，自动优选延迟最低的节点
- 支持 IPv4/IPv6 双栈网络

### 📊 **企业级运维**
- Systemd 原生集成，开机自启动
- 实时日志监控，故障快速定位
- 一键健康检查，服务状态了然于心

## 🚀 快速开始

### 一键部署

```bash
curl -fsSL https://raw.githubusercontent.com/buyi06/argotunnel_pro/main/argotunnel_pro.sh -o argotunnel_pro.sh
chmod +x argotunnel_pro.sh
sudo ./argotunnel_pro.sh
```

脚本将自动检测环境并引导您完成配置，整个过程无需手动干预。

## ⚙️ 高级配置

### 环境变量

通过环境变量实现自动化部署：

```bash
export DOMAIN="tunnel.example.com"
export XRAY_PROTOCOL="vless"
export TUNNEL_NAME="prod-tunnel"
export EDGE_IP_VERSION="4"
export CF_PROTOCOL="quic"
export NO_COLOR="1"

sudo ./argotunnel_pro.sh install
```

### 配置矩阵

| 变量 | 默认值 | 可选值 | 说明 |
|------|--------|--------|------|
| `DOMAIN` | - | - | **必填** - 您的域名 |
| `XRAY_PROTOCOL` | `vless` | `vmess` | 代理协议选择 |
| `TUNNEL_NAME` | `${DOMAIN%%.*}` | - | Tunnel 实例名称 |
| `EDGE_IP_VERSION` | `auto` | `4`/`6` | CF 边缘 IP 版本 |
| `CF_PROTOCOL` | `auto` | `quic`/`http2` | CF 传输协议 |
| `NO_COLOR` | `0` | `1` | 禁用彩色输出 |

### 命令行接口

```bash
# 完整命令列表
sudo ./argotunnel_pro.sh install    # 安装/重装
sudo ./argotunnel_pro.sh status     # 服务状态
sudo ./argotunnel_pro.sh links      # 获取节点
sudo ./argotunnel_pro.sh uninstall  # 卸载服务
sudo ./argotunnel_pro.sh menu       # 交互菜单
sudo ./argotunnel_pro.sh help       # 帮助信息
```

## 📁 目录结构

```
/opt/argotunnel/
├── 📂 bin/                    # 可执行文件
│   ├── cloudflared           # CF Tunnel 客户端
│   └── xray                  # Xray 代理核心
├── 📂 etc/                   # 配置文件
│   ├── cloudflared.yml       # Tunnel 配置
│   ├── xray.json            # Xray 服务配置
│   └── client.json          # 客户端参考配置
├── 📂 out/                   # 导出文件
│   ├── links.txt            # 节点链接
│   ├── vless.json           # VLESS 客户端配置
│   └── vmess.json           # VMess 客户端配置
└── 📂 var/                   # 运行时数据
    └── tunnel.json          # Tunnel 信息备份
```

## 🔧 运维管理

### 服务监控

```bash
# 实时状态监控
sudo systemctl status argotunnel-cloudflared
sudo systemctl status argotunnel-xray

# 日志追踪
sudo journalctl -u argotunnel-cloudflared -f
sudo journalctl -u argotunnel-xray -f

# 性能统计
sudo journalctl -u argotunnel-cloudflared --since "1 hour ago" | grep -E "connected|disconnected"
```

### 健康检查

```bash
# 检查服务状态
sudo ./argotunnel_pro.sh status

# 验证节点可用性
curl -I https://your-domain.com

# 查看实时连接
sudo ss -tulpn | grep -E "127.0.0.1:|:443"
```

### 故障恢复

```bash
# 重启服务
sudo systemctl restart argotunnel-cloudflared
sudo systemctl restart argotunnel-xray

# 清理并重装
sudo ./argotunnel_pro.sh uninstall
sudo ./argotunnel_pro.sh install

# 查看详细错误日志
sudo journalctl -u argotunnel-cloudflared -u argotunnel-xray --no-pager -n 100
```

## 🔒 安全最佳实践

### 1. 访问控制
- 使用强密码和随机 UUID
- 定期轮换访问凭证
- 启用 Cloudflare Access（可选）

### 2. 网络安全
- 配置 Cloudflare WAF 规则
- 启用 DDoS 保护
- 限制源地区访问

### 3. 监控告警
```bash
# 设置日志监控
sudo journalctl -u argotunnel-* -f --grep="error\|failed\|timeout"

# 创建监控脚本
cat > /root/monitor.sh << 'EOF'
#!/bin/bash
if ! systemctl is-active --quiet argotunnel-cloudflared; then
  echo "ArgoTunnel service is down!" | mail -s "Alert" admin@example.com
fi
EOF
```

## 🚨 故障排除

### 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 域名无法解析 | DNS 未配置 | 检查 Cloudflare DNS 设置 |
| 连接被拒绝 | 服务未启动 | `sudo systemctl restart argotunnel-*` |
| 认证失败 | Token 过期 | 重新执行 `cloudflared tunnel login` |
| 端口冲突 | 随机端口重复 | 脚本自动处理，无需手动干预 |

### 调试模式

```bash
# 启用详细日志
export NO_COLOR=1
sudo bash -x ./argotunnel_pro.sh install

# 查看 Cloudflare 连接状态
cloudflared tunnel list
cloudflared tunnel route dns list
```

## 🎯 性能优化

### 网络优化
```bash
# 强制 IPv4（解决双栈问题）
export EDGE_IP_VERSION="4"

# 使用 QUIC 协议（降低延迟）
export CF_PROTOCOL="quic"
```

### 系统调优
```bash
# 增加文件描述符限制
echo "* soft nofile 65535" >> /etc/security/limits.conf
echo "* hard nofile 65535" >> /etc/security/limits.conf

# 优化内核参数
sysctl -w net.core.rmem_max=134217728
sysctl -w net.core.wmem_max=134217728
```

## 🌟 高级特性

### 多实例部署
```bash
# 部署多个 Tunnel 实例
export DOMAIN="tunnel1.example.com"
sudo ./argotunnel_pro.sh install

export DOMAIN="tunnel2.example.com"
sudo ./argotunnel_pro.sh install
```

### 自动化集成
```bash
# CI/CD 集成示例
cat > deploy-tunnel.sh << 'EOF'
#!/bin/bash
set -euo pipefail

DOMAIN="${1:-tunnel.example.com}"
export DOMAIN="$DOMAIN"
export XRAY_PROTOCOL="vless"
export NO_COLOR="1"

curl -fsSL https://raw.githubusercontent.com/buyi06/argotunnel_pro/main/argotunnel_pro.sh | sudo bash
EOF
```

## 🤝 贡献指南

我们欢迎所有形式的贡献！

### 提交 Issue
- 使用 Issue 模板
- 提供详细的错误日志
- 包含系统环境信息

### 提交 PR
1. Fork 本仓库
2. 创建特性分支：`git checkout -b feature/amazing-feature`
3. 提交更改：`git commit -m 'Add amazing feature'`
4. 推送分支：`git push origin feature/amazing-feature`
5. 创建 Pull Request

## 📄 许可证

本项目采用 [MIT 许可证](LICENSE)。

## 🙏 致谢

- [Cloudflare](https://cloudflare.com/) - 提供全球边缘网络
- [Xray](https://github.com/XTLS/Xray-core) - 高性能代理核心
- [Systemd](https://systemd.io/) - Linux 服务管理框架

## 📞 支持

- 📧 [GitHub Issues](https://github.com/buyi06/argotunnel_pro/issues) - 问题反馈
- 💬 [Discussions](https://github.com/buyi06/argotunnel_pro/discussions) - 社区交流
- 📖 [Wiki](https://github.com/buyi06/argotunnel_pro/wiki) - 详细文档

---

<div align="center">
  <p>🌟 如果这个项目对您有帮助，请给我们一个 Star！</p>
  <p>Made with ❤️ by ArgoTunnel Pro Team</p>
</div>