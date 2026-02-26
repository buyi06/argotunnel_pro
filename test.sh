#!/usr/bin/env bash

# 代码自查自纠测试脚本
# 用于验证 argotunnel_pro.sh 的各种功能和边界情况

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/argotunnel_pro.sh"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

# 测试计数
TESTS_TOTAL=0
TESTS_PASSED=0

run_test() {
    local test_name="$1"
    shift
    ((TESTS_TOTAL++))
    echo -e "\n${YELLOW}测试: $test_name${NC}"
    
    # 捕获输出和退出码
    if output=$("$@" 2>&1); then
        pass "$test_name"
        ((TESTS_PASSED++))
        return 0
    else
        fail "$test_name"
        echo "错误输出: $output" >&2
        return 1
    fi
}

# 1. 语法检查
echo "=== 1. 语法检查 ==="
run_test "Bash 语法检查" bash -n "$SCRIPT"

# 2. 函数定义检查
echo -e "\n=== 2. 函数定义检查 ==="
functions=(
    "need_root"
    "have"
    "require_systemd"
    "b64_nw0"
    "json_get_tunnel_id_by_name_py"
    "urlencode_py"
    "detect_pm"
    "install_deps"
    "install_cloudflared_repo"
    "install_cloudflared_bin"
    "ensure_cloudflared"
    "install_xray"
    "write_xray_config"
    "ensure_cloudflared_login"
    "prompt_if_empty"
    "get_tunnel_id_by_name"
    "create_or_reuse_tunnel"
    "route_dns"
    "write_cloudflared_config"
    "write_systemd_units"
    "write_links"
    "do_install"
    "do_uninstall"
    "do_status"
    "do_links"
    "usage"
    "main"
)

for func in "${functions[@]}"; do
    if grep -q "^$func()" "$SCRIPT"; then
        pass "函数 $func 已定义"
    else
        fail "函数 $func 未找到"
    fi
done

# 3. 变量检查
echo -e "\n=== 3. 关键变量检查 ==="
variables=(
    "APP_DIR"
    "BIN_DIR"
    "ETC_DIR"
    "OUT_DIR"
    "SYSTEMD_DIR"
    "CLOUDFLARED_BIN"
    "XRAY_BIN"
    "XRAY_PROTOCOL"
    "EDGE_IP_VERSION"
    "CF_PROTOCOL"
    "DOMAIN"
    "TUNNEL_NAME"
    "NO_COLOR"
)

for var in "${variables[@]}"; do
    if grep -q "^$var=" "$SCRIPT"; then
        pass "变量 $var 已定义"
    else
        fail "变量 $var 未找到"
    fi
done

# 4. 安全检查
echo -e "\n=== 4. 安全检查 ==="
# 检查是否有 eval 或类似的危险命令
if grep -q "eval\|exec\|\$\(" "$SCRIPT" | grep -v "json_get_tunnel_id_by_name_py" | grep -v "ExecStart"; then
    warn "发现潜在的危险命令（eval/exec），请检查"
else
    pass "未发现明显的危险命令"
fi

# 检查文件权限
if grep -q "chmod 777" "$SCRIPT"; then
    fail "发现 777 权限设置"
else
    pass "未发现 777 权限设置"
fi

# 5. 错误处理检查
echo -e "\n=== 5. 错误处理检查 ==="
if grep -q "set -Eeuo pipefail" "$SCRIPT"; then
    pass "启用了严格模式"
else
    fail "未启用严格模式"
fi

if grep -q "trap on_err ERR" "$SCRIPT"; then
    pass "设置了错误陷阱"
else
    fail "未设置错误陷阱"
fi

# 6. 路径检查
echo -e "\n=== 6. 路径检查 ==="
# 检查硬编码路径
if grep -q "/root\|/home" "$SCRIPT" | grep -v "HOME"; then
    warn "发现硬编码的用户路径"
else
    pass "未发现硬编码的用户路径"
fi

# 检查相对路径
if grep -q "mkdir.*[^$]\./" "$SCRIPT"; then
    warn "发现相对路径使用"
else
    pass "未使用相对路径"
fi

# 7. 依赖检查
echo -e "\n=== 7. 依赖检查 ==="
dependencies=(
    "systemctl"
    "curl"
    "unzip"
)

for dep in "${dependencies[@]}"; do
    if grep -q "$dep" "$SCRIPT"; then
        pass "依赖 $dep 已在脚本中检查或使用"
    else
        warn "依赖 $dep 未明确检查"
    fi
done

# 8. 配置生成检查
echo -e "\n=== 8. 配置生成检查 ==="
# 检查 JSON 配置的语法
if grep -q '"port":' "$SCRIPT" && grep -q '"protocol":' "$SCRIPT"; then
    pass "配置文件包含必要的字段"
else
    fail "配置文件可能缺少必要字段"
fi

# 9. 服务管理检查
echo -e "\n=== 9. 服务管理检查 ==="
service_operations=(
    "systemctl daemon-reload"
    "systemctl enable"
    "systemctl disable"
    "systemctl status"
)

for op in "${service_operations[@]}"; do
    if grep -q "$op" "$SCRIPT"; then
        pass "服务操作 $op 已使用"
    else
        warn "服务操作 $op 未使用"
    fi
done

# 10. 输出重定向检查
echo -e "\n=== 10. 输出重定向检查 ==="
if grep -q ">/dev/null" "$SCRIPT"; then
    pass "使用了输出重定向抑制噪音"
else
    warn "未使用输出重定向"
fi

# 11. 端口随机化检查
echo -e "\n=== 11. 端口随机化检查 ==="
if grep -q "rand_port\|RANDOM" "$SCRIPT"; then
    pass "使用了端口随机化"
else
    fail "未使用端口随机化"
fi

# 12. UUID 生成检查
echo -e "\n=== 12. UUID 生成检查 ==="
if grep -q "random/uuid\|uuidgen" "$SCRIPT"; then
    pass "使用了 UUID 生成"
else
    fail "未使用 UUID 生成"
fi

# 13. 备份和清理检查
echo -e "\n=== 13. 备份和清理检查 ==="
if grep -q "cleanup\|backup\|rm -rf" "$SCRIPT"; then
    pass "包含了清理或备份逻辑"
else
    warn "未发现清理或备份逻辑"
fi

# 14. 日志记录检查
echo -e "\n=== 14. 日志记录检查 ==="
if grep -q "log\|ok\|warn\|die" "$SCRIPT"; then
    pass "使用了日志记录函数"
else
    fail "未使用日志记录函数"
fi

# 15. 文件存在性检查
echo -e "\n=== 15. 文件存在性检查 ==="
if grep -q "\-f\|\-s\|\-d" "$SCRIPT"; then
    pass "检查了文件存在性"
else
    warn "未检查文件存在性"
fi

# 总结
echo -e "\n${YELLOW}=== 测试总结 ===${NC}"
echo "总测试数: $TESTS_TOTAL"
echo -e "通过: ${GREEN}$TESTS_PASSED${NC}"
echo -e "失败: ${RED}$((TESTS_TOTAL - TESTS_PASSED))${NC}"

if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
    echo -e "\n${GREEN}所有测试通过！${NC}"
    exit 0
else
    echo -e "\n${YELLOW}请检查失败的测试项。${NC}"
    exit 1
fi