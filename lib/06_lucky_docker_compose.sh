# Lucky 普通版安装（固定安装到 /etc/lucky）
detect_lucky_arch() {
    local machine
    machine=$(uname -m 2>/dev/null | tr '[:upper:]' '[:lower:]')
    case "$machine" in
        x86_64|amd64) echo "x86_64" ;;
        i386|i486|i586|i686|x86) echo "i386" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armv7*) echo "armv7" ;;
        armv6l|armv6*) echo "armv6" ;;
        armv5l|armv5*|arm) echo "armv5" ;;
        riscv64) echo "riscv64" ;;
        mips64el|mipsel|mipsle) echo "mipsle_softfloat" ;;
        mips64|mips) echo "mips_softfloat" ;;
        *) return 1 ;;
    esac
}

install_lucky_standard() {
    local base_url="https://release.66666.host"
    local install_dir="/etc/lucky"
    local service_name="lucky.service"
    local service_path="/etc/systemd/system/${service_name}"
    local tmp_root package_file extract_dir
    local arch version plain_version subdir package_name package_url backup_dir
    local root_html version_html package_html

    ensure_basic_tool_installed curl curl || {
        msg_err "curl安装失败，无法继续安装Lucky。"
        return 1
    }
    ensure_basic_tool_installed tar tar || {
        msg_err "tar安装失败，无法继续安装Lucky。"
        return 1
    }

    arch=$(detect_lucky_arch) || {
        msg_err "暂不支持当前架构: $(uname -m 2>/dev/null)"
        return 1
    }

    msg_info "开始安装Lucky普通版"
    msg_info "固定安装目录: ${install_dir}"
    msg_info "识别到系统架构: ${arch}"

    root_html=$(curl -fsSL --connect-timeout 5 --max-time 300 "$base_url/") || {
        msg_err "获取Lucky发布列表失败: ${base_url}/"
        return 1
    }
    version=$(printf '%s\n' "$root_html" | grep -oE 'href="\./v[^"/]+/' | sed 's/^href="\.\/\(.*\)\/$/\1/' | grep -vi 'beta' | sort -V | tail -n 1)
    [ -n "$version" ] || {
        msg_err "未找到Lucky稳定版版本目录。"
        return 1
    }
    plain_version="${version#v}"

    version_html=$(curl -fsSL --connect-timeout 5 --max-time 300 "$base_url/$version/") || {
        msg_err "获取Lucky版本目录失败: ${base_url}/${version}/"
        return 1
    }
    subdir=$(printf '%s\n' "$version_html" | grep -oE 'href="\./[^"/]+/' | sed 's/^href="\.\/\(.*\)\/$/\1/' | grep -Fx "${plain_version}_lucky" | head -n 1)
    if [ -z "$subdir" ]; then
        subdir=$(printf '%s\n' "$version_html" | grep -oE 'href="\./[^"/]+/' | sed 's/^href="\.\/\(.*\)\/$/\1/' | grep '_lucky$' | grep -v '_docker$' | sort -V | tail -n 1)
    fi
    [ -n "$subdir" ] || {
        msg_err "未找到Lucky普通版目录。"
        return 1
    }

    package_html=$(curl -fsSL --connect-timeout 5 --max-time 300 "$base_url/$version/$subdir/") || {
        msg_err "获取Lucky安装包目录失败: ${base_url}/${version}/${subdir}/"
        return 1
    }
    package_name=$(printf '%s\n' "$package_html" | grep -oE 'href="\./[^"]+tar\.gz"' | sed 's/^href="\.\/\(.*\)"$/\1/' | grep -F "Linux_${arch}.tar.gz" | head -n 1)
    [ -n "$package_name" ] || {
        msg_err "未找到匹配架构${arch}的Lucky普通版安装包。"
        return 1
    }
    package_url="$base_url/$version/$subdir/$package_name"

    msg_info "将安装版本: ${version}"
    msg_info "版本目录: ${subdir}"
    msg_info "安装包: ${package_name}"

    tmp_root=$(mktemp -d /tmp/lucky-install.XXXXXX) || {
        msg_err "创建临时目录失败。"
        return 1
    }
    package_file="${tmp_root}/lucky.tar.gz"
    extract_dir="${tmp_root}/extract"
    mkdir -p "$extract_dir"

    if ! curl -fsSL --connect-timeout 5 --max-time 300 -o "$package_file" "$package_url"; then
        rm -rf "$tmp_root"
        msg_err "下载Lucky安装包失败: $package_url"
        return 1
    fi

    if ! tar -xzf "$package_file" -C "$extract_dir"; then
        rm -rf "$tmp_root"
        msg_err "解压Lucky安装包失败。"
        return 1
    fi

    [ -x "$extract_dir/lucky" ] || [ -f "$extract_dir/lucky" ] || {
        rm -rf "$tmp_root"
        msg_err "安装包内容异常：未找到 lucky 主程序。"
        return 1
    }

    if [ -e "$install_dir" ]; then
        backup_dir="${install_dir}.bak.$(date +%Y%m%d%H%M%S)"
        msg_warn "检测到已存在 ${install_dir}，将备份到 ${backup_dir}"
        mv "$install_dir" "$backup_dir" || {
            rm -rf "$tmp_root"
            msg_err "备份旧目录失败，已停止安装。"
            return 1
        }
    fi

    mkdir -p "$install_dir" || {
        rm -rf "$tmp_root"
        msg_err "创建安装目录失败: ${install_dir}"
        return 1
    }
    cp -a "$extract_dir"/. "$install_dir"/ || {
        rm -rf "$tmp_root"
        msg_err "复制Lucky文件到安装目录失败。"
        return 1
    }
    chmod 755 "$install_dir"
    chmod 755 "$install_dir/lucky" 2>/dev/null || true
    [ -d "$install_dir/scripts" ] && chmod 755 "$install_dir"/scripts/* 2>/dev/null || true

    ln -sfn "$install_dir/lucky" /usr/local/bin/lucky 2>/dev/null || true

    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now lucky.daji.service >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/lucky.daji.service /usr/lib/systemd/system/lucky.daji.service

        cat > "$service_path" <<EOF
[Unit]
Description=lucky
After=network.target

[Service]
Type=simple
User=root
ExecStart=${install_dir}/lucky -c ${install_dir}/lucky.conf
Restart=on-failure
RestartSec=3s
LimitNOFILE=999999
KillMode=process
WorkingDirectory=${install_dir}
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        chmod 644 "$service_path"
        systemctl daemon-reload || {
            rm -rf "$tmp_root"
            msg_err "systemctl daemon-reload 执行失败。"
            return 1
        }
        systemctl enable --now "$service_name" || {
            rm -rf "$tmp_root"
            msg_err "Lucky服务启动失败，请检查: systemctl status ${service_name}"
            return 1
        }
    else
        nohup "$install_dir/lucky" -c "$install_dir/lucky.conf" >/var/log/lucky.log 2>&1 &
        msg_warn "当前系统未检测到 systemd，已尝试后台启动 Lucky，但未配置开机自启。"
    fi

    rm -rf "$tmp_root"
    msg_ok "Lucky普通版安装完成"
    msg_info "安装目录: ${install_dir}"
    msg_info "默认管理端口通常为 16601，请按需放行防火墙。"
    command -v systemctl >/dev/null 2>&1 && systemctl --no-pager --full status "$service_name" 2>/dev/null | sed -n '1,12p'
}

configure_docker_daemon_logging() {
    local daemon_json="/etc/docker/daemon.json"
    local backup_path=""
    local merge_result=""
    DOCKER_DAEMON_CONFIG_STATE=""

    mkdir -p /etc/docker || return 1

    if [ -f "$daemon_json" ]; then
        backup_path="${daemon_json}.bak.$(date +%F_%H%M%S)"
        cp -af "$daemon_json" "$backup_path" || return 1
    fi

    if [ ! -s "$daemon_json" ]; then
        cat > "$daemon_json" <<EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "50m",
        "max-file": "3"
    }
}
EOF
        msg_ok "Docker 日志轮转配置已写入。"
        DOCKER_DAEMON_CONFIG_STATE="changed"
        return 0
    fi

    ensure_basic_tool_installed python3 python3 || {
        msg_err "未检测到 python3，无法安全合并现有 Docker 配置。"
        [ -n "$backup_path" ] && msg_warn "原配置备份: ${backup_path}"
        return 1
    }

    merge_result=$(python3 - "$daemon_json" <<'PY'
import json, os, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    raw = f.read().strip()

try:
    data = {} if not raw else json.loads(raw)
except Exception:
    print("invalid_json")
    raise SystemExit(0)

if not isinstance(data, dict):
    print("invalid_type")
    raise SystemExit(0)

driver = data.get("log-driver")
if driver not in (None, "json-file"):
    print(f"skipped_driver:{driver}")
    raise SystemExit(0)

changed = False
if driver is None:
    data["log-driver"] = "json-file"
    changed = True

log_opts = data.get("log-opts")
if log_opts is None:
    log_opts = {}
    data["log-opts"] = log_opts
    changed = True
elif not isinstance(log_opts, dict):
    print("invalid_log_opts")
    raise SystemExit(0)

targets = {"max-size": "50m", "max-file": "3"}
for key, value in targets.items():
    if log_opts.get(key) != value:
        log_opts[key] = value
        changed = True

if changed:
    tmp_path = f"{path}.tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)
        f.write("\n")
    os.replace(tmp_path, path)
    print("changed")
else:
    print("unchanged")
PY
)

    case "$merge_result" in
        changed)
            msg_ok "Docker 日志轮转配置已更新。"
            DOCKER_DAEMON_CONFIG_STATE="changed"
            return 0
            ;;
        unchanged)
            msg_info "Docker 日志轮转配置已存在，跳过修改。"
            DOCKER_DAEMON_CONFIG_STATE="unchanged"
            return 0
            ;;
        skipped_driver:*)
            msg_warn "检测到 Docker 使用非 json-file 日志驱动，保留现有配置: ${merge_result#skipped_driver:}"
            DOCKER_DAEMON_CONFIG_STATE="skipped"
            return 0
            ;;
        invalid_json)
            msg_err "现有 /etc/docker/daemon.json 不是合法 JSON，已停止修改。"
            [ -n "$backup_path" ] && msg_warn "原配置备份: ${backup_path}"
            return 1
            ;;
        invalid_type|invalid_log_opts)
            msg_err "现有 /etc/docker/daemon.json 结构异常，已停止修改。"
            [ -n "$backup_path" ] && msg_warn "原配置备份: ${backup_path}"
            return 1
            ;;
        *)
            msg_err "Docker 配置处理失败。"
            [ -n "$backup_path" ] && msg_warn "原配置备份: ${backup_path}"
            return 1
            ;;
    esac
}

ensure_docker_service_running() {
    local action="${1:-start}"

    if command -v systemctl >/dev/null 2>&1 && has_systemd_service "docker.service"; then
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl enable docker >/dev/null 2>&1 || true
        if [ "$action" = "restart" ]; then
            systemctl restart docker >/dev/null 2>&1 || systemctl start docker >/dev/null 2>&1 || return 1
        else
            systemctl start docker >/dev/null 2>&1 || return 1
        fi
        systemctl is-active --quiet docker >/dev/null 2>&1
        return $?
    fi

    if command -v service >/dev/null 2>&1; then
        if [ "$action" = "restart" ]; then
            service docker restart >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || return 1
        else
            service docker start >/dev/null 2>&1 || return 1
        fi
        return 0
    fi

    msg_warn "未检测到systemctl/service，无法自动管理Docker服务。"
    return 1
}

install_or_configure_docker() {
    local docker_preinstalled=0
    local config_state=""
    local service_action="start"
    local docker_script docker_rc use_aliyun=0

    ensure_basic_tool_installed curl curl || {
        msg_err "curl安装失败，无法继续安装Docker。"
        return 1
    }

    if command -v docker >/dev/null 2>&1; then
        docker_preinstalled=1
        msg_warn "检测到Docker已安装，跳过安装步骤。"
        docker --version
    else
        msg_info "正在准备安装Docker..."
        if confirm "是否使用阿里云镜像加速? (国内服务器推荐)"; then
            use_aliyun=1
        fi
        msg_info "开始下载并安装 (请耐心等待)..."
        docker_script=$(download_remote_script "https://get.docker.com" "/tmp/get-docker.XXXXXX.sh" "Docker安装脚本") || return 1
        if [ "$use_aliyun" -eq 1 ]; then
            bash "$docker_script" --mirror Aliyun
        else
            bash "$docker_script"
        fi
        docker_rc=$?
        rm -f "$docker_script"
        if [ "$docker_rc" -ne 0 ]; then
            msg_err "Docker安装脚本执行失败，请检查网络。"
            return 1
        fi
        command -v docker >/dev/null 2>&1 || {
            msg_err "Docker安装后未检测到docker命令。"
            return 1
        }
    fi

    msg_info "正在配置Docker日志轮转策略..."
    configure_docker_daemon_logging || return 1
    config_state="$DOCKER_DAEMON_CONFIG_STATE"

    if [ "$docker_preinstalled" -eq 0 ] || [ "$config_state" = "changed" ]; then
        service_action="restart"
    fi

    msg_info "启动Docker服务..."
    if ! ensure_docker_service_running "$service_action"; then
        msg_err "Docker服务启动失败，请检查服务状态。"
        return 1
    fi

    msg_ok "Docker安装/配置完成！"
    draw_line
    status_pair "Docker版本" "$(docker --version 2>/dev/null || echo N/A)"
    status_pair "Compose版本" "$(docker compose version 2>/dev/null || echo 未检测到)"
    draw_line
    return 0
}

ensure_docker_compose_available() {
    if docker compose version >/dev/null 2>&1; then
        return 0
    fi

    msg_warn "未检测到 docker compose 插件，尝试安装 docker-compose-plugin。"
    pkg_update || true
    if ! pkg_install docker-compose-plugin; then
        msg_err "docker-compose-plugin 安装失败。"
        return 1
    fi

    docker compose version >/dev/null 2>&1 || {
        msg_err "安装后仍未检测到 docker compose 命令。"
        return 1
    }
}

sync_docker_compose_repo_files() {
    local parent_dir backup_dir

    ensure_basic_tool_installed git git || {
        msg_err "git 安装失败，无法同步 Docker Compose 仓库。"
        return 1
    }

    parent_dir=$(dirname "$DOCKER_COMPOSE_STACK_DIR")
    mkdir -p "$parent_dir" || {
        msg_err "创建目录失败: ${parent_dir}"
        return 1
    }

    if [ -d "${DOCKER_COMPOSE_STACK_DIR}/.git" ]; then
        msg_info "正在更新 Compose 仓库: ${DOCKER_COMPOSE_STACK_DIR}"
        git -C "$DOCKER_COMPOSE_STACK_DIR" remote set-url origin "$DOCKER_COMPOSE_REPO_URL" >/dev/null 2>&1 || true
        git -C "$DOCKER_COMPOSE_STACK_DIR" pull --ff-only || {
            msg_err "Compose 仓库更新失败，请检查目录状态: ${DOCKER_COMPOSE_STACK_DIR}"
            return 1
        }
    else
        if [ -e "$DOCKER_COMPOSE_STACK_DIR" ]; then
            backup_dir="${DOCKER_COMPOSE_STACK_DIR}.bak.$(date +%Y%m%d%H%M%S)"
            msg_warn "检测到已存在 ${DOCKER_COMPOSE_STACK_DIR}，将移动到 ${backup_dir}"
            mv "$DOCKER_COMPOSE_STACK_DIR" "$backup_dir" || {
                msg_err "移动旧目录失败: ${DOCKER_COMPOSE_STACK_DIR}"
                return 1
            }
        fi

        msg_info "正在克隆 Compose 仓库..."
        git clone --depth 1 "$DOCKER_COMPOSE_REPO_URL" "$DOCKER_COMPOSE_STACK_DIR" || {
            msg_err "Compose 仓库克隆失败。"
            return 1
        }
    fi

    msg_ok "Compose 文件目录: ${DOCKER_COMPOSE_STACK_DIR}"
}

list_docker_compose_repo_files() {
    local file found=0

    for file in "${DOCKER_COMPOSE_STACK_DIR}"/*.yml "${DOCKER_COMPOSE_STACK_DIR}"/*.yaml; do
        [ -f "$file" ] || continue
        found=1
        basename "$file"
    done

    [ "$found" -eq 1 ]
}

ensure_builtin_compose_templates() {
    local iyuu_file="${DOCKER_COMPOSE_STACK_DIR}/iyuu.yml"
    local transmission_file="${DOCKER_COMPOSE_STACK_DIR}/transmission.yml"
    local transmission_user transmission_pass

    mkdir -p "$DOCKER_COMPOSE_STACK_DIR" || return 1

    if [ -f "$iyuu_file" ]; then
        msg_info "iyuu.yml 已存在，保留现有文件。"
    else
        cat > "$iyuu_file" <<'EOF'
version: '3'

services:
  iyuu:
    image: iyuucn/iyuuplus-dev:latest
    container_name: iyuu
    stdin_open: true
    tty: true
    environment:
      - TZ=Asia/Shanghai
    volumes:
      - /data/docker/iyuu:/iyuu
      - /data/docker/iyuu-data:/data
    ports:
      - "8780:8780"
    restart: unless-stopped
    labels:
      com.centurylinklabs.watchtower.enable: "true"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

        msg_ok "已生成内置 Compose 模板: ${iyuu_file}"
    fi

    if [ -f "$transmission_file" ]; then
        msg_info "transmission.yml 已存在，保留现有文件。"
    else
        prompt_valid_username "请输入 Transmission 用户名" "admin" transmission_user || return 1
        prompt_password_twice "Transmission 用户 ${transmission_user}" transmission_pass || return 1

        cat > "$transmission_file" <<EOF
version: '3'

services:
  transmission:
    image: lscr.io/linuxserver/transmission:latest
    container_name: transmission
    environment:
      - TZ=Asia/Shanghai
      - PUID=0
      - PGID=0
      - USER=${transmission_user}
      - PASS=${transmission_pass}
    volumes:
      - /data/docker/transmission:/config
      - /data/download:/downloads
      - /data/docker/transmission-watch:/watch
    ports:
      - "9091:9091"
      - "51413:51413"
      - "51413:51413/udp"
    restart: unless-stopped
    labels:
      com.centurylinklabs.watchtower.enable: "true"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

        msg_ok "已生成内置 Compose 模板: ${transmission_file}"
    fi
}

deploy_one_compose_file() {
    local compose_file="$1"
    local compose_name project_name

    [ -f "$compose_file" ] || {
        msg_err "Compose 文件不存在: ${compose_file}"
        return 1
    }

    compose_name=$(basename "$compose_file")
    project_name="${compose_name%.*}"
    project_name=$(printf '%s' "$project_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/^[^a-z0-9]+//')
    project_name=${project_name:-composeapp}

    msg_info "正在部署 ${compose_name} ..."
    docker compose -p "$project_name" -f "$compose_file" up -d
}

install_docker_compose_repo_services() {
    local selected compose_file rc=0 file_list i file
    local -a compose_files=()

    install_or_configure_docker || return 1
    ensure_docker_compose_available || return 1
    sync_docker_compose_repo_files || return 1
    ensure_builtin_compose_templates || return 1

    file_list=$(list_docker_compose_repo_files) || {
        msg_err "仓库中未找到 .yml/.yaml Compose 文件。"
        return 1
    }

    while IFS= read -r file; do
        [ -n "$file" ] || continue
        compose_files+=("$file")
    done <<< "$file_list"

    while true; do
        draw_line
        msg_info "请选择要部署的单个 Compose 文件:"
        i=1
        for file in "${compose_files[@]}"; do
            printf '  [%d] %s\n' "$i" "$file"
            i=$((i + 1))
        done
        printf '  [0] 结束部署\n'
        draw_line
        read -r -p "请输入编号: " selected

        if [ "$selected" = "0" ]; then
            break
        fi

        if ! [[ "$selected" =~ ^[0-9]+$ ]] || [ "$selected" -lt 1 ] || [ "$selected" -gt "${#compose_files[@]}" ]; then
            msg_err "编号无效: ${selected}"
            continue
        fi

        compose_file="${DOCKER_COMPOSE_STACK_DIR}/${compose_files[$((selected - 1))]}"
        deploy_one_compose_file "$compose_file" || rc=1

        draw_line
        docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
        draw_line
    done

    draw_line
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
    draw_line

    if [ "$rc" -eq 0 ]; then
        msg_ok "Docker Compose 单项部署流程已结束。"
    else
        msg_err "部分 Docker Compose 服务部署失败，请查看上方输出。"
    fi
    return "$rc"
}
