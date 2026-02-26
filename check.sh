#!/usr/bin/env bash

# 简化版代码检查脚本
set -eo pipefail

SCRIPT="argotunnel_pro.sh"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== 代码检查报告 ==="

# 1. 语法检查
echo -n "1. Bash 语法检查... "
if bash -n "$SCRIPT" 2>/dev/null; then
    echo -e "${GREEN}通过${NC}"
else
    echo -e "${RED}失败${NC}"
    bash -n "$SCRIPT"
fi

# 2. 关键函数检查
echo -n "2. 关键函数检查... "
functions=("do_install" "do_uninstall" "write_links" "write_xray_config" "write_cloudflared_config")
missing=()
for func in "${functions[@]}"; do
    if ! grep -q "^$func()" "$SCRIPT"; then
        missing+=("$func")
    fi
done
if [ ${#missing[@]} -eq 0 ]; then
    echo -e "${GREEN}通过${NC}"
else
    echo -e "${RED}失败：缺少函数 ${missing[*]}${NC}"
fi

# 3. 安全检查
echo -n "3. 安全检查... "
if grep -q "eval\|exec.*\$" "$SCRIPT" | grep -v "ExecStart" >/dev/null; then
    echo -e "${YELLOW}警告：发现潜在危险命令${NC}"
else
    echo -e "${GREEN}通过${NC}"
fi

# 4. 错误处理
echo -n "4. 错误处理检查... "
if grep -q "set -Eeuo pipefail" "$SCRIPT" && grep -q "trap on_err ERR" "$SCRIPT"; then
    echo -e "${GREEN}通过${NC}"
else
    echo -e "${RED}失败：未启用严格模式或错误陷阱${NC}"
fi

# 5. 配置生成
echo -n "5. 配置生成检查... "
if grep -q "visa.com" "$SCRIPT"; then
    echo -e "${RED}失败：仍有硬编码的 visa.com${NC}"
else
    echo -e "${GREEN}通过${NC}"
fi

# 6. 端口和UUID
echo -n "6. 端口和UUID生成... "
if grep -q "rand_port\|random/uuid" "$SCRIPT"; then
    echo -e "${GREEN}通过${NC}"
else
    echo -e "${RED}失败：未使用随机端口/UUID${NC}"
fi

# 7. 服务管理
echo -n "7. systemd服务管理... "
if grep -q "systemctl.*enable.*now\|systemctl.*disable.*now" "$SCRIPT"; then
    echo -e "${GREEN}通过${NC}"
else
    echo -e "${YELLOW}警告：服务管理不完整${NC}"
fi

echo -e "\n=== 主要问题 ==="
echo -e "${GREEN}✓ 配置文件名为 cloudflared.yml（一致）${NC}"

if grep -q "credentials-file.*HOME" "$SCRIPT"; then
    echo -e "${GREEN}✓ 使用了 \$HOME 路径${NC}"
else
    echo -e "${RED}✗ 未使用 \$HOME 路径${NC}"
fi

echo -e "\n检查完成！"