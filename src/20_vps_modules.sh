# ============================================================
# VPS 新机一键初始化模块（纯净极智版）
# 作者定制：基于用户需求提纯的核心服务器配置脚本
# ============================================================

# 分隔线工具函数
line() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# VPS 模块专用输出（前缀 >>> 风格，与 DMIT 模块的 ✔/➜/⚠ 风格区分）
vps_ok()    { echo -e "${GREEN}>>> [OK] $1${NC}"; }
vps_info()  { echo -e "${CYAN}>>> [INFO] $1${NC}"; }
vps_error() { echo -e "${RED}>>> [ERROR] $1${NC}"; exit 1; }

# [核心鉴权]
[ "$(id -u)" -ne 0 ] && vps_error "操作敏感，请务必使用超级系统权限(root用户)运行此脚本！"

# === 模块 1：更新与软件 ===
# 【优化】增加 DEBIAN_FRONTEND=noninteractive 和 --force-confold，防止 dpkg 弹窗卡住脚本
# 【优化】拆分为两步独立输出，进度更清晰
func_update() {
    export DEBIAN_FRONTEND=noninteractive

    # 第一步：更新系统软件库
    vps_info "正在更新系统软件库并升级已安装的软件包..."
    apt update -y && apt upgrade -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
    vps_ok "系统软件库更新完成，所有已安装包已升级到最新版本！"
    echo ""

    # 第二步：安装必备基础软件
    vps_info "正在安装必备基础软件 (sudo/curl/wget/nano/procps)..."
    apt install -y sudo curl wget nano procps
    vps_ok "必备软件全部就位！"
}

# === 模块 2：时区校正 ===
func_timezone() {
    vps_info "正在校正系统主板时钟，并设置时区为亚洲/上海..."
    timedatectl set-timezone Asia/Shanghai
    vps_ok "操作成功！当前机器时间已被校准为：$(date '+%Y-%m-%d %H:%M:%S')"
}

# === 模块 3：交互式 SWAP ===
# 【优化】dd 增加 status=progress 进度提示
func_swap() {
    echo ""
    vps_info "正在启动交互式 SWAP 磁盘虚拟内存管理程序..."
    echo "【系统当前内存余量扫描】"
    free -h
    echo ""
    echo -e "  ${YELLOW}1.${NC} 给 VPS 添加一块新的 SWAP 空间 (${GREEN}防止小内存爆满当机${NC})"
    echo -e "  ${YELLOW}2.${NC} 安全卸载并彻底删除系统上的 SWAP (${RED}强迫症患者清理磁盘${NC})"
    echo -e "  ${YELLOW}0.${NC} 跳过此项配置"
    read -p "=> 请抉择执行的操作号 [0-2]: " swap_choice

    if [ "$swap_choice" == "1" ]; then
        read -p "=> 请输入你要割让多少 MB 的硬盘做缓冲池？ (常用推荐: 1024 或者 2048): " swap_mb
        if [[ ! "$swap_mb" =~ ^[0-9]+$ ]]; then
            vps_error "系统无法识别！请输入纯粹的数字（例如 2048）。操作终止。"
        fi
        vps_info "正在将 ${swap_mb}MB 物理硬盘转化配置为 SWAP 虚拟池..."

        # 先清除掉机器可能残留的历史配置
        if grep -q "/swapfile" /etc/fstab || [ -f /swapfile ]; then
            swapoff -a >/dev/null 2>&1
            sed -i '/swap/d' /etc/fstab
            rm -f /swapfile
        fi

        # 创建零填充文件（status=progress 显示进度）
        dd if=/dev/zero of=/swapfile bs=1M count=$swap_mb status=progress
        chmod 600 /swapfile
        mkswap /swapfile > /dev/null 2>&1
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        vps_ok "挂载顺利完成！请检阅上方最终成果："
        free -m | grep -i swap

    elif [ "$swap_choice" == "2" ]; then
        vps_info "正在安全抽离配置表，并彻底释放出 SWAP 占用的硬盘空间..."
        swapoff -a >/dev/null 2>&1
        sed -i '/swap/d' /etc/fstab
        rm -f /swapfile
        vps_ok "剔除干净得就像刚买来一样！系统配置表(fstab)和残留(/swapfile)均已灰飞烟灭。"
    else
        vps_info "已跳过虚拟内存规划。"
    fi
}

# === 模块 4：Fail2ban ===
# 【优化】动态读取当前 SSH 端口，不再硬编码 55520
func_fail2ban() {
    vps_info "正在下载防暴系统中心 fail2ban..."
    export DEBIAN_FRONTEND=noninteractive
    apt install -y fail2ban

    # 动态获取当前 SSH 端口（兼容未改端口和已改端口的情况）
    local ssh_port
    ssh_port=$(grep -E '^[[:space:]]*Port[[:space:]]' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)
    ssh_port="${ssh_port:-22}"

    vps_info "正在将定制防护伞机制写入 /etc/fail2ban/jail.local（监控端口: ${ssh_port}）..."

    cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
ignoreip = 127.0.0.1
allowipv6 = auto
backend = systemd

[sshd]
enabled = true
filter = sshd
port = ${ssh_port}
action = iptables[name=SSH, port=${ssh_port}, protocol=tcp]
logpath = %(sshd_log)s
bantime = 86400
findtime = 86400
maxretry = 3
EOF

    systemctl enable fail2ban >/dev/null 2>&1
    systemctl restart fail2ban
    vps_ok "堡垒防护已上线！全网所有胆敢连续猜错 3 次密码的野鸡扫描器将会被物理拉黑 24 小时。（监控端口: ${ssh_port}）"
}

# === 模块 5：修改 SSH 端口与密钥登录 ===
func_ssh_secure() {
    vps_info "正在将 SSH 默认端口 22 修改为隐蔽端口 55520 (防扫描)..."
    sed -i 's/^#\?Port .*/Port 55520/g' /etc/ssh/sshd_config
    if ! grep -q "^Port 55520" /etc/ssh/sshd_config; then
        echo "Port 55520" >> /etc/ssh/sshd_config
    fi
    systemctl restart sshd
    vps_ok "SSH 端口已成功修改为 55520！请务必记住下次连接机器时指定 -p 55520"
    echo "-----------------------------------"
    vps_info "调用你指定的开源密钥挂载体系(yuju520/Script)接入中..."
    echo -e "${RED}${BOLD}=================== 【生 死 警 告】 ===================${NC}"
    echo -e "${YELLOW}一旦你生成完密钥退出系统，你以后将永远无法再通过普通的密码方式登录机器！${NC}"
    echo -e "${YELLOW}你必须极其妥善地把私钥(Private Key)保存在你的所有电脑终端口。${NC}"
    echo -e "${RED}${BOLD}=======================================================${NC}"
    echo -e "[系统将停顿 ${GREEN}5秒${NC} 给你犹豫时间，如果不想玩高级密码锁，请猛按 ${RED}Ctrl+C${NC} 中断]"
    sleep 5
    wget -qO /tmp/key.sh https://raw.githubusercontent.com/yuju520/Script/main/key.sh && chmod +x /tmp/key.sh && bash /tmp/key.sh; rm -f /tmp/key.sh
}

# === 模块 6：内核/网络深度调优（jerry048/Tune） ===
# 【修复】jerry048/Tune 新版已移除 -x (BBRx) 选项，-t 已包含 BBR + sysctl + 网卡调优
# 调优项：BBR 拥塞控制、FQ 队列、TCP 缓冲区、网卡环形缓冲区、offload 等，sysctl 即时生效
func_tune_bbr() {
    vps_info "远程调用 jerry048/Tune 进行系统级内核与网络深度调优 (-t)..."
    vps_info "包含：BBR 拥塞控制 / sysctl 参数优化 / 网卡环形缓冲区 / TCP 缓冲区调优"
    bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Tune/main/tune.sh) -t
    vps_ok "内核/网络调优全部注入完成！BBR + FQ + TCP 缓冲区 + 网卡参数已即时生效。"
    echo ""
    echo -e "${GREEN}💡 调优参数已通过 sysctl 即时生效，无需重启。${NC}"
    echo -e "${YELLOW}   部分系统级限制（如 ulimit）需要重新登录 SSH 会话后才能完全生效。${NC}"
}
