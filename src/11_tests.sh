
run_remote_script() {
  local title="$1"
  local cmd="$2"
  local note="${3:-}"

  echo
  echo -e "${c_bold}${c_white}${title}${c_reset}"
  [[ -n "$note" ]] && echo -e "${c_yellow}${note}${c_reset}"
  echo -e "${c_dim}将执行：${cmd}${c_reset}"
  warn "注意：这会从网络拉取并运行脚本（请自行确认来源可信）"

  if ! has_tty; then
    warn "当前无可交互 TTY（可能是 curl|bash 场景 / 无 -t 终端），为安全起见：已取消执行"
    return 0
  fi
  read_tty _ "回车执行（Ctrl+C 取消）..." ""

  if echo "$cmd" | grep -q "curl"; then pkg_install curl; fi
  if echo "$cmd" | grep -q "wget"; then pkg_install wget; fi
  pkg_install bash

  bash -lc "$cmd" </dev/tty || true
}

tests_dmit_menu() {
  while true; do
    echo
    echo -e "${c_bold}${c_white}一键测试脚本${c_reset}"
    sub_banner
    echo "  1) GB5 性能测试（Geekbench 5）"
    echo "  2) Bench 综合测试（bench.sh）"
    echo "  3) 三网回程测试（仅参考）"
    echo "  4) IP 质量检测（IP.Check.Place）"
    echo "  5) NodeQuality 测试"
    echo "  6) Telegram 延迟测试"
    echo "  7) 流媒体解锁检测（check.unlock.media）"
    echo "  0) 返回"
    local c=""
    read_tty c "选择> " ""
    case "$c" in
      1) run_remote_script "GB5 性能测试"  "bash <(wget -qO- https://raw.githubusercontent.com/i-abc/GB5/main/gb5-test.sh)"; pause_up ;;
      2) run_remote_script "Bench 综合测试" "bash <(curl -fsSL https://bench.sh)"; pause_up ;;
      3) run_remote_script "三网回程测试" "bash <(curl -fsSL https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh)" "备注：仅参考"; pause_up ;;
      4) run_remote_script "IP 质量检测" "bash <(curl -sL IP.Check.Place)"; pause_up ;;
      5) run_remote_script "NodeQuality 测试" "bash <(curl -sL https://run.NodeQuality.com)"; pause_up ;;
      6) run_remote_script "Telegram 延迟测试" "bash <(curl -fsSL https://sub.777337.xyz/tgdc.sh)"; pause_up ;;
      7) run_remote_script "流媒体解锁检测" "bash <(curl -L -s check.unlock.media)"; pause_up ;;
      0) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}
