# ============================================================
# VPS 新机一键初始化 · 菜单系统
# 【优化】选项0执行顺序调整为：update → timezone → swap → fail2ban → ssh → bbr
# 【优化】IP探测超时缩短为2秒
# ============================================================

show_menu() {
    clear
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║        VPS 新机一键初始化专属配置中心          ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    # 【优化】缩短超时为2秒，避免串行等待9秒
    local sys_ip
    sys_ip=$(curl -s -4 --connect-timeout 2 ip.sb 2>/dev/null)
    [ -z "$sys_ip" ] && sys_ip=$(curl -s -4 --connect-timeout 2 icanhazip.com 2>/dev/null)
    [ -z "$sys_ip" ] && sys_ip=$(curl -s -4 --connect-timeout 2 api.ipify.org 2>/dev/null)
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

vps_menu_loop() {
    while true; do
        show_menu
        read -p "=> 发出你的战术指令 [0-6 或 q]: " choice
    
        case $choice in
            0)
                echo ""
                # 【优化】调整执行顺序：先 update 确保包源最新，再做其他配置
                vps_info "即将串行自动挡启动！由于切分 SWAP 需要你预先分配大小，我们将它排在更新之后！"
                echo "-----------------------------------"
                func_update
                echo "-----------------------------------"
                func_timezone
                echo "-----------------------------------"
                func_swap
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
                return 0
                ;;
            1) echo ""; func_update; read -p "$(echo -e ${CYAN}按回车返回重装总界面！${NC})";;
            2) echo ""; func_timezone; read -p "$(echo -e ${CYAN}按回车返回重装总界面！${NC})";;
            3) echo ""; func_swap; read -p "$(echo -e ${CYAN}按回车返回重装总界面！${NC})";;
            4) echo ""; func_fail2ban; read -p "$(echo -e ${CYAN}按回车返回重装总界面！${NC})";;
            5) echo ""; func_ssh_secure; read -p "$(echo -e ${CYAN}按回车返回重装总界面！${NC})";;
            6) echo ""; func_tune_bbr; read -p "$(echo -e ${CYAN}按回车返回重装总界面！${NC})";;
            q|Q)
                echo -e "${GREEN}平安退出体系。${NC}"
                return 0
                ;;
            *)
                echo -e "${RED}输入了未知象限的字符，请规范输入0-6!${NC}"
                sleep 1
                ;;
        esac
    done
}
