
dd_reinstall() {
  warn "一键 DD 重装系统：会清空系统盘数据，风险极高！"
  warn "建议先准备好：VNC/救援模式/面板控制台"
  warn "开始后 SSH 可能中断，请勿慌"

  if ! has_tty; then
    warn "当前无可交互 TTY（可能是 curl|bash 场景），为安全起见：已取消"
    return 0
  fi

  local c="" flag="" ver="" port="" mode="" pwd=""
  echo
  echo -e "${c_bold}${c_white}DD 重装系统（InstallNET.sh）${c_reset}"
  sub_banner
  echo "  1) Debian 11"
  echo "  2) Debian 12"
  echo "  3) Debian 13"
  echo "  4) Ubuntu 22.04"
  echo "  5) Ubuntu 24.04"
  echo "  6) CentOS 7"
  echo "  7) CentOS 8"
  echo "  8) RockyLinux 9"
  echo "  9) AlmaLinux 9"
  echo "  10) Alpine edge"
  echo "  0) 返回"
  read_tty c "选择> " ""
  case "$c" in
    1)  flag="-debian";     ver="11" ;;
    2)  flag="-debian";     ver="12" ;;
    3)  flag="-debian";     ver="13" ;;
    4)  flag="-ubuntu";     ver="22.04" ;;
    5)  flag="-ubuntu";     ver="24.04" ;;
    6)  flag="-centos";     ver="7" ;;
    7)  flag="-centos";     ver="8" ;;
    8)  flag="-rockylinux"; ver="9" ;;
    9)  flag="-almalinux";  ver="9" ;;
    10) flag="-alpine";     ver="edge" ;;
    0) return 0 ;;
    *) warn "无效选项"; return 0 ;;
  esac

  local cur_port
  cur_port="$(ssh_current_ports | awk '{print $1}' || true)"
  cur_port="${cur_port:-22}"
  read_tty port "SSH 端口（默认 ${cur_port}）> " "$cur_port"
  [[ "$port" =~ ^[0-9]+$ ]] || { warn "端口必须是数字"; return 0; }

  echo
  echo "  1) 随机密码"
  echo "  2) 自定义密码"
  read_tty mode "选择> " "1"
  if [[ "$mode" == "1" ]]; then
    pwd="K$(ssh_random_pass)"
  elif [[ "$mode" == "2" ]]; then
    read_tty_secret pwd "设置密码（输入不回显）> "
    [[ -n "${pwd:-}" ]] || { warn "密码不能为空"; return 0; }
  else
    warn "无效选项"
    return 0
  fi

  echo
  echo -e "${c_bold}${c_white}即将执行（确认信息）${c_reset}"
  echo -e "系统：${flag} ${ver}"
  echo -e "SSH端口：${port}"
  echo -e "root密码：${c_green}${pwd}${c_reset}"
  echo -e "${c_yellow}⚠ 数据将被清空！${c_reset}"
  echo
  local ans=""
  read_tty ans "确认继续请输入 DD > " ""
  if [[ "$ans" != "DD" ]]; then
    warn "已取消"
    return 0
  fi

  if have_cmd apt-get; then
    apt-get -y update >/dev/null 2>&1 || true
    apt-get -y install wget >/dev/null 2>&1 || true
  elif have_cmd yum; then
    yum -y install wget >/dev/null 2>&1 || true
  elif have_cmd dnf; then
    dnf -y install wget >/dev/null 2>&1 || true
  elif have_cmd apk; then
    apk update >/dev/null 2>&1 || true
    apk add bash wget >/dev/null 2>&1 || true
    sed -i 's/root:\/bin\/ash/root:\/bin\/bash/g' /etc/passwd 2>/dev/null || true
  fi

  info "下载 InstallNET.sh..."
  wget --no-check-certificate -qO /tmp/InstallNET.sh 'https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh'
  chmod a+x /tmp/InstallNET.sh

  warn "开始执行重装脚本（可能会进入安装流程/重启）"
  bash /tmp/InstallNET.sh "${flag}" "${ver}" -port "${port}" -pwd "${pwd}" || true
}
