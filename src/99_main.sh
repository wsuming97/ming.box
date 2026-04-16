# ============================================================
# 终极世界树主菜单 (Super Main Menu)
# ============================================================

# DMIT 菜单内部使用的短名称别名
# 原始代码中 dmit_menu 引用了这些短名，但函数定义用了 *_dmit_menu 全名
# 这里统一建立别名，确保菜单正常工作
pause_main()          { pause_dmit_main; }
dns_switch_menu()     { dns_switch_dmit_menu; }
mtu_menu()            { mtu_dmit_menu; }
ipv6_tools_menu()     { ipv6_tools_dmit_menu; }
ssh_menu()            { ssh_dmit_menu; }
tests_menu()          { tests_dmit_menu; }
cloudinit_qga_menu()  { cloudinit_qga_dmit_menu; }
menu()                { dmit_menu; }
_need_root()          { need_root; }

super_main_menu() {
    clear
    echo ""
    echo -e "\033[0;32m\033[1m╔══════════════════════════════════════════════╗\033[0m"
    echo -e "\033[0;32m\033[1m║      ✨ 终极全栖开荒与深度调优系统 ✨      ║\033[0m"
    echo -e "\033[0;32m\033[1m╚══════════════════════════════════════════════╝\033[0m"
    echo ""
    
    echo -e "  \033[1;33m1.\033[0m 🚀 【新机防御与优化阵列】(极简部署·安全配置·底层升级)"
    echo -e "  \033[1;33m2.\033[0m 🛠️ 【极客实验与深水专区】(DMIT防封网·强制路由·原生内核池)"
    echo -e "  \033[1;33m0.\033[0m 🚪 撤除引信退出"
    echo ""
}

while true; do
    super_main_menu
    read -p "=> 请从主节点跃迁 [0-2]: " super_choice
    case $super_choice in
        1) vps_menu_loop ;;
        2) dmit_menu ;;
        0) echo -e "\n\033[0;32m已平安降落终端。\033[0m"; exit 0 ;;
        *) echo -e "\n\033[0;31m跳跃失败，请输入范围内的合法指令。\033[0m"; sleep 1 ;;
    esac
done
