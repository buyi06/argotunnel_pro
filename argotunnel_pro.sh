#!/usr/bin/env bash
# argotunnel.sh (2026 refactor)
# 目标：更稳、更可维护、更少坑（仍保持“一键安装 + systemd 管理”体验）
#
# 主要变化：
# - 严格模式 + 错误提示（set -Eeuo pipefail）
# - 更靠谱的系统/包管理器检测；不再尝试“安装 systemctl”
# - cloudflared 优先使用官方仓库安装（apt/yum/dnf/pacman），不行再回退到 GitHub 二进制
# - tunnel UUID 获取更稳：优先从 create 输出/JSON list 解析，最后才猜 newest .json
# - config.yaml 修复 hostname/404 兜底；systemd unit 放到 /etc/systemd/system
# - 减少 kill -9；卸载/重装更干净
#
# 依赖：systemd（必须）、curl、unzip、ca-certificates

set -Eeuo pipefail

APP_DIR="/opt/argotunnel"
BIN_DIR="${APP_DIR}/bin"
ETC_DIR="${APP_DIR}/etc"
OUT_DIR="${APP_DIR}/out"
SYSTEMD_DIR="/etc/systemd/system"

CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-cloudflared}"   # 若用包管理器安装，一般在 PATH 中
XRAY_BIN="${BIN_DIR}/xray"

# 默认参数（可用环境变量覆盖）
XRAY_PROTOCOL="${XRAY_PROTOCOL:-vless}"             # vmess | vless
EDGE_IP_VERSION="${EDGE_IP_VERSION:-auto}"          # auto | 4 | 6
CF_PROTOCOL="${CF_PROTOCOL:-auto}"                  # auto | quic | http2
DOMAIN="${DOMAIN:-}"                                # 必填；为空则走交互
TUNNEL_NAME="${TUNNEL_NAME:-}"                      # 为空则从 DOMAIN 取前缀
NO_COLOR="${NO_COLOR:-0}"

# ---------- 小工具 ----------
if [[ "$NO_COLOR" == "1" ]]; then
  _c_red=""; _c_grn=""; _c_yel=""; _c_blu=""; _c_rst=""
else
  _c_red=$'\033[31m'; _c_grn=$'\033[32m'; _c_yel=$'\033[33m'; _c_blu=$'\033[34m'; _c_rst=$'\033[0m'
fi

log()   { echo "${_c_blu}[INFO]${_c_rst} $*"; }
ok()    { echo "${_c_grn}[ OK ]${_c_rst} $*"; }
warn()  { echo "${_c_yel}[WARN]${_c_rst} $*" >&2; }
die()   { echo "${_c_red}[FAIL]${_c_rst} $*" >&2; exit 1; }

on_err() {
  local ec=$?
  warn "脚本执行失败（exit=$ec）。最后一条命令：${BASH_COMMAND}"
  warn "可先查看日志：journalctl -u argotunnel-cloudflared -u argotunnel-xray --no-pager -n 200"
  exit "$ec"
}
trap on_err ERR

need_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "请使用 root 运行（sudo -i 后再执行）"
}

have() { command -v "$1" >/dev/null 2>&1; }

require_systemd() {
  have systemctl || die "当前系统没有 systemd/systemctl，脚本仅支持 systemd 环境"
}

b64_nw0() { base64 -w 0 2>/dev/null || base64 | tr -d '\n'; }

# 尽量不依赖 jq；有 python3 就用 python3 解析 JSON
json_get_tunnel_id_by_name_py() {
  # stdin: json array; arg1: name
  python3 - "$1" <<'PY'
import json,sys
name=sys.argv[1]
data=json.load(sys.stdin)
for t in data:
    if t.get("name")==name:
        # 兼容不同字段
        for k in ("id","ID","uuid","UUID"):
            if t.get(k):
                print(t[k])
                raise SystemExit(0)
print("")
PY
}

urlencode_py() {
  python3 - <<'PY'
import sys,urllib.parse
print(urllib.parse.quote(sys.stdin.read().strip(), safe=""))
PY
}

# ---------- 包管理器 ----------
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

  case "$pm" in
    apt)
      DEBIAN_FRONTEND=noninteractive apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
      ;;
    dnf)
      dnf -y makecache
      dnf -y install "${pkgs[@]}"
      ;;
    yum)
      yum -y makecache || true
      yum -y install "${pkgs[@]}"
      ;;
    pacman)
      pacman -Syu --noconfirm "${pkgs[@]}"
      ;;
    apk)
      apk update
      apk add --no-cache "${pkgs[@]}"
      ;;
    zypper)
      zypper -n refresh
      zypper -n install "${pkgs[@]}"
      ;;
    *)
      die "无法识别包管理器，需手动安装依赖：${pkgs[*]}"
      ;;
  esac
}

ensure_deps() {
  local pm; pm="$(detect_pm)"
  log "检测包管理器：$pm"

  local deps=(curl unzip ca-certificates)
  pm_install "$pm" "${deps[@]}"

  ok "基础依赖已安装：${deps[*]}"
}

# ---------- 安装 cloudflared ----------
install_cloudflared_repo() {
  local pm; pm="$(detect_pm)"

  # 已存在就不折腾（优先用系统安装）
  if have cloudflared; then
    ok "已检测到 cloudflared：$(command -v cloudflared)"
    return 0
  fi

  case "$pm" in
    apt)
      log "使用 Cloudflare 官方 APT 源安装 cloudflared"
      mkdir -p --mode=0755 /usr/share/keyrings
      curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg \
        | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
      echo "deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main" \
        | tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
      apt-get update -y
      apt-get install -y cloudflared
      ;;
    dnf|yum)
      log "使用 Cloudflare 官方 RPM 源安装 cloudflared"
      curl -fsSl https://pkg.cloudflare.com/cloudflared.repo \
        | tee /etc/yum.repos.d/cloudflared.repo >/dev/null
      if [[ "$pm" == "dnf" ]]; then
        dnf -y install cloudflared
      else
        yum -y install cloudflared
      fi
      ;;
    pacman)
      log "使用 pacman 安装 cloudflared"
      pacman -Syu --noconfirm cloudflared
      ;;
    *)
      return 1
      ;;
  esac

  have cloudflared
}

install_cloudflared_bin() {
  log "回退到 GitHub Releases 二进制安装 cloudflared"

  mkdir -p "$BIN_DIR"
  local arch; arch="$(uname -m)"
  local asset=""
  case "$arch" in
    x86_64|amd64) asset="cloudflared-linux-amd64" ;;
    i386|i686)    asset="cloudflared-linux-386" ;;
    aarch64|arm64) asset="cloudflared-linux-arm64" ;;
    armv7l|armv7*) asset="cloudflared-linux-arm" ;;
    *)
      die "不支持的 CPU 架构：$arch（cloudflared）"
      ;;
  esac

  local url="https://github.com/cloudflare/cloudflared/releases/latest/download/${asset}"
  curl -fsSL "$url" -o "${BIN_DIR}/cloudflared"
  chmod +x "${BIN_DIR}/cloudflared"

  CLOUDFLARED_BIN="${BIN_DIR}/cloudflared"
  ok "cloudflared 已安装到：${CLOUDFLARED_BIN}"
}

ensure_cloudflared() {
  if install_cloudflared_repo; then
    CLOUDFLARED_BIN="$(command -v cloudflared)"
    ok "cloudflared 就绪：${CLOUDFLARED_BIN}"
  else
    install_cloudflared_bin
  fi
}

# ---------- 安装 Xray ----------
install_xray() {
  mkdir -p "$BIN_DIR"
  local arch; arch="$(uname -m)"
  local zip=""
  case "$arch" in
    x86_64|amd64) zip="Xray-linux-64.zip" ;;
    i386|i686)    zip="Xray-linux-32.zip" ;;
    aarch64|arm64) zip="Xray-linux-arm64-v8a.zip" ;;
    armv7l|armv7*) zip="Xray-linux-arm32-v7a.zip" ;;
    *)
      die "不支持的 CPU 架构：$arch（Xray）"
      ;;
  esac

  local tmp; tmp="$(mktemp -d)"
  local url="https://github.com/XTLS/Xray-core/releases/latest/download/${zip}"
  log "下载 Xray：${zip}"
  curl -fsSL "$url" -o "${tmp}/${zip}"

  # 尝试校验（如果 GitHub 提供 .dgst）
  if have sha256sum; then
    local dgst_url="https://github.com/XTLS/Xray-core/releases/latest/download/${zip}.dgst"
    if curl -fsSL "$dgst_url" -o "${tmp}/${zip}.dgst" 2>/dev/null; then
      local expected
      expected="$(grep -Eo 'SHA256=([0-9a-f]{64})' "${tmp}/${zip}.dgst" | head -n1 | cut -d= -f2 || true)"
      if [[ -n "$expected" ]]; then
        local actual
        actual="$(sha256sum "${tmp}/${zip}" | awk '{print $1}')"
        [[ "$actual" == "$expected" ]] || die "Xray ZIP 校验失败（SHA256 不匹配）"
        ok "Xray ZIP 校验通过（SHA256）"
      else
        warn "未能从 .dgst 提取 SHA256，跳过校验"
      fi
    else
      warn "未找到 ${zip}.dgst，跳过校验"
    fi
  else
    warn "系统缺少 sha256sum，跳过校验"
  fi

  unzip -q -o "${tmp}/${zip}" -d "$tmp/xray"
  install -m 0755 "$tmp/xray/xray" "$XRAY_BIN"
  rm -rf "$tmp"

  ok "Xray 已安装到：${XRAY_BIN}"
}

# ---------- 配置 ----------
rand_port() {
  # 取一个 10000-60000 的随机端口
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

  if [[ "$XRAY_PROTOCOL" == "vmess" ]]; then
    cat > "${ETC_DIR}/xray.json" <<EOF
{
  "inbounds": [
    {
      "port": ${port},
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": { "clients": [ { "id": "${uuid}", "alterId": 0 } ] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/${path}" } }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "settings": {} } ]
}
EOF
  elif [[ "$XRAY_PROTOCOL" == "vless" ]]; then
    cat > "${ETC_DIR}/xray.json" <<EOF
{
  "inbounds": [
    {
      "port": ${port},
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": [ { "id": "${uuid}" } ]
      },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/${path}" } }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "settings": {} } ]
}
EOF
  else
    die "不支持的 XRAY_PROTOCOL：$XRAY_PROTOCOL（仅 vmess/vless）"
  fi
}

ensure_cloudflared_login() {
  # locally-managed tunnel 需要 cert.pem。Cloudflare 默认路径 ~/.cloudflared/cert.pem
  local cert="${HOME}/.cloudflared/cert.pem"
  local cred_dir="${HOME}/.cloudflared"
  
  # 确保目录存在
  mkdir -p "$cred_dir"
  
  # 每次都强制登录
  warn "需要登录 Cloudflare（请准备浏览器）"
  "${CLOUDFLARED_BIN}" tunnel login
  [[ -s "$cert" ]] || die "未生成 cert.pem，login 可能未完成"
  
  # 验证登录是否成功
  if "${CLOUDFLARED_BIN}" tunnel list >/dev/null 2>&1; then
    ok "认证完成：$cert"
  else
    die "认证失败，请检查是否有权限访问该账户"
  fi
}

do_login() {
  local cert="$1"
  local cred_dir="$2"
  
  # 确保目录存在
  mkdir -p "$cred_dir"
  
  # 执行登录
  "${CLOUDFLARED_BIN}" tunnel login
  [[ -s "$cert" ]] || die "未生成 cert.pem，login 可能未完成"
  
  # 验证登录是否成功
  if "${CLOUDFLARED_BIN}" tunnel list >/dev/null 2>&1; then
    ok "认证完成：$cert"
  else
    die "认证失败，请检查是否有权限访问该账户"
  fi
}

prompt_if_empty() {
  if [[ -z "$DOMAIN" ]]; then
    # 检查是否为管道模式（非交互式）
    if [[ -t 0 ]]; then
      echo
      echo "请输入要绑定的完整二级域名，例如：app.example.com"
      read -r -p "DOMAIN: " DOMAIN
    else
      die "非交互式模式下请设置 DOMAIN 环境变量，例如：\n  curl ... | sudo DOMAIN=your.domain.com bash"
    fi
  fi
  [[ -n "$DOMAIN" ]] || die "DOMAIN 不能为空"
  [[ "$DOMAIN" == *.* ]] || die "DOMAIN 格式不正确（需要包含点号）：$DOMAIN"

  if [[ -z "$TUNNEL_NAME" ]]; then
    TUNNEL_NAME="${DOMAIN%%.*}"
  fi
}

get_tunnel_id_by_name() {
  local name="$1"
  local id=""

  # 1) 先试 JSON 输出（不保证所有版本都有，但很稳）
  if have python3; then
    if out="$("${CLOUDFLARED_BIN}" tunnel list -o json 2>/dev/null)"; then
      id="$(printf '%s' "$out" | json_get_tunnel_id_by_name_py "$name" || true)"
      [[ -n "$id" ]] && { echo "$id"; return 0; }
    fi
  fi

  # 2) 回退：解析表格输出（第一列通常是 ID，第二列是 NAME）
  id="$("${CLOUDFLARED_BIN}" tunnel list 2>/dev/null | awk -v n="$name" 'NR>2 && $2==n {print $1; exit}')"
  [[ -n "$id" ]] && { echo "$id"; return 0; }

  echo ""
}

create_or_reuse_tunnel() {
  local name="$1"
  local id; id="$(get_tunnel_id_by_name "$name")"

  if [[ -z "$id" ]]; then
    log "创建 Tunnel：$name"
    local out
    out="$("${CLOUDFLARED_BIN}" tunnel create "$name" 2>&1)"
    # 从输出里抓 UUID
    id="$(grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' <<<"$out" | head -n1 || true)"
    if [[ -z "$id" ]]; then
      # 再回退：找最新 json
      local newest
      newest="$(ls -t "${HOME}/.cloudflared/"*.json 2>/dev/null | head -n1 || true)"
      id="${newest##*/}"; id="${id%.json}"
    fi
    [[ -n "$id" ]] || die "无法获取 tunnel UUID，请检查 cloudflared 输出"
    ok "Tunnel 已创建：$name / $id"
  else
    ok "Tunnel 已存在：$name / $id"
    # 尽量做一次 cleanup，避免“连接残留”导致 delete/run 报错
    "${CLOUDFLARED_BIN}" tunnel cleanup "$name" >/dev/null 2>&1 || true
  fi

  echo "$id"
}

route_dns() {
  local name="$1" domain="$2"
  log "绑定 DNS（CNAME）到 Tunnel：$domain -> $name"
  "${CLOUDFLARED_BIN}" tunnel route dns --overwrite-dns "$name" "$domain"
  ok "DNS 绑定完成：$domain"
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
}

write_systemd_units() {
  local svc_cf="${SYSTEMD_DIR}/argotunnel-cloudflared.service"
  local svc_xr="${SYSTEMD_DIR}/argotunnel-xray.service"

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
# 安全加固（保守设置，不影响常见环境）
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=false

[Install]
WantedBy=multi-user.target
EOF

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

  systemctl daemon-reload
  systemctl enable --now argotunnel-xray.service
  systemctl enable --now argotunnel-cloudflared.service
  ok "systemd 服务已启用并启动"
}

write_links() {
  local domain="$1" uuid="$2" path="$3"
  mkdir -p "$OUT_DIR"
  local ps="Cloudflare_Tunnel"
  if have curl; then
    # 仅用作备注名；失败不影响安装
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

  if [[ "$XRAY_PROTOCOL" == "vmess" ]]; then
    local j
    j=$(printf '{"add":"%s","aid":"0","host":"%s","id":"%s","net":"ws","path":"/%s","port":"443","ps":"%s","tls":"tls","type":"none","v":"2"}' \
      "$domain" "$domain" "$uuid" "$path" "$ps")
    printf 'vmess://%s\n' "$(printf '%s' "$j" | b64_nw0)" >> "$out"
  else
    printf 'vless://%s@%s:443?encryption=none&security=tls&type=ws&host=%s&path=/%s#%s\n' \
      "$uuid" "$domain" "$domain" "$path" "$ps_enc" >> "$out"
  fi

  ok "链接已生成：$out（备注名/host/优选 IP 可自行替换）"
}

# ---------- 动作 ----------
do_install() {
  need_root
  require_systemd

  mkdir -p "$APP_DIR" "$BIN_DIR" "$ETC_DIR" "$OUT_DIR"

  ensure_deps
  ensure_cloudflared
  install_xray
  
  prompt_if_empty

  # 交互选择协议 / IP 版本（如果用户没提前设置环境变量）
  if [[ -z "${XRAY_PROTOCOL:-}" || ( "${XRAY_PROTOCOL}" != "vmess" && "${XRAY_PROTOCOL}" != "vless" ) ]]; then
    echo
    echo "选择 Xray 协议：1) vmess  2) vless（默认 1）"
    read -r -p "选择: " _p
    _p="${_p:-1}"
    XRAY_PROTOCOL=$([[ "$_p" == "2" ]] && echo "vless" || echo "vmess")
  fi

  if [[ "$EDGE_IP_VERSION" == "auto" ]]; then
    echo
    echo "选择 cloudflared 连接 IP 版本：auto/4/6（默认 auto）"
    read -r -p "选择: " _ip
    _ip="${_ip:-auto}"
    case "$_ip" in auto|4|6) EDGE_IP_VERSION="$_ip" ;; *) EDGE_IP_VERSION="auto" ;; esac
  fi

  if [[ "$CF_PROTOCOL" == "auto" ]]; then
    echo
    echo "选择 cloudflared 传输协议：auto/quic/http2（默认 auto）"
    read -r -p "选择: " _tp
    _tp="${_tp:-auto}"
    case "$_tp" in auto|quic|http2) CF_PROTOCOL="$_tp" ;; *) CF_PROTOCOL="auto" ;; esac
  fi

  ensure_cloudflared_login

  local uuid path port tunnel_id
  uuid="$(cat /proc/sys/kernel/random/uuid)"
  path="${uuid%%-*}"
  port="$(rand_port)"

  log "生成配置：protocol=${XRAY_PROTOCOL} port=${port} path=/${path}"
  write_xray_config "$port" "$uuid" "$path"

  tunnel_id="$(create_or_reuse_tunnel "$TUNNEL_NAME")"
  route_dns "$TUNNEL_NAME" "$DOMAIN"
  write_cloudflared_config "$tunnel_id" "$DOMAIN" "$port"

  write_systemd_units
  write_links "$DOMAIN" "$uuid" "$path"

  echo
  ok "安装完成 ✅"
  echo "状态查看：systemctl status argotunnel-cloudflared argotunnel-xray"
  echo "查看链接：cat ${OUT_DIR}/links.txt"
}

do_uninstall() {
  need_root
  require_systemd

  systemctl disable --now argotunnel-cloudflared.service >/dev/null 2>&1 || true
  systemctl disable --now argotunnel-xray.service >/dev/null 2>&1 || true

  rm -f "${SYSTEMD_DIR}/argotunnel-cloudflared.service" "${SYSTEMD_DIR}/argotunnel-xray.service"
  systemctl daemon-reload

  rm -rf "$APP_DIR"

  ok "卸载完成（未删除 ~/.cloudflared 授权/证书；如需彻底清理可手动删除该目录）"
}

do_status() {
  require_systemd
  systemctl status argotunnel-cloudflared argotunnel-xray --no-pager || true
}

do_links() {
  if [[ -f "${OUT_DIR}/links.txt" ]]; then
    cat "${OUT_DIR}/links.txt"
  else
    die "未找到链接文件：${OUT_DIR}/links.txt"
  fi
}

usage() {
  cat <<'EOF'
用法：
  bash argotunnel.sh install
  bash argotunnel.sh uninstall
  bash argotunnel.sh status
  bash argotunnel.sh links

可用环境变量（可选）：
  DOMAIN=app.example.com
  TUNNEL_NAME=app
  XRAY_PROTOCOL=vmess|vless
  EDGE_IP_VERSION=auto|4|6
  CF_PROTOCOL=auto|quic|http2
EOF
}

show_menu() {
  clear
  echo "=================================="
  echo "   ArgoTunnel Pro 管理菜单"
  echo "=================================="
  echo
  echo "1. 安装/重装服务"
  echo "2. 查看服务状态"
  echo "3. 查看节点链接"
  echo "4. 卸载服务"
  echo "5. 退出"
  echo
  echo -n "请选择操作 [1-5]: "
}

handle_menu() {
  while true; do
    show_menu
    read -r choice
    echo
    
    case "$choice" in
      1)
        do_install
        echo
        echo "按回车键继续..."
        read -r
        ;;
      2)
        do_status
        echo
        echo "按回车键继续..."
        read -r
        ;;
      3)
        do_links
        echo
        echo "按回车键继续..."
        read -r
        ;;
      4)
        echo "确定要卸载吗？(y/N)"
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          do_uninstall
        fi
        echo
        echo "按回车键继续..."
        read -r
        ;;
      5)
        echo "退出..."
        exit 0
        ;;
      *)
        echo "无效选择，请输入 1-5"
        sleep 1
        ;;
    esac
  done
}

main() {
  local cmd="${1:-menu}"
  case "$cmd" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
    status)    do_status ;;
    links)     do_links ;;
    menu)      handle_menu ;;
    -h|--help|help) usage ;;
    *)
      usage
      die "未知命令：$cmd"
      ;;
  esac
}

main "$@"
