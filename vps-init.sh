#!/bin/bash
# ============================================================
# VPS 新机一键初始化脚本 (纯净极智版)
# 作者定制：基于用户需求提纯的核心服务器配置脚本
# ============================================================

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'
BOLD=$'\033[1m'

line() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
ok() { echo -e "${GREEN}>>> [OK] $1${NC}"; }
info() { echo -e "${CYAN}>>> [INFO] $1${NC}"; }
error() { echo -e "${RED}>>> [ERROR] $1${NC}"; exit 1; }

# [核心鉴权]
[ "$(id -u)" -ne 0 ] && error "操作敏感，请务必使用超级系统权限(root用户)运行此脚本！"

# === 模块 1：更新与软件 ===
func_update() {
    info "正在高速更新底层系统包目录，并安装必备基础软件..."
    apt update -y && apt upgrade -y
    apt install -y sudo curl wget nano procps
    ok "所有系统补丁拉取完成！必备软件(curl/wget/nano/sudo)均已存在于系统中。"
}

# === 模块 2：时区校正 ===
func_timezone() {
    info "正在校正系统主板时钟，并设置时区为亚洲/上海..."
    timedatectl set-timezone Asia/Shanghai
    ok "操作成功！当前机器时间已被校准为：$(date '+%Y-%m-%d %H:%M:%S')"
}

# === 模块 3：交互式 SWAP ===
func_swap() {
    echo ""
    info "正在启动交互式 SWAP 磁盘虚拟内存管理程序..."
    echo "【系统当前内存余量扫描】"
    free -h
    echo ""
    echo -e "  ${YELLOW}1.${NC} 给 VPS 添加一块新的 SWAP 空间 (${GREEN}防止小内存爆满当机${NC})"
    echo -e "  ${YELLOW}2.${NC} 安全卸载并彻底删除系统上的 SWAP (${RED}强迫症患者清理磁盘${NC})"
    echo -e "  ${YELLOW}0.${NC} 跳过此项配置"
    read -p "=> 请抉择执行的操作号 [0-2]: " swap_choice

    if [ "$swap_choice" == "1" ]; then
        read -p "=> 请输入你要割让多少 MB 的硬盘做缓冲池？ (常用推荐: 1024 或者 2048): " swap_mb
        # 正则判断纯文字输入防止破坏
        if [[ ! "$swap_mb" =~ ^[0-9]+$ ]]; then
            error "系统无法识别！请输入纯粹的数字（例如 2048）。操作终止。"
        fi
        info "正在将 ${swap_mb}MB 物理硬盘转化配置为 SWAP 虚拟池..."

        # 先清除掉机器可能残留的历史配置
        if grep -q "/swapfile" /etc/fstab || [ -f /swapfile ]; then
            swapoff -a >/dev/null 2>&1
            sed -i '/swap/d' /etc/fstab
            rm -f /swapfile
        fi

        # 创建零填充文件 (使用 dd 创建并挂载)
        dd if=/dev/zero of=/swapfile bs=1M count=$swap_mb status=none
        chmod 600 /swapfile
        mkswap /swapfile > /dev/null 2>&1
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        ok "挂载顺利完成！请检阅上方最终成果："
        free -m | grep -i swap

    elif [ "$swap_choice" == "2" ]; then
        info "正在安全抽离配置表，并彻底释放出 SWAP 占用的硬盘空间..."
        # 多层校验删除
        swapoff -a >/dev/null 2>&1
        sed -i '/swap/d' /etc/fstab
        rm -f /swapfile
        ok "剔除干净得就像刚买来一样！系统配置表(fstab)和残留(/swapfile)均已灰飞烟灭。"
    else
        info "已跳过虚拟内存规划。"
    fi
}

# === 模块 4：Fail2ban ===
func_fail2ban() {
    info "正在下载防暴系统中心 fail2ban..."
    apt install -y fail2ban
    info "正在将定制防护伞机制写入 /etc/fail2ban/jail.local..."
    
    # 按照需求定死防破封策略 (1次连续封印1天，可错3次)
    cat << EOF > /etc/fail2ban/jail.local
[DEFAULT]
ignoreip = 127.0.0.1
allowipv6 = auto
backend = systemd

[sshd]
enabled = true
filter = sshd
port = 55520
action = iptables[name=SSH, port=55520, protocol=tcp]
logpath = /var/log/auth.log
bantime = 86400
findtime = 86400
maxretry = 3
EOF

    systemctl enable fail2ban >/dev/null 2>&1
    systemctl restart fail2ban
    ok "堡垒防护已上线！全网所有胆敢连续猜错 3 次密码的野鸡扫描器将会被物理拉黑 24 小时。"
}

# === 模块 5：修改 SSH 端口与密钥登录 ===
func_ssh_secure() {
    info "正在将 SSH 默认端口 22 修改为隐蔽端口 55520 (防扫描)..."
    sed -i 's/^#\?Port .*/Port 55520/g' /etc/ssh/sshd_config
    # 兼容处理未生效情况
    if ! grep -q "^Port 55520" /etc/ssh/sshd_config; then
        echo "Port 55520" >> /etc/ssh/sshd_config
    fi
    systemctl restart sshd
    ok "SSH 端口已成功修改为 55520！请务必记住下次连接机器时指定 -p 55520"
    echo "-----------------------------------"
    info "调用你指定的开源密钥挂载体系(yuju520/Script)接入中..."
    echo -e "${RED}${BOLD}=================== 【生 死 警 告】 ===================${NC}"
    echo -e "${YELLOW}一旦你生成完密钥退出系统，你以后将永远无法再通过普通的密码方式登录机器！${NC}"
    echo -e "${YELLOW}你必须极其妥善地把私钥(Private Key)保存在你的所有电脑终端口。${NC}"
    echo -e "${RED}${BOLD}=======================================================${NC}"
    echo -e "[系统将停顿 ${GREEN}5秒${NC} 给你犹豫时间，如果不想玩高级密码锁，请猛按 ${RED}Ctrl+C${NC} 中断]"
    sleep 5
    wget -qO /tmp/key.sh https://raw.githubusercontent.com/yuju520/Script/main/key.sh && chmod +x /tmp/key.sh && bash /tmp/key.sh; rm -f /tmp/key.sh
}

# === 模块 6：大佬级网络调优与BBRx ===
func_tune_bbr() {
    info "远程劫持 jerry048/Tune 中的超级系统级底层并发参数进行调优 (-t)..."
    bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Tune/main/tune.sh) -t
    ok "队列深度、TCP重传、缓冲区优化文件全部注入！"
    echo ""
    info "正在强制推平旧版堵塞控制，将网络架构提升为最强算法 BBRx (-x)..."
    bash <(wget -qO- https://raw.githubusercontent.com/jerry048/Tune/main/tune.sh) -x
    ok "新内核替换安装完成！"
    echo -e "${YELLOW}⚠️ 此时内核虽然写入，但并没有装载成功。你必须亲自重启电脑 (Reboot) 才能生效这种手术带来的改变！${NC}"
}

# ============================================================
# 系统主菜单调度核心
# ============================================================
show_menu() {
    clear
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║        VPS 新机一键初始化专属配置中心          ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    # 使用极致强制性的双栈网络探针
    local sys_ip
    sys_ip=$(curl -s -4 --connect-timeout 3 ip.sb 2>/dev/null)
    [ -z "$sys_ip" ] && sys_ip=$(curl -s -4 --connect-timeout 3 icanhazip.com 2>/dev/null)
    [ -z "$sys_ip" ] && sys_ip=$(curl -s -4 --connect-timeout 3 api.ipify.org 2>/dev/null)
    [ -z "$sys_ip" ] && sys_ip="连接源服务器严重超时"

    local sys_os
    sys_os=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME}" || uname -sr)

    echo -e "  🪪 ${BOLD}这台机器干净明亮的 IPv4 地址${NC}:  ${CYAN}${sys_ip}${NC}"
    echo -e "  🖥️  ${BOLD}它当前承载的底层操作系统骨架${NC}:  ${CYAN}${sys_os}${NC}"
    echo ""
    line
    echo -e "  ${GREEN}0.${NC} 🚀 ${BOLD}一键无脑开启完整装机大礼包${NC} (依次挂载1-6项, 极速打造战斗机)"
    line
    echo -e "  ${YELLOW}1.${NC} 📦 为内核和源执行 Update 刷新操作"
    echo -e "  ${YELLOW}2.${NC} 🕐 单独校正本台机器的时间标尺 (Asia/Shanghai)"
    echo -e "  ${YELLOW}3.${NC} 💾 交互式部署虚拟内存池 SWAP (加多少随时定/支持删除)"
    echo -e "  ${YELLOW}4.${NC} 🛡️ 焊死防爆大门 (Fail2ban SSH封锁策略，锁定1天)"
    echo -e "  ${YELLOW}5.${NC} 🔑 修改缺省 22 端口为 55520 并替换为高级密钥锁 (yuju版)"
    echo -e "  ${YELLOW}6.${NC} ⚡ 单挑装网神功：黑科技内核调优与 BBRx 加速 (jerry048版)"
    echo -e "  ${YELLOW}q.${NC} 暂且不用，我回去了"
    line
    echo ""
}

# ============================================================
# 无限控制循环门
# ============================================================
while true; do
    show_menu
    read -p "=> 发出你的战术指令 [0-6 或 q]: " choice

    case $choice in
        0)
            echo ""
            info "即将串行自动挡启动！由于切分 SWAP 需要你预先分配大小，我们将它直接排在了首个执行！"
            echo "-----------------------------------"
            func_swap
            echo "-----------------------------------"
            func_update
            echo "-----------------------------------"
            func_timezone
            echo "-----------------------------------"
            func_fail2ban
            echo "-----------------------------------"
            func_ssh_secure
            echo "-----------------------------------"
            func_tune_bbr
            echo "-----------------------------------"
            echo -e "${GREEN}${BOLD}=======================================================${NC}"
            echo -e "${GREEN}${BOLD}     洗礼完成，一台完美、流畅、强悍的钢铁机甲已装填完毕！     ${NC}"
            echo -e "${GREEN}${BOLD}=======================================================${NC}"
            read -p "为给最后的极客版 BBRx 和密钥体系锁死打药，接下来需要近两分钟的关机重启，长按回车确认断尾..."
            echo -e "${RED}主机即将坠入黑暗并重新自启，再回头就是全新的传说！再见！${NC}"
            sleep 2
            reboot
            exit 0
            ;;
        1) echo ""; func_update; read -p "$(echo -e ${CYAN}按回车返回重装总界面！${NC})";;
        2) echo ""; func_timezone; read -p "$(echo -e ${CYAN}按回车返回重装总界面！${NC})";;
        3) echo ""; func_swap; read -p "$(echo -e ${CYAN}按回车返回重装总界面！${NC})";;
        4) echo ""; func_fail2ban; read -p "$(echo -e ${CYAN}按回车返回重装总界面！${NC})";;
        5) echo ""; func_ssh_secure; read -p "$(echo -e ${CYAN}按回车返回重装总界面！${NC})";;
        6) echo ""; func_tune_bbr; read -p "$(echo -e ${CYAN}按回车返回重装总界面！${NC})";;
        q|Q)
            echo -e "${GREEN}平安退出体系。${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}输入了未知象限的字符，请规范输入0-6!${NC}"
            sleep 1
            ;;
    esac
done
