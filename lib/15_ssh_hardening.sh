download_reinstall_script_if_missing() {
    local url="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"

    if [ -f "reinstall.sh" ]; then
        return 0
    fi

    msg_info "正在下载reinstall.sh脚本..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 5 --max-time 300 -o reinstall.sh "$url" || {
            msg_err "reinstall.sh 下载失败。"
            return 1
        }
    elif command -v wget >/dev/null 2>&1; then
        wget -O reinstall.sh "$url" || {
            msg_err "reinstall.sh 下载失败。"
            return 1
        }
    else
        msg_err "错误：未找到curl或wget，无法下载脚本。"
        return 1
    fi

    chmod +x reinstall.sh
}

get_ssh_service_name() {
    if [ -n "$SSH_SERVICE_NAME_CACHE" ]; then
        printf '%s\n' "$SSH_SERVICE_NAME_CACHE"
        return 0
    fi

    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then
        SSH_SERVICE_NAME_CACHE="ssh"
    elif command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q '^sshd\.service'; then
        SSH_SERVICE_NAME_CACHE="sshd"
    elif command -v systemctl >/dev/null 2>&1 && systemctl status ssh >/dev/null 2>&1; then
        SSH_SERVICE_NAME_CACHE="ssh"
    else
        SSH_SERVICE_NAME_CACHE="sshd"
    fi

    printf '%s\n' "$SSH_SERVICE_NAME_CACHE"
}

restart_ssh_service() {
    local ssh_service="${1:-$(get_ssh_service_name)}"
    systemctl restart "$ssh_service" >/dev/null 2>&1 || \
    service "$ssh_service" restart >/dev/null 2>&1
}

enable_ssh_service() {
    local ssh_service="${1:-$(get_ssh_service_name)}"
    systemctl enable "$ssh_service" >/dev/null 2>&1 || true
    systemctl start "$ssh_service" >/dev/null 2>&1 || service "$ssh_service" start >/dev/null 2>&1 || true
}

cleanup_ssh_socket_activation() {
    local socket_conf="/etc/systemd/system/ssh.socket.d/override.conf"
    if systemctl is-active --quiet ssh.socket 2>/dev/null || \
       systemctl is-enabled --quiet ssh.socket 2>/dev/null || \
       [ -f "$socket_conf" ]; then
        systemctl stop ssh.socket >/dev/null 2>&1 || true
        systemctl disable ssh.socket >/dev/null 2>&1 || true
        rm -f "$socket_conf"
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
}

backup_file_with_timestamp() {
    local target_file="$1"
    local backup_path="${target_file}.bak.$(date +%F_%H%M%S)"
    cp -af "$target_file" "$backup_path"
    if [ "$target_file" = "/etc/ssh/sshd_config" ]; then
        if [ -f "$SSHD_MANAGED_OVERRIDE_FILE" ]; then
            LAST_SSHD_OVERRIDE_BACKUP="${SSHD_MANAGED_OVERRIDE_FILE}.bak.$(date +%F_%H%M%S)"
            cp -af "$SSHD_MANAGED_OVERRIDE_FILE" "$LAST_SSHD_OVERRIDE_BACKUP"
        else
            LAST_SSHD_OVERRIDE_BACKUP="__ABSENT__"
        fi
    fi
    echo "$backup_path"
}

ensure_sshd_managed_override_include() {
    local tmp_file
    mkdir -p /etc/ssh
    touch /etc/ssh/sshd_config
    touch "$SSHD_MANAGED_OVERRIDE_FILE"
    tmp_file=$(mktemp) || {
        msg_err "创建临时文件失败，无法调整 sshd Include 顺序。"
        return 1
    }

    {
        printf 'Include %s\n' "$SSHD_MANAGED_OVERRIDE_FILE"
        awk -v line="Include ${SSHD_MANAGED_OVERRIDE_FILE}" '
            $0 == line { next }
            { print }
        ' /etc/ssh/sshd_config
    } > "$tmp_file" || {
        rm -f "$tmp_file"
        msg_err "重写 /etc/ssh/sshd_config 失败。"
        return 1
    }

    cat "$tmp_file" > /etc/ssh/sshd_config || {
        rm -f "$tmp_file"
        msg_err "写回 /etc/ssh/sshd_config 失败。"
        return 1
    }

    rm -f "$tmp_file"
}

restore_sshd_backup_state() {
    local ssh_backup="$1"
    [ -n "$ssh_backup" ] && [ -f "$ssh_backup" ] && cp -af "$ssh_backup" /etc/ssh/sshd_config

    case "$LAST_SSHD_OVERRIDE_BACKUP" in
        "__ABSENT__")
            rm -f "$SSHD_MANAGED_OVERRIDE_FILE"
            ;;
        "")
            ;;
        *)
            [ -f "$LAST_SSHD_OVERRIDE_BACKUP" ] && cp -af "$LAST_SSHD_OVERRIDE_BACKUP" "$SSHD_MANAGED_OVERRIDE_FILE"
            ;;
    esac
}

set_sshd_directive() {
    local key="$1"
    local value="$2"
    local config_file="${3:-$SSHD_MANAGED_OVERRIDE_FILE}"
    [ "$config_file" = "$SSHD_MANAGED_OVERRIDE_FILE" ] && ensure_sshd_managed_override_include
    sed -i "/^[[:space:]#]*${key}[[:space:]]\\+/Id" "$config_file"
    printf '%s %s\n' "$key" "$value" >> "$config_file"
}

delete_sshd_directive() {
    local key="$1"
    local config_file="${2:-$SSHD_MANAGED_OVERRIDE_FILE}"
    [ "$config_file" = "$SSHD_MANAGED_OVERRIDE_FILE" ] && ensure_sshd_managed_override_include
    sed -i "/^[[:space:]#]*${key}[[:space:]]\\+/Id" "$config_file"
}

validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

prompt_password_twice() {
    local prompt_label="$1"
    local __resultvar="$2"
    local p1 p2
    while true; do
        read -s -p "请输入${prompt_label}密码: " p1; echo
        read -s -p "请再次输入${prompt_label}密码以确认: " p2; echo
        if [ -z "$p1" ]; then
            msg_warn "密码不能为空。"
            continue
        fi
        if [ "$p1" != "$p2" ]; then
            msg_warn "两次输入的密码不一致。"
            continue
        fi
        printf -v "$__resultvar" '%s' "$p1"
        return 0
    done
}

ensure_ssh_server_installed() {
    if command -v sshd >/dev/null 2>&1; then
        return 0
    fi
    msg_warn "未检测到 openssh-server，正在尝试自动安装..."
    pkg_update || true
    pkg_install openssh-server || {
        msg_err "openssh-server 安装失败，请手动检查。"
        return 1
    }
    command -v sshd >/dev/null 2>&1
}

ensure_user_in_admin_group() {
    local username="$1"
    if getent group sudo >/dev/null 2>&1; then
        usermod -aG sudo "$username"
    elif getent group wheel >/dev/null 2>&1; then
        usermod -aG wheel "$username"
    else
        msg_warn "未检测到 sudo/wheel 组，跳过管理员组设置。"
    fi
}

handle_selinux_ssh_port() {
    local port="$1"
    local pkg_mgr

    if ! command -v getenforce >/dev/null 2>&1; then
        return 0
    fi
    if [ "$(getenforce 2>/dev/null || true)" != "Enforcing" ]; then
        return 0
    fi

    if ! command -v semanage >/dev/null 2>&1; then
        pkg_mgr=$(get_pkg_manager)
        msg_info "检测到 SELinux=Enforcing，正在补装 semanage..."
        case "$pkg_mgr" in
            dnf) pkg_install policycoreutils-python-utils || true ;;
            yum) pkg_install policycoreutils-python policycoreutils-python-utils || true ;;
            apt) pkg_install policycoreutils python3-semanage || true ;;
        esac
    fi

    if ! command -v semanage >/dev/null 2>&1; then
        msg_err "SELinux 正在 Enforcing，但 semanage 不可用，无法安全放行 SSH 端口 ${port}。"
        return 1
    fi

    if ! semanage port -l | awk '/^ssh_port_t[[:space:]]+tcp/ {print}' | grep -qw "$port"; then
        semanage port -a -t ssh_port_t -p tcp "$port" 2>/dev/null || \
        semanage port -m -t ssh_port_t -p tcp "$port"
    fi
    return 0
}

disable_other_firewalls_quiet() {
    if systemctl list-unit-files 2>/dev/null | grep -q '^firewalld\.service'; then
        systemctl stop firewalld >/dev/null 2>&1 || true
        systemctl disable firewalld >/dev/null 2>&1 || true
        systemctl mask firewalld >/dev/null 2>&1 || true
    fi

    if command -v ufw >/dev/null 2>&1; then
        ufw disable >/dev/null 2>&1 || true
    fi
    if systemctl list-unit-files 2>/dev/null | grep -q '^ufw\.service'; then
        systemctl stop ufw >/dev/null 2>&1 || true
        systemctl disable ufw >/dev/null 2>&1 || true
        systemctl mask ufw >/dev/null 2>&1 || true
    fi

    if command -v nft >/dev/null 2>&1; then
        nft flush ruleset >/dev/null 2>&1 || true
        printf '#!/usr/sbin/nft -f\nflush ruleset\n' > /etc/nftables.conf 2>/dev/null || true
    fi
    if systemctl list-unit-files 2>/dev/null | grep -q '^nftables\.service'; then
        systemctl stop nftables >/dev/null 2>&1 || true
        systemctl disable nftables >/dev/null 2>&1 || true
        systemctl mask nftables >/dev/null 2>&1 || true
    fi
}

# 检查是否安装 fail2ban
check_fail2ban() {
    if command -v fail2ban-client &>/dev/null; then
        echo "已安装"
    else
        echo "未安装"
    fi
}

ensure_fail2ban_installed() {
    if command -v fail2ban-client >/dev/null 2>&1; then
        return 0
    fi
    msg_info "未检测到 Fail2Ban，正在尝试自动安装..."
    pkg_update || true
    pkg_install fail2ban || {
        msg_err "Fail2Ban 安装失败，请检查软件源或系统兼容性。"
        return 1
    }
    command -v fail2ban-client >/dev/null 2>&1
}

get_fail2ban_sshd_backend() {
    if command -v journalctl >/dev/null 2>&1 && \
       command -v python3 >/dev/null 2>&1 && \
       python3 - <<'PY' >/dev/null 2>&1
import systemd.journal
PY
    then
        echo "systemd"
    else
        echo "auto"
    fi
}

get_fail2ban_banaction() {
    local backend
    backend=$(detect_firewall_backend 2>/dev/null || true)

    if [ "$backend" = "nft" ] && [ -f /etc/fail2ban/action.d/nftables.conf ]; then
        echo "nftables"
    else
        echo "iptables-multiport"
    fi
}

# 更新 fail2ban 中 sshd jail 的端口配置并重启/重载 fail2ban
update_fail2ban_ssh_port() {
    local ports="$1"
    local f2b_backend f2b_banaction
    [ -z "$ports" ] && ports=$(get_current_ssh_ports_csv)

    if ! command -v fail2ban-client &>/dev/null; then
        msg_warn "未检测到 Fail2Ban，跳过 SSH 端口同步。"
        return 1
    fi

    f2b_backend=$(get_fail2ban_sshd_backend)
    f2b_banaction=$(get_fail2ban_banaction)

    mkdir -p /etc/fail2ban/jail.d
    cat > "$FAIL2BAN_SSH_JAIL_FILE" <<EOF
[sshd]
enabled = true
filter = sshd
port = ${ports}
logpath = %(sshd_log)s
backend = ${f2b_backend}
banaction = ${f2b_banaction}
maxretry = 5
findtime = 10m
bantime = 1h
EOF
    if [ "$f2b_backend" = "systemd" ]; then
        cat >> "$FAIL2BAN_SSH_JAIL_FILE" <<'EOF'
journalmatch = _SYSTEMD_UNIT=ssh.service + _SYSTEMD_UNIT=sshd.service + _COMM=sshd
EOF
    fi

    if ! fail2ban-client -d >/dev/null 2>&1; then
        msg_err "Fail2Ban 配置校验失败，请检查 ${FAIL2BAN_SSH_JAIL_FILE}"
        return 1
    fi

    systemctl enable fail2ban >/dev/null 2>&1 || true
    if systemctl restart fail2ban >/dev/null 2>&1 || \
       service fail2ban restart >/dev/null 2>&1 || \
       fail2ban-client reload >/dev/null 2>&1; then
        msg_ok "Fail2Ban 已按当前 SSH 端口同步: ${ports}"
        return 0
    fi

    msg_err "Fail2Ban 重启/重载失败，请检查服务状态。"
    return 1
}

install_and_configure_fail2ban() {
    ensure_fail2ban_installed || return 1
    update_fail2ban_ssh_port "$(get_current_ssh_ports_csv)"
}
