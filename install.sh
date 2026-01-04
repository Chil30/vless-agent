#!/bin/bash
# VLESS Agent 一键安装脚本 v1.0.0
# 用法: bash <(curl -sL URL) -e <服务器地址> -t <Token>

set -e

VERSION="1.0.0"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[*]${NC} $1"; }

# 默认值
SERVICE_NAME="vless-agent"
INSTALL_DIR="/opt/vless-agent"
GITHUB_REPO="Chil30/vless-agent"  # 修改为你的 GitHub 仓库
GITHUB_PROXY=""
ENDPOINT=""
TOKEN=""
SERVER_NAME=""
VLESS_SCRIPT="/usr/local/bin/vless"

# 检测操作系统
detect_os() {
    case $(uname -s) in
        Darwin) echo "darwin" ;;
        Linux) echo "linux" ;;
        FreeBSD) echo "freebsd" ;;
        *) log_error "不支持的操作系统: $(uname -s)"; exit 1 ;;
    esac
}

# 检测架构
detect_arch() {
    case $(uname -m) in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        i386|i686) echo "386" ;;
        armv7*|armv6*) echo "arm" ;;
        *) log_error "不支持的架构: $(uname -m)"; exit 1 ;;
    esac
}

# 检测 init 系统
detect_init_system() {
    # Alpine Linux
    if [ -f /etc/alpine-release ]; then
        if command -v rc-service >/dev/null 2>&1; then
            echo "openrc"
            return
        fi
    fi
    
    # systemd
    if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
        echo "systemd"
        return
    fi
    
    # OpenRC
    if command -v rc-service >/dev/null 2>&1; then
        echo "openrc"
        return
    fi
    
    # OpenWrt procd
    if command -v uci >/dev/null 2>&1 && [ -f /etc/rc.common ]; then
        echo "procd"
        return
    fi
    
    # macOS launchd
    if [ "$(uname -s)" = "Darwin" ] && command -v launchctl >/dev/null 2>&1; then
        echo "launchd"
        return
    fi
    
    echo "unknown"
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--endpoint)
            ENDPOINT="$2"
            shift 2
            ;;
        -t|--token)
            TOKEN="$2"
            shift 2
            ;;
        -n|--name)
            SERVER_NAME="$2"
            shift 2
            ;;
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --ghproxy)
            GITHUB_PROXY="$2"
            shift 2
            ;;
        -h|--help)
            echo "用法: $0 -e <服务器地址> -t <Token> [-n <名称>]"
            echo ""
            echo "参数:"
            echo "  -e, --endpoint   服务器地址 (必需)"
            echo "  -t, --token      认证 Token (必需)"
            echo "  -n, --name       服务器名称 (可选)"
            echo "  --install-dir    安装目录 (默认: /opt/vless-agent)"
            echo "  --ghproxy        GitHub 代理地址"
            exit 0
            ;;
        *)
            log_warning "未知参数: $1"
            shift
            ;;
    esac
done

# 检查必需参数
if [ -z "$ENDPOINT" ] || [ -z "$TOKEN" ]; then
    log_error "必须指定 -e (服务器地址) 和 -t (Token) 参数"
    echo "用法: $0 -e <服务器地址> -t <Token>"
    exit 1
fi

# 检查 root 权限
if [ "$EUID" -ne 0 ] && [ "$(uname -s)" != "Darwin" ]; then
    log_error "请使用 root 权限运行"
    exit 1
fi

echo -e "${WHITE}========================================${NC}"
echo -e "${WHITE}    VLESS Agent 安装脚本 v${VERSION}${NC}"
echo -e "${WHITE}========================================${NC}"
echo ""

OS=$(detect_os)
ARCH=$(detect_arch)
INIT_SYSTEM=$(detect_init_system)

log_info "操作系统: ${GREEN}$OS${NC}"
log_info "架构: ${GREEN}$ARCH${NC}"
log_info "Init 系统: ${GREEN}$INIT_SYSTEM${NC}"
log_info "服务器: ${GREEN}$ENDPOINT${NC}"
log_info "Token: ${GREEN}${TOKEN:0:8}...${NC}"
echo ""

# 检查 vless-server.sh 脚本
check_vless_script() {
    log_step "检查 vless-server.sh 脚本..."
    
    if [ -f "$VLESS_SCRIPT" ]; then
        log_success "vless 脚本已安装: $VLESS_SCRIPT"
    elif [ -f "/root/vless-server.sh" ]; then
        log_info "创建 vless 命令链接..."
        ln -sf /root/vless-server.sh "$VLESS_SCRIPT"
        chmod +x "$VLESS_SCRIPT"
        log_success "vless 命令已创建"
    else
        log_warning "未检测到 vless-server.sh 脚本"
        log_info "Agent 需要 vless-server.sh 脚本来执行协议安装等操作"
        log_info "请先安装 vless-server.sh 或确保脚本位于 /root/vless-server.sh"
    fi
}

check_vless_script

# 卸载旧版本
uninstall_previous() {
    log_step "检查旧版本..."
    
    if [ "$INIT_SYSTEM" = "systemd" ] && systemctl list-unit-files | grep -q "${SERVICE_NAME}.service"; then
        log_info "停止并删除旧服务..."
        systemctl stop ${SERVICE_NAME}.service 2>/dev/null || true
        systemctl disable ${SERVICE_NAME}.service 2>/dev/null || true
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        systemctl daemon-reload
    elif [ "$INIT_SYSTEM" = "openrc" ] && [ -f "/etc/init.d/${SERVICE_NAME}" ]; then
        log_info "停止并删除旧服务..."
        rc-service ${SERVICE_NAME} stop 2>/dev/null || true
        rc-update del ${SERVICE_NAME} default 2>/dev/null || true
        rm -f "/etc/init.d/${SERVICE_NAME}"
    elif [ "$INIT_SYSTEM" = "launchd" ]; then
        PLIST="/Library/LaunchDaemons/com.vless.${SERVICE_NAME}.plist"
        if [ -f "$PLIST" ]; then
            log_info "停止并删除旧服务..."
            launchctl bootout system "$PLIST" 2>/dev/null || true
            rm -f "$PLIST"
        fi
    fi
    
    # 删除旧二进制
    if [ -f "${INSTALL_DIR}/vless-agent" ]; then
        rm -f "${INSTALL_DIR}/vless-agent"
    fi
}

uninstall_previous

# 安装依赖
install_dependencies() {
    log_step "检查依赖..."
    
    if ! command -v curl >/dev/null 2>&1; then
        log_info "安装 curl..."
        if command -v apt >/dev/null 2>&1; then
            apt update && apt install -y curl
        elif command -v yum >/dev/null 2>&1; then
            yum install -y curl
        elif command -v apk >/dev/null 2>&1; then
            apk add curl
        elif command -v brew >/dev/null 2>&1; then
            brew install curl
        fi
    fi
    
    log_success "依赖检查完成"
}

install_dependencies

# 下载二进制文件
download_binary() {
    log_step "下载 Agent..."
    
    BINARY_NAME="vless-agent-${OS}-${ARCH}"
    
    if [ -n "$GITHUB_PROXY" ]; then
        DOWNLOAD_URL="${GITHUB_PROXY}/https://github.com/${GITHUB_REPO}/releases/latest/download/${BINARY_NAME}"
    else
        DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/latest/download/${BINARY_NAME}"
    fi
    
    log_info "下载地址: ${CYAN}$DOWNLOAD_URL${NC}"
    
    mkdir -p "$INSTALL_DIR"
    
    # 下载文件
    HTTP_CODE=$(curl -L -w "%{http_code}" -o "${INSTALL_DIR}/vless-agent" "$DOWNLOAD_URL" 2>/dev/null)
    
    if [ "$HTTP_CODE" != "200" ]; then
        log_error "下载失败 (HTTP $HTTP_CODE)"
        log_error "请确认 GitHub Release 中存在文件: ${BINARY_NAME}"
        rm -f "${INSTALL_DIR}/vless-agent"
        exit 1
    fi
    
    # 检查文件大小
    FILE_SIZE=$(stat -c%s "${INSTALL_DIR}/vless-agent" 2>/dev/null || stat -f%z "${INSTALL_DIR}/vless-agent" 2>/dev/null)
    if [ "$FILE_SIZE" -lt 1000 ]; then
        log_error "下载的文件无效 (大小: ${FILE_SIZE} 字节)"
        log_error "请确认 GitHub Release 中存在文件: ${BINARY_NAME}"
        rm -f "${INSTALL_DIR}/vless-agent"
        exit 1
    fi
    
    # 检查是否为有效的可执行文件
    chmod +x "${INSTALL_DIR}/vless-agent"
    
    # 尝试运行 --version 或 --help 来验证是否为有效可执行文件
    if "${INSTALL_DIR}/vless-agent" --help >/dev/null 2>&1 || "${INSTALL_DIR}/vless-agent" -h >/dev/null 2>&1; then
        : # 文件有效
    else
        # 检查文件头是否为 ELF (Linux) 或 Mach-O (macOS)
        FILE_HEADER=$(head -c 4 "${INSTALL_DIR}/vless-agent" 2>/dev/null | od -A n -t x1 | tr -d ' ')
        if [ "$FILE_HEADER" != "7f454c46" ] && [ "$FILE_HEADER" != "cafebabe" ] && [ "$FILE_HEADER" != "feedface" ] && [ "$FILE_HEADER" != "feedfacf" ]; then
            log_error "下载的文件不是有效的可执行文件"
            rm -f "${INSTALL_DIR}/vless-agent"
            exit 1
        fi
    fi
    
    log_success "下载完成: ${INSTALL_DIR}/vless-agent (${FILE_SIZE} 字节)"
}

download_binary

# 配置服务
configure_service() {
    log_step "配置系统服务..."
    
    AGENT_ARGS="-e ${ENDPOINT} -t ${TOKEN}"
    if [ -n "$SERVER_NAME" ]; then
        AGENT_ARGS="$AGENT_ARGS -n \"${SERVER_NAME}\""
    fi
    
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=VLESS Agent Service
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/vless-agent ${AGENT_ARGS}
WorkingDirectory=${INSTALL_DIR}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable ${SERVICE_NAME}.service
        systemctl start ${SERVICE_NAME}.service
        log_success "systemd 服务已配置并启动"
        
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        cat > "/etc/init.d/${SERVICE_NAME}" << EOF
#!/sbin/openrc-run

name="VLESS Agent Service"
description="VLESS monitoring agent"
command="${INSTALL_DIR}/vless-agent"
command_args="${AGENT_ARGS}"
command_user="root"
directory="${INSTALL_DIR}"
pidfile="/run/${SERVICE_NAME}.pid"
supervisor=supervise-daemon

depend() {
    need net
    after network
}
EOF
        
        chmod +x "/etc/init.d/${SERVICE_NAME}"
        rc-update add ${SERVICE_NAME} default
        rc-service ${SERVICE_NAME} start
        log_success "OpenRC 服务已配置并启动"
        
    elif [ "$INIT_SYSTEM" = "procd" ]; then
        cat > "/etc/init.d/${SERVICE_NAME}" << EOF
#!/bin/sh /etc/rc.common

START=99
STOP=10
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command ${INSTALL_DIR}/vless-agent ${AGENT_ARGS}
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
        
        chmod +x "/etc/init.d/${SERVICE_NAME}"
        /etc/init.d/${SERVICE_NAME} enable
        /etc/init.d/${SERVICE_NAME} start
        log_success "procd 服务已配置并启动"
        
    elif [ "$INIT_SYSTEM" = "launchd" ]; then
        PLIST="/Library/LaunchDaemons/com.vless.${SERVICE_NAME}.plist"
        cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vless.${SERVICE_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/vless-agent</string>
        <string>-e</string>
        <string>${ENDPOINT}</string>
        <string>-t</string>
        <string>${TOKEN}</string>
EOF
        if [ -n "$SERVER_NAME" ]; then
            cat >> "$PLIST" << EOF
        <string>-n</string>
        <string>${SERVER_NAME}</string>
EOF
        fi
        cat >> "$PLIST" << EOF
    </array>
    <key>WorkingDirectory</key>
    <string>${INSTALL_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
        
        launchctl bootstrap system "$PLIST"
        log_success "launchd 服务已配置并启动"
        
    else
        log_warning "未知的 init 系统，请手动配置服务"
        log_info "运行命令: ${INSTALL_DIR}/vless-agent ${AGENT_ARGS}"
    fi
}

configure_service

echo ""
echo -e "${WHITE}========================================${NC}"
echo -e "${GREEN}    安装完成! (v${VERSION})${NC}"
echo -e "${WHITE}========================================${NC}"
echo ""
log_info "安装目录: ${GREEN}${INSTALL_DIR}${NC}"
log_info "服务名称: ${GREEN}${SERVICE_NAME}${NC}"

# 检查 vless 脚本状态
if [ -f "$VLESS_SCRIPT" ]; then
    log_info "vless 脚本: ${GREEN}已就绪${NC}"
else
    log_info "vless 脚本: ${YELLOW}未安装 (部分功能不可用)${NC}"
fi

echo ""
log_info "管理命令:"
if [ "$INIT_SYSTEM" = "systemd" ]; then
    echo -e "  查看状态: ${YELLOW}systemctl status ${SERVICE_NAME}${NC}"
    echo -e "  查看日志: ${YELLOW}journalctl -u ${SERVICE_NAME} -f${NC}"
    echo -e "  重启服务: ${YELLOW}systemctl restart ${SERVICE_NAME}${NC}"
elif [ "$INIT_SYSTEM" = "openrc" ]; then
    echo -e "  查看状态: ${YELLOW}rc-service ${SERVICE_NAME} status${NC}"
    echo -e "  重启服务: ${YELLOW}rc-service ${SERVICE_NAME} restart${NC}"
elif [ "$INIT_SYSTEM" = "launchd" ]; then
    echo -e "  查看状态: ${YELLOW}launchctl list | grep vless${NC}"
fi
