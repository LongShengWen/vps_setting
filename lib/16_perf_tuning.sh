tcp_tune_calculate_buffer_mb() {
    local bandwidth="$1"
    local region="${2:-asia}"

    if ! [[ "$bandwidth" =~ ^[0-9]+$ ]] || [ "$bandwidth" -le 0 ]; then
        echo "16"
        return 0
    fi

    if [ "$region" = "overseas" ]; then
        case "$bandwidth" in
            100) echo "8" ;;
            200) echo "16" ;;
            300) echo "20" ;;
            500) echo "32" ;;
            700) echo "48" ;;
            1000|1500|2000|2500) echo "64" ;;
            *)
                if [ "$bandwidth" -lt 500 ]; then
                    echo "16"
                elif [ "$bandwidth" -lt 1000 ]; then
                    echo "48"
                else
                    echo "64"
                fi
                ;;
        esac
    else
        case "$bandwidth" in
            100) echo "6" ;;
            200) echo "8" ;;
            300) echo "10" ;;
            500) echo "12" ;;
            700) echo "14" ;;
            1000) echo "16" ;;
            1500) echo "20" ;;
            2000) echo "24" ;;
            2500) echo "28" ;;
            *)
                if [ "$bandwidth" -lt 500 ]; then
                    echo "8"
                elif [ "$bandwidth" -lt 1000 ]; then
                    echo "12"
                elif [ "$bandwidth" -lt 2000 ]; then
                    echo "16"
                elif [ "$bandwidth" -lt 5000 ]; then
                    echo "24"
                elif [ "$bandwidth" -lt 10000 ]; then
                    echo "28"
                else
                    echo "32"
                fi
                ;;
        esac
    fi
}

cleanup_main_sysctl_for_tcp_tune() {
    [ -f /etc/sysctl.conf ] || return 0
    cp -af /etc/sysctl.conf /etc/sysctl.conf.bak.vps-init-suite-tcp 2>/dev/null || true
    sed -ri \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.core\.default_qdisc[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.tcp_congestion_control[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.core\.rmem_max[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.core\.wmem_max[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.tcp_rmem[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.tcp_wmem[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.tcp_tw_reuse[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.ip_local_port_range[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.core\.somaxconn[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.tcp_max_syn_backlog[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.core\.netdev_max_backlog[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.tcp_slow_start_after_idle[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.tcp_mtu_probing[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.tcp_notsent_lowat[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.tcp_fin_timeout[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.tcp_max_tw_buckets[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.tcp_fastopen[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.tcp_keepalive_time[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.tcp_keepalive_intvl[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.tcp_keepalive_probes[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.udp_rmem_min[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.udp_wmem_min[[:space:]=].*)$/# \1/I' \
        -e '/^[[:space:]]*#/! s/^[[:space:]]*(net\.ipv4\.tcp_syncookies[[:space:]=].*)$/# \1/I' \
        /etc/sysctl.conf
}

disable_conflicting_tcp_tune_dropins() {
    local changed=0
    local target ts
    ts=$(date +%F_%H%M%S)

    for target in /etc/sysctl.d/*.conf; do
        [ -f "$target" ] || continue
        [ "$target" = "$BBR_SYSCTL_FILE" ] && continue
        if grep -Eiq '^[[:space:]]*(net\.core\.default_qdisc|net\.ipv4\.tcp_congestion_control|net\.core\.(rmem_max|wmem_max)|net\.ipv4\.tcp_(rmem|wmem|tw_reuse|slow_start_after_idle|mtu_probing|notsent_lowat|fin_timeout|max_tw_buckets|fastopen|keepalive_time|keepalive_intvl|keepalive_probes|max_syn_backlog|syncookies)|net\.core\.somaxconn|net\.core\.netdev_max_backlog|net\.ipv4\.ip_local_port_range|net\.ipv4\.udp_(rmem_min|wmem_min))[[:space:]=]' "$target"; then
            mv "$target" "${target}.disabled.${ts}" || return 1
            changed=1
        fi
    done

    TCP_TUNE_CONFLICTS_DISABLED="$changed"
    return 0
}

apply_fq_to_physical_ifaces() {
    local dev applied=0
    command -v tc >/dev/null 2>&1 || return 0

    for dev in /sys/class/net/*; do
        [ -e "$dev" ] || continue
        dev=$(basename "$dev")
        case "$dev" in
            lo|docker*|veth*|br-*|virbr*|zt*|tailscale*|wg*|tun*|tap*) continue ;;
        esac
        tc qdisc replace dev "$dev" root fq >/dev/null 2>&1 && applied=$((applied + 1))
    done

    [ "$applied" -gt 0 ] && msg_ok "已对 ${applied} 个网卡应用fq。"
}

apply_bbr_optimization() {
    local available_cc bandwidth_choice region_choice region buffer_mb buffer_bytes
    local current_qdisc current_cc current_wmem current_rmem target_cc

    modprobe tcp_bbr >/dev/null 2>&1 || true
    available_cc=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if printf '%s\n' "$available_cc" | grep -qw bbr; then
        target_cc="bbr"
    else
        target_cc="${current_cc:-cubic}"
    fi

    draw_line
    msg_info "TCP网络调优"
    [ "$target_cc" != "bbr" ] && msg_warn "当前内核未提供bbr，将保留${target_cc}并只应用TCP参数。"
    msg_text "可选带宽: 100 / 200 / 300 / 500 / 700 / 1000 / 1500 / 2000 / 2500"
    while true; do
        read -p "带宽(Mbps)[默认: 1000]: " bandwidth_choice
        bandwidth_choice=${bandwidth_choice:-1000}
        if [[ "$bandwidth_choice" =~ ^[0-9]+$ ]] && [ "$bandwidth_choice" -gt 0 ]; then
            break
        fi
        msg_warn "请输入大于0的数字。"
    done

    while true; do
        read -p "地区[1=亚太, 2=美欧][默认: 1]: " region_choice
        region_choice=${region_choice:-1}
        case "$region_choice" in
            1) region="asia"; break ;;
            2) region="overseas"; break ;;
            *) msg_warn "请输入 1 或 2。" ;;
        esac
    done

    buffer_mb=$(tcp_tune_calculate_buffer_mb "$bandwidth_choice" "$region")
    buffer_bytes=$((buffer_mb * 1024 * 1024))

    draw_line
    status_pair "带宽" "${bandwidth_choice}Mbps"
    status_pair "地区" "$([ "$region" = "asia" ] && echo "亚太" || echo "美欧")"
    status_pair "缓冲区" "${buffer_mb}MB"
    status_pair "拥塞控制" "${target_cc}"
    draw_line

    cleanup_main_sysctl_for_tcp_tune || {
        msg_err "清理 /etc/sysctl.conf 冲突项失败。"
        return 1
    }

    TCP_TUNE_CONFLICTS_DISABLED=0
    disable_conflicting_tcp_tune_dropins || {
        msg_err "处理sysctl.d冲突配置失败。"
        return 1
    }
    [ "${TCP_TUNE_CONFLICTS_DISABLED:-0}" -eq 1 ] && msg_ok "已禁用冲突的sysctl.d配置。"

    mkdir -p /etc/sysctl.d
    cat > "$BBR_SYSCTL_FILE" <<EOF
# Managed by vps-init-suite
# Bandwidth=${bandwidth_choice}Mbps Region=${region} Buffer=${buffer_mb}MB CC=${target_cc}
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=${target_cc}
net.core.rmem_max=${buffer_bytes}
net.core.wmem_max=${buffer_bytes}
net.ipv4.tcp_rmem=4096 87380 ${buffer_bytes}
net.ipv4.tcp_wmem=4096 65536 ${buffer_bytes}
net.ipv4.tcp_tw_reuse=1
net.ipv4.ip_local_port_range=1024 65535
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=8192
net.core.netdev_max_backlog=5000
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_max_tw_buckets=5000
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=5
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
net.ipv4.tcp_syncookies=1
EOF

    sysctl -p "$BBR_SYSCTL_FILE" >/dev/null 2>&1 || {
        msg_err "TCP调优参数加载失败，请手动检查 ${BBR_SYSCTL_FILE}。"
        return 1
    }

    apply_fq_to_physical_ifaces

    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    current_wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null | awk '{print $3}')
    current_rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null | awk '{print $3}')

    if [ "$current_qdisc" = "fq" ] && [ "$current_cc" = "$target_cc" ] && \
       [ "$current_wmem" = "$buffer_bytes" ] && [ "$current_rmem" = "$buffer_bytes" ]; then
        msg_ok "TCP网络调优已生效。"
    else
        msg_warn "参数已写入，但存在部分未生效项，请检查 sysctl 输出。"
    fi
}

validate_non_negative_int() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

configure_swap_file() {
    local size_mb="$1"

    validate_non_negative_int "$size_mb" || {
        msg_err "Swap 大小必须是非负整数（单位：MB）。"
        return 1
    }

    if command -v swapon >/dev/null 2>&1; then
        swapon --show=NAME 2>/dev/null | awk '{print $1}' | grep -Fxq "/swapfile" && \
            swapoff /swapfile >/dev/null 2>&1 || true
    fi

    sed -i '\|^/swapfile[[:space:]]|d' /etc/fstab 2>/dev/null || true

    if [ "$size_mb" -eq 0 ]; then
        rm -f /swapfile
        msg_ok "已禁用并移除 /swapfile。"
        return 0
    fi

    rm -f /swapfile
    if command -v fallocate >/dev/null 2>&1; then
        fallocate -l "${size_mb}M" /swapfile 2>/dev/null || \
            dd if=/dev/zero of=/swapfile bs=1M count="$size_mb" status=none
    else
        dd if=/dev/zero of=/swapfile bs=1M count="$size_mb" status=none
    fi || {
        msg_err "创建 /swapfile 失败。"
        return 1
    }

    chmod 600 /swapfile || return 1
    mkswap /swapfile >/dev/null || {
        msg_err "mkswap 执行失败。"
        return 1
    }
    swapon /swapfile || {
        msg_err "swapon 执行失败。"
        return 1
    }
    printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
    msg_ok "Swap 配置完成：${size_mb}MB"
}

# 持久化保存 iptables 规则
