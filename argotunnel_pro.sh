#!/usr/bin/env bash
# argotunnel_pro.sh (2026 UI Enhanced)
# 核心逻辑与原版保持一致，仅进行界面美化与交互体验升级
#
# 依赖：systemd（必须）、curl、unzip、ca-certificates

set -Eeuo pipefail

# ==============================================================================
#  UI & THEME CONFIGURATION
# ==============================================================================

# 定义配色方案 (ANSI Escape Codes)
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_RED='\033[38;5;196m'
C_GREEN='\033[38;5;46m'
C_YELLOW='\033[38;5;226m'
C_BLUE='\033[38;5;39m'
C_CYAN='\033[38;5;51m'
C_PURPLE='\033[38;5;129m'
C_WHITE='\033[38;5;255m'
C_BG_RED='\033[48;5;196m\033[38;5;255m'

# 符号定义
S_INFO="${C_BLUE}➜${C_RESET}"
S_SUCCESS="${C_GREEN}✔${C_RESET}"
S_WARN="${C_YELLOW}⚠${C_RESET}"
S_FAIL="${C_RED}✖${C_RESET}"
S_ARROW="${C_CYAN}➤${C_RESET}"
S_LINE="${C_DIM}──────────────────────────────────────────────────────────────${C_RESET}"

# ==============================================================================
#  CORE VARIABLES
# ==============================================================================

APP_DIR="/opt/argotunnel"
BIN_DIR="${APP_DIR}/bin"
ETC_DIR="${APP_DIR}/etc"
OUT_DIR="${APP_DIR}/out"
SYSTEMD_DIR="/etc/systemd/system"

CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-cloudflared}"
XRAY_BIN="${BIN_DIR}/xray"

# 默认参数（可用环境变量覆盖）
XRAY_PROTOCOL="${XRAY_PROTOCOL:-vmess}"             # vmess | vless
EDGE_IP_VERSION="${EDGE_IP_VERSION:-auto}"          # auto | 4 | 6
CF_PROTOCOL="${CF_PROTOCOL:-auto}"                  # auto | quic | http2
DOMAIN="${DOMAIN:-}"                                # 必填；为空则走交互
TUNNEL_NAME="${TUNNEL_NAME:-}"                      # 为空则从 DOMAIN 取前缀
NO_COLOR="${NO_COLOR:-0}"

# ==============================================================================
#  UI HELPER FUNCTIONS
# ==============================================================================

# 禁用颜色（如果设置）
if [[ "$NO_COLOR" == "1" ]]; then
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""; C_PURPLE=""; C_WHITE=""; C_BG_RED=""
fi

show_banner() {
  clear
  echo -e "${C_CYAN}"
  echo "    _                  _____                      _ "
  echo "   / \   _ __ __ _  __|_   _|   _ _ __  _ __   ___| |"
  echo "  / _ \ | '__/ _\` |/ _ \| || | | | '_ \| '_ \ / _ \ |"
  echo " / ___ \| | | (_| | (_) | || |_| | | | | | | |  __/ |"
  echo "/_/   \_\_|  \__, |\___/|_| \__,_|_| |_|_| |_|\___|_|"
  echo "             |___/    ${C_DIM}Optimized Edition 2026${C_RESET}"
  echo ""
  echo -e " ${C_DIM}Systemd Managed  |  Cloudflare Tunnel  |  Xray Core${C_RESET}"
  echo -e "$S_LINE"
  echo ""
}

log()   { echo -e " ${S_INFO}  ${C_WHITE}$*${C_RESET}"; }
step()  { echo -e "\n ${S_ARROW}  ${C_BOLD}$*${C_RESET}"; }
ok()    { echo -e " ${S_SUCCESS}  ${C_GREEN}$*${C_RESET}"; }
warn()  { echo -e " ${S_WARN}  ${C_YELLOW}$*${C_RESET}" >&2; }
die()   { echo -e "\n ${S_FAIL}  ${C_BG_RED} FATAL ERROR ${C_RESET} ${C_RED}$*${C_RESET}\n" >&2; exit 1; }

# 输入框样式
ask_input() {
  local prompt="$1"
  local default="$2"
  local var_ref="$3"
  
  local def_display=""
  if [[ -n "$default" ]]; then
    def_display="${C_DIM}(默认: ${default})${C_RESET}"
  fi

  echo -e -n " ${C_CYAN}?${C_RESET}  ${C_BOLD}${prompt}${C_RESET} ${def_display} \n    ${C_DIM}└─>${C_RESET} "
  read -r input_val
  
  if [[ -z "$input_val" ]]; then
    eval "$var_ref=\"$default\""
  else
    eval "$var_ref=\"$input_val\""
  fi
}

on_err() {
  local ec=$?
  echo ""
  echo -e "$S_LINE"
  warn "脚本执行异常终止 (Exit Code: $ec)"
  warn "最后执行命令: ${BASH_COMMAND}"
  warn "调试建议: journalctl -u argotunnel-cloudflared -u argotunnel-xray --no-pager -n 50"
  echo -e "$S_LINE"
  exit "$ec"
}
trap on_err ERR

need_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "权限不足，请使用 root 身份运行 (sudo -i)"
}

have() { command -v "$1" >/dev/null 2>&1; }

require_systemd() {
  have systemctl || die "系统不支持 systemd，本脚本仅适配现代 Linux 发行版"
}

b64_nw0() { base64 -w 0 2>/dev/null || base64 | tr -d '\n'; }

# Python 辅助工具
json_get_tunnel_id_by_name_py() {
  python3 - "$1" <<'PY'
import json,sys
name=sys.argv[1]
try:
    data=json.load(sys.stdin)
    for t in data:
        if t.get("name")==name:
            for k in ("id","ID","uuid","UUID"):
                if t.get(k):
                    print(t[k])
                    raise SystemExit(0)
except: pass
print("")
PY
}

urlencode_py() {
  python3 - <<'PY'
import sys,urllib.parse
print(urllib.parse.quote(sys.stdin.read().strip(), safe=""))
PY
}

# ==============================================================================
#  PACKAGE MANAGEMENT
# ==============================================================================

detect_pm() {
  if have apt-get; then echo "apt"; return; fi
  if have dnf; then echo "dnf"; return; fi
  if have yum; then echo "yum"; return; fi
  if have pacman; then echo "pacman"; return; fi
  if have apk; then echo "apk"; return; fi
  if have zypper; then echo "zypper"; return; fi
  echo "unknown"
}

pm_install() {
  local pm="$1"; shift
  local pkgs=("$@")

  log "正在安装依赖: ${C_CYAN}${pkgs[*]}${C_RESET} (使用 $pm)..."
  
  # 隐藏详细输出，除非出错
  if ! {
    case "$pm" in
      apt)
        DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}" >/dev/null 2>&1
        ;;
      dnf)
        dnf -y makecache >/dev/null 2>&1
        dnf -y install "${pkgs[@]}" >/dev/null 2>&1
        ;;
      yum)
        yum -y makecache >/dev/null 2>&1 || true
        yum -y install "${pkgs[@]}" >/dev/null 2>&1
        ;;
      pacman)
        pacman -Syu --noconfirm "${pkgs[@]}" >/dev/null 2>&1
        ;;
      apk)
        apk update >/dev/null 2>&1
        apk add --no-cache "${pkgs[@]}" >/dev/null 2>&1
        ;;
      zypper)
        zypper -n refresh >/dev/null 2>&1
        zypper -n install "${pkgs[@]}" >/dev/null 2>&1
        ;;
      *)
        die "未知的包管理器，请手动安装: ${pkgs[*]}"
        ;;
    esac
  }; then
    die "依赖安装失败，请检查网络或源设置"
  fi
}

ensure_deps() {
  local pm; pm="$(detect_pm)"
  local deps=(curl unzip ca-certificates)
  pm_install "$pm" "${deps[@]}"
  ok "基础依赖安装完成"
}

# ==============================================================================
#  CLOUDFLARED INSTALLATION
# ==============================================================================

install_cloudflared_repo() {
  local pm; pm="$(detect_pm)"

  if have cloudflared; then
    ok "检测到 Cloudflared 已安装: ${C_DIM}$(command -v cloudflared)${C_RESET}"
    return 0
  fi

  log "尝试使用官方源安装 Cloudflared..."
  
  case "$pm" in
    apt)
      mkdir -p --mode=0755 /usr/share/keyrings
      curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg \
        | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
      echo "deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main" \
        | tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
      apt-get update -y >/dev/null 2>&1
      apt-get install -y cloudflared >/dev/null 2>&1
      ;;
    dnf|yum)
      curl -fsSl https://pkg.cloudflare.com/cloudflared.repo \
        | tee /etc/yum.repos.d/cloudflared.repo >/dev/null
      if [[ "$pm" == "dnf" ]]; then
        dnf -y install cloudflared >/dev/null 2>&1
      else
        yum -y install cloudflared >/dev/null 2>&1
      fi
      ;;
    pacman)
      pacman -Syu --noconfirm cloudflared >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac

  have cloudflared
}

install_cloudflared_bin() {
  log "切换至 GitHub Release 二进制安装模式..."

  mkdir -p "$BIN_DIR"
  local arch; arch="$(uname -m)"
  local asset=""
  case "$arch" in
    x86_64|amd64) asset="cloudflared-linux-amd64" ;;
    i386|i686)    asset="cloudflared-linux-386" ;;
    aarch64|arm64) asset="cloudflared-linux-arm64" ;;
    armv7l|armv7*) asset="cloudflared-linux-arm" ;;
    *) die "不支持的 CPU 架构: $arch" ;;
  esac

  local url="https://github.com/cloudflare/cloudflared/releases/latest/download/${asset}"
  curl -fsSL "$url" -o "${BIN_DIR}/cloudflared"
  chmod +x "${BIN_DIR}/cloudflared"

  CLOUDFLARED_BIN="${BIN_DIR}/cloudflared"
  ok "Cloudflared 二进制已部署: ${C_DIM}${CLOUDFLARED_BIN}${C_RESET}"
}

ensure_cloudflared() {
  step "检查/安装 Cloudflared 组件"
  if ! install_cloudflared_repo; then
    install_cloudflared_bin
  else
     CLOUDFLARED_BIN="$(command -v cloudflared)"
     ok "Cloudflared 就绪 (Repo Mode)"
  fi
}

# ==============================================================================
#  XRAY INSTALLATION
# ==============================================================================

install_xray() {
  step "安装 Xray Core"
  mkdir -p "$BIN_DIR"
  local arch; arch="$(uname -m)"
  local zip=""
  case "$arch" in
    x86_64|amd64) zip="Xray-linux-64.zip" ;;
    i386|i686)    zip="Xray-linux-32.zip" ;;
    aarch64|arm64) zip="Xray-linux-arm64-v8a.zip" ;;
    armv7l|armv7*) zip="Xray-linux-arm32-v7a.zip" ;;
    *) die "不支持的 CPU 架构: $arch" ;;
  esac

  local tmp; tmp="$(mktemp -d)"
  local url="https://github.com/XTLS/Xray-core/releases/latest/download/${zip}"
  
  log "下载核心组件: ${C_CYAN}${zip}${C_RESET}"
  curl -fsSL "$url" -o "${tmp}/${zip}"

  # 简单的完整性检查
  if have sha256sum; then
     log "正在校验文件完整性..."
     # 这里简化逻辑，只提示正在校验，不做强阻断除非文件损坏
     if ! unzip -tq "${tmp}/${zip}" >/dev/null 2>&1; then
        die "下载的 ZIP 文件损坏，请重试"
     fi
     ok "文件校验通过"
  fi

  unzip -q -o "${tmp}/${zip}" -d "$tmp/xray"
  install -m 0755 "$tmp/xray/xray" "$XRAY_BIN"
  rm -rf "$tmp"

  ok "Xray Core 已部署: ${C_DIM}${XRAY_BIN}${C_RESET}"
}

# ==============================================================================
#  CONFIGURATION & TUNNEL
# ==============================================================================

rand_port() {
  local p
  for _ in {1..20}; do
    p=$(( (RANDOM % 50001) + 10000 ))
    if ! ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}$"; then
      echo "$p"
      return 0
    fi
  done
  echo $(( (RANDOM % 50001) + 10000 ))
}

write_xray_config() {
  local port="$1" uuid="$2" path="$3"
  mkdir -p "$ETC_DIR"

  log "生成 Xray 配置文件 (${XRAY_PROTOCOL})..."
  
  # 简化 JSON 写入，不展示内容以保持界面整洁
  if [[ "$XRAY_PROTOCOL" == "vmess" ]]; then
    cat > "${ETC_DIR}/xray.json" <<EOF
{
  "inbounds": [{
      "port": ${port}, "listen": "127.0.0.1", "protocol": "vmess",
      "settings": { "clients": [ { "id": "${uuid}", "alterId": 0 } ] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/${path}" } }
  }],
  "outbounds": [ { "protocol": "freedom", "settings": {} } ]
}
EOF
  else
    cat > "${ETC_DIR}/xray.json" <<EOF
{
  "inbounds": [{
      "port": ${port}, "listen": "127.0.0.1", "protocol": "vless",
      "settings": { "decryption": "none", "clients": [ { "id": "${uuid}" } ] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/${path}" } }
  }],
  "outbounds": [ { "protocol": "freedom", "settings": {} } ]
}
EOF
  fi
  ok "Xray 配置已更新"
}

ensure_cloudflared_login() {
  local cert="${HOME}/.cloudflared/cert.pem"
  if [[ -s "$cert" ]]; then
    ok "检测到有效授权证书: ${C_DIM}${cert}${C_RESET}"
    return 0
  fi

  step "Cloudflare 账号授权"
  echo -e " ${C_YELLOW}>> 请复制下方链接在浏览器打开，并授权您要绑定的域名 <<${C_RESET}"
  echo -e "$S_LINE"
  "${CLOUDFLARED_BIN}" tunnel login
  echo -e "$S_LINE"
  
  [[ -s "$cert" ]] || die "未检测到证书生成，授权可能未完成"
  ok "授权成功，证书已保存"
}

prompt_config() {
  step "配置参数向导"
  
  if [[ -z "$DOMAIN" ]]; then
    ask_input "请输入完整二级域名 (例如: app.example.com)" "" DOMAIN
  fi
  [[ -n "$DOMAIN" ]] || die "域名不能为空"
  [[ "$DOMAIN" == *.* ]] || die "域名格式错误: $DOMAIN"

  if [[ -z "$TUNNEL_NAME" ]]; then
    TUNNEL_NAME="${DOMAIN%%.*}"
  fi
  
  # 如果未预设协议，则交互
  if [[ -z "${XRAY_PROTOCOL:-}" || ( "${XRAY_PROTOCOL}" != "vmess" && "${XRAY_PROTOCOL}" != "vless" ) ]]; then
    ask_input "选择 Xray 协议 (vmess/vless)" "vmess" XRAY_PROTOCOL
    # 简单的纠错
    if [[ "$XRAY_PROTOCOL" == "1" ]]; then XRAY_PROTOCOL="vmess"; fi
    if [[ "$XRAY_PROTOCOL" == "2" ]]; then XRAY_PROTOCOL="vless"; fi
  fi
  log "使用协议: ${C_PURPLE}${XRAY_PROTOCOL}${C_RESET}"

  if [[ "$EDGE_IP_VERSION" == "auto" ]]; then
    ask_input "Cloudflare 连接 IP 版本 (auto/4/6)" "auto" EDGE_IP_VERSION
  fi

  if [[ "$CF_PROTOCOL" == "auto" ]]; then
    ask_input "Tunnel 传输协议 (auto/quic/http2)" "auto" CF_PROTOCOL
  fi
}

get_tunnel_id_by_name() {
  local name="$1"
  local id=""
  if have python3; then
    if out="$("${CLOUDFLARED_BIN}" tunnel list -o json 2>/dev/null)"; then
      id="$(printf '%s' "$out" | json_get_tunnel_id_by_name_py "$name" || true)"
      [[ -n "$id" ]] && { echo "$id"; return 0; }
    fi
  fi
  id="$("${CLOUDFLARED_BIN}" tunnel list 2>/dev/null | awk -v n="$name" 'NR>2 && $2==n {print $1; exit}')"
  [[ -n "$id" ]] && { echo "$id"; return 0; }
  echo ""
}

create_or_reuse_tunnel() {
  step "Tunnel 初始化"
  local name="$1"
  local id; id="$(get_tunnel_id_by_name "$name")"

  if [[ -z "$id" ]]; then
    log "创建新隧道: ${C_CYAN}$name${C_RESET}"
    local out
    out="$("${CLOUDFLARED_BIN}" tunnel create "$name" 2>&1)"
    id="$(grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' <<<"$out" | head -n1 || true)"
    if [[ -z "$id" ]]; then
      local newest
      newest="$(ls -t "${HOME}/.cloudflared/"*.json 2>/dev/null | head -n1 || true)"
      id="${newest##*/}"; id="${id%.json}"
    fi
    [[ -n "$id" ]] || die "无法获取 Tunnel ID"
    ok "隧道创建成功: ${C_DIM}$id${C_RESET}"
  else
    ok "复用已有隧道: ${C_DIM}$id${C_RESET}"
    "${CLOUDFLARED_BIN}" tunnel cleanup "$name" >/dev/null 2>&1 || true
  fi
  echo "$id"
}

route_dns() {
  local name="$1" domain="$2"
  log "更新 DNS 记录 (CNAME)..."
  "${CLOUDFLARED_BIN}" tunnel route dns --overwrite-dns "$name" "$domain" >/dev/null 2>&1
  ok "DNS 绑定完成: ${C_CYAN}$domain${C_RESET} -> ${C_DIM}$name${C_RESET}"
}

write_cloudflared_config() {
  local tunnel_id="$1" domain="$2" port="$3"
  mkdir -p "$ETC_DIR"
  cat > "${ETC_DIR}/cloudflared.yml" <<EOF
tunnel: ${tunnel_id}
credentials-file: ${HOME}/.cloudflared/${tunnel_id}.json
ingress:
  - hostname: ${domain}
    service: http://127.0.0.1:${port}
  - service: http_status:404
EOF
  log "Cloudflared 配置已生成"
}

write_systemd_units() {
  step "注册 Systemd 服务"
  local svc_cf="${SYSTEMD_DIR}/argotunnel-cloudflared.service"
  local svc_xr="${SYSTEMD_DIR}/argotunnel-xray.service"

  # 写入 Cloudflared Service
  cat > "$svc_cf" <<EOF
[Unit]
Description=Cloudflare Tunnel (argotunnel)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${CLOUDFLARED_BIN} tunnel --edge-ip-version ${EDGE_IP_VERSION} --protocol ${CF_PROTOCOL} --config ${ETC_DIR}/cloudflared.yml run
Restart=on-failure
RestartSec=3s
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=false

[Install]
WantedBy=multi-user.target
EOF

  # 写入 Xray Service
  cat > "$svc_xr" <<EOF
[Unit]
Description=Xray (argotunnel)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${XRAY_BIN} run -config ${ETC_DIR}/xray.json
Restart=on-failure
RestartSec=3s
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=false

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload >/dev/null 2>&1
  systemctl enable --now argotunnel-xray.service >/dev/null 2>&1
  systemctl enable --now argotunnel-cloudflared.service >/dev/null 2>&1
  ok "服务已启动并设置开机自启"
}

write_links() {
  local domain="$1" uuid="$2" path="$3"
  mkdir -p "$OUT_DIR"
  local ps="Cloudflare_Tunnel"
  if have curl; then
    local meta
    meta="$(curl -fsSL "https://speed.cloudflare.com/meta" 2>/dev/null || true)"
    if [[ -n "$meta" && -n "$(echo "$meta" | head -c 2)" ]]; then
      ps="CF_$(date +%Y%m%d)"
    fi
  fi

  local ps_enc="$ps"
  if have python3; then
    ps_enc="$(printf '%s' "$ps" | urlencode_py)"
  fi

  local out="${OUT_DIR}/links.txt"
  : > "$out"
  local link=""

  if [[ "$XRAY_PROTOCOL" == "vmess" ]]; then
    local j
    j=$(printf '{"add":"%s","aid":"0","host":"%s","id":"%s","net":"ws","path":"/%s","port":"443","ps":"%s","tls":"tls","type":"none","v":"2"}' \
      "visa.com" "$domain" "$uuid" "$path" "$ps")
    link="vmess://$(printf '%s' "$j" | b64_nw0)"
  else
    link="vless://${uuid}@visa.com:443?encryption=none&security=tls&type=ws&host=${domain}&path=/${path}#${ps_enc}"
  fi
  
  echo "$link" >> "$out"
  ok "连接凭证已生成"
}

# ==============================================================================
#  ACTIONS
# ==============================================================================

do_install() {
  show_banner
  need_root
  require_systemd

  mkdir -p "$APP_DIR" "$BIN_DIR" "$ETC_DIR" "$OUT_DIR"

  ensure_deps
  ensure_cloudflared
  install_xray

  prompt_config

  ensure_cloudflared_login

  local uuid path port tunnel_id
  uuid="$(cat /proc/sys/kernel/random/uuid)"
  path="${uuid%%-*}"
  port="$(rand_port)"

  tunnel_id="$(create_or_reuse_tunnel "$TUNNEL_NAME")"
  
  log "配置内部参数: Port=${port}, Path=/${path}"
  write_xray_config "$port" "$uuid" "$path"
  route_dns "$TUNNEL_NAME" "$DOMAIN"
  write_cloudflared_config "$tunnel_id" "$DOMAIN" "$port"

  write_systemd_units
  write_links "$DOMAIN" "$uuid" "$path"

  echo ""
  echo -e " ${C_GREEN}INSTALLATION SUCCESSFUL${C_RESET}"
  echo -e "$S_LINE"
  echo -e " 状态检查 : systemctl status argotunnel-cloudflared"
  echo -e " 链接文件 : ${OUT_DIR}/links.txt"
  echo -e "$S_LINE"
  
  # 直接显示链接，无需用户再去 cat
  echo -e " ${C_BOLD}🚀 您的专属连接:${C_RESET}"
  echo -e " ${C_CYAN}$(cat "${OUT_DIR}/links.txt")${C_RESET}"
  echo -e "$S_LINE"
  echo ""
}

do_uninstall() {
  show_banner
  need_root
  require_systemd

  step "开始卸载..."
  
  log "停止并禁用服务..."
  systemctl disable --now argotunnel-cloudflared.service >/dev/null 2>&1 || true
  systemctl disable --now argotunnel-xray.service >/dev/null 2>&1 || true

  log "移除 Systemd 单元文件..."
  rm -f "${SYSTEMD_DIR}/argotunnel-cloudflared.service" "${SYSTEMD_DIR}/argotunnel-xray.service"
  systemctl daemon-reload >/dev/null 2>&1

  log "清理应用程序文件..."
  rm -rf "$APP_DIR"

  ok "卸载完成"
  echo -e " ${C_DIM}提示: 您的 Cloudflare 授权凭证保留在 ~/.cloudflared 目录中。${C_RESET}"
  echo ""
}

do_status() {
  require_systemd
  echo -e "$S_LINE"
  echo -e " ${C_BOLD}SERVICE STATUS${C_RESET}"
  echo -e "$S_LINE"
  systemctl status argotunnel-cloudflared argotunnel-xray --no-pager || true
  echo -e "$S_LINE"
}

do_links() {
  if [[ -f "${OUT_DIR}/links.txt" ]]; then
    echo -e "$S_LINE"
    echo -e " ${C_BOLD}CONNECTION LINK${C_RESET}"
    echo -e "$S_LINE"
    echo -e "${C_CYAN}$(cat "${OUT_DIR}/links.txt")${C_RESET}"
    echo -e "$S_LINE"
  else
    die "未找到链接文件: ${OUT_DIR}/links.txt"
  fi
}

usage() {
  show_banner
  cat <<EOF
 ${C_BOLD}Usage:${C_RESET}
   bash $0 [command]

 ${C_BOLD}Commands:${C_RESET}
   ${C_CYAN}install${C_RESET}     安装并配置 (默认)
   ${C_CYAN}uninstall${C_RESET}   卸载服务及文件
   ${C_CYAN}status${C_RESET}      查看服务运行状态
   ${C_CYAN}links${C_RESET}       显示连接链接

 ${C_BOLD}Environment Variables:${C_RESET}
   DOMAIN           (e.g., app.example.com)
   TUNNEL_NAME      (e.g., app)
   XRAY_PROTOCOL    (vmess | vless)
   CF_PROTOCOL      (auto | quic | http2)
   
EOF
}

main() {
  local cmd="${1:-install}"
  case "$cmd" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
    status)    do_status ;;
    links)     do_links ;;
    -h|--help|help) usage ;;
    *)
      usage
      echo -e " ${S_FAIL} 未知命令: $cmd"
      exit 1
      ;;
  esac
}

main "$@"
