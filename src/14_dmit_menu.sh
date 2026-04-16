
dmit_menu() {
  RUN_MODE="menu"
  while true; do
    banner

    echo -e "${c_bold}${c_white}【网络】${c_reset}"
    echo -e "  ${c_cyan}1${c_reset}) 网络体检（只看状态）"
    echo -e "  ${c_cyan}2${c_reset}) 体检 + 自动修复（重拉IPv6/刷新DNS）"
    echo -e "  ${c_cyan}3${c_reset}) 开启 IPv6（重拉地址/路由）"
    echo -e "  ${c_cyan}4${c_reset}) 关闭 IPv6（系统级禁用）"
    echo -e "  ${c_cyan}5${c_reset}) DNS 切换（CF/Google/Quad9）"
    echo -e "  ${c_cyan}6${c_reset}) DNS 恢复（回到备份）"
    echo -e "  ${c_cyan}7${c_reset}) MTU 工具（探测/设置/持久化）"
    echo -e "  ${c_cyan}8${c_reset}) IPv4 优先（解析优先）"
    echo -e "  ${c_cyan}9${c_reset}) IPv6 优先（恢复默认）"
    echo -e "  ${c_cyan}10${c_reset}) 恢复 IPv4/IPv6 优先级（用备份还原）"
    echo -e "  ${c_cyan}11${c_reset}) IPv6 /64 工具（地址池 / 随机出网）"

    echo
    echo -e "${c_bold}${c_white}【TCP/BBR】${c_reset}"
    echo -e "  ${c_cyan}12${c_reset}) TCP 通用调优（BBR+FQ）"
    echo -e "  ${c_cyan}13${c_reset}) 恢复 Linux 默认 TCP（CUBIC）"
    echo -e "  ${c_cyan}14${c_reset}) 恢复 DMIT 默认 TCP"
    echo -e "  ${c_cyan}15${c_reset}) BBR 支持性检测"
    echo -e "  ${c_cyan}16${c_reset}) 安装 BBRv3（XanMod 内核，需要重启）"

    echo
    echo -e "${c_bold}${c_white}【系统/安全】${c_reset}"
    echo -e "  ${c_cyan}17${c_reset}) 设置时区为中国（Asia/Shanghai）"
    echo -e "  ${c_cyan}18${c_reset}) SSH 安全工具（密码/密钥/换端口）"
    echo -e "  ${c_cyan}19${c_reset}) 一键 DD 重装系统（高风险）"

    echo
    echo -e "${c_bold}${c_white}【测试】${c_reset}"
    echo -e "  ${c_cyan}20${c_reset}) 一键测试脚本（GB5/Bench/回程/IP质量/解锁）"

    echo
    echo -e "${c_bold}${c_white}【工具】${c_reset}"
    echo -e "  ${c_cyan}21${c_reset}) 一键还原（撤销本脚本改动）"
    echo -e "  ${c_cyan}22${c_reset}) 保存环境快照（发工单用）"
    echo -e "  ${c_cyan}23${c_reset}) 换IP防失联（cloud-init/QGA 工具）"

    echo
    echo -e "  ${c_cyan}0${c_reset}) 退出"
    echo -e "${c_dim}----------------------------------------------${c_reset}"

    local choice=""
    read_tty choice "选择> " ""

    case "$choice" in
      1) health_check_only; pause_main ;;
      2) health_check_autofix; pause_main ;;
      3) ipv6_enable; pause_main ;;
      4) ipv6_disable; pause_main ;;
      5) dns_switch_menu ;;
      6) dns_restore; pause_main ;;
      7) mtu_menu ;;
      8) prefer_ipv4; pause_main ;;
      9) prefer_ipv6; pause_main ;;
      10) restore_gai_default; pause_main ;;
      11) ipv6_tools_menu ;;
      12) tcp_tune_apply; pause_main ;;
      13) tcp_restore_default; pause_main ;;
      14) tcp_restore_dmit_default; pause_main ;;
      15) bbr_check; pause_main ;;
      16) bbrv3_install_xanmod; pause_main ;;
      17) set_timezone_china; pause_main ;;
      18) ssh_menu ;;
      19) dd_reinstall; pause_main ;;
      20) tests_menu ;;
      21) restore_all; pause_main ;;
      22) env_snapshot; pause_main ;;
      23) cloudinit_qga_menu ;;
      0) return 0 ;;
      *) warn "无效选项"; pause_main ;;
    esac
  done
}

dmit_main() {
  need_root
  menu
}
