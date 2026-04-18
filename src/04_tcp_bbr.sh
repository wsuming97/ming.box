
bbr_check() {
  echo "================ BBR 检测 ================"
  echo "kernel=$(uname -r)"
  local avail cur
  avail="$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || echo "")"
  cur="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "N/A")"
  echo "当前=${cur}"
  echo "可用=${avail:-N/A}"
  if echo " $avail " | grep -q " bbr "; then
    ok "支持 bbr（实现取决于内核）"
  else
    warn "未看到 bbr（可能内核不含/模块不可用）"
  fi
  echo "=========================================="
}

tcp_tune_apply() {
  info "TCP：通用调优（BBR + FQ + 常用参数）"
  have_cmd modprobe && modprobe tcp_bbr >/dev/null 2>&1 || true

  rm -f "$DMIT_TCP_DEFAULT_FILE" >/dev/null 2>&1 || true

  write_file "$TUNE_SYSCTL_FILE" \
"net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

net.core.netdev_max_backlog=16384
net.core.somaxconn=8192
net.ipv4.tcp_max_syn_backlog=8192

net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864

net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_syncookies=1"
  sysctl_apply_all
  ok "已应用 TCP 通用调优"
  bbr_check
}

tcp_restore_default() {
  info "TCP：恢复 Linux 默认（CUBIC + pfifo_fast）"
  rm -f "$TUNE_SYSCTL_FILE" "$DMIT_TCP_DEFAULT_FILE" >/dev/null 2>&1 || true
  sysctl -w net.core.default_qdisc=pfifo_fast >/dev/null 2>&1 || true
  sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || true
  sysctl_apply_all
  ok "已恢复 TCP 默认"
}

tcp_restore_dmit_default() {
  info "TCP：恢复 DMIT 默认 TCP"
  rm -f "$TUNE_SYSCTL_FILE" >/dev/null 2>&1 || true

  write_file "$DMIT_TCP_DEFAULT_FILE" \
"net.core.rmem_max = 67108848
net.core.wmem_max = 67108848
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_rmem = 16384 16777216 536870912
net.ipv4.tcp_wmem = 16384 16777216 536870912
net.ipv4.tcp_adv_win_scale = -2
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1
kernel.panic = -1
vm.swappiness = 0"
  sysctl_apply_all
  ok "已应用 DMIT 默认 TCP 参数"
  bbr_check
}

os_id_like() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "${ID:-unknown}|${ID_LIKE:-}"
  else
    echo "unknown|"
  fi
}

bbrv3_install_xanmod() {
  local arch; arch="$(uname -m)"
  if [[ "$arch" != "x86_64" ]]; then
    warn "BBRv3（XanMod）仅建议 x86_64 使用。当前：$arch"
    return 1
  fi

  local ids; ids="$(os_id_like)"
  if ! echo "$ids" | grep -Eqi 'debian|ubuntu|kali'; then
    warn "当前系统不像 Debian/Ubuntu/Kali：此安装方式不适用"
    return 1
  fi

  warn "将安装 XanMod 内核（包含 BBRv3），需要重启生效"
  warn "有 DKMS/驱动的机器请谨慎"

  local ans=""
  read_tty ans "确认继续请输入 YES > " ""
  if [[ "$ans" != "YES" ]]; then
    warn "已取消"
    return 0
  fi

  pkg_install wget gpg ca-certificates lsb-release apt-transport-https

  local psabi="x86-64-v3"
  local out=""
  out="$(wget -qO- https://dl.xanmod.org/check_x86-64_psabi.sh | bash 2>/dev/null || true)"
  if echo "$out" | grep -q "x86-64-v1"; then psabi="x86-64-v1"; fi
  if echo "$out" | grep -q "x86-64-v2"; then psabi="x86-64-v2"; fi
  if echo "$out" | grep -q "x86-64-v3"; then psabi="x86-64-v3"; fi
  info "CPU 指令集等级：${psabi}"

  wget -qO /tmp/xanmod.gpg https://dl.xanmod.org/gpg.key
  gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg /tmp/xanmod.gpg >/dev/null 2>&1 || true

  local codename=""
  codename="$(lsb_release -sc 2>/dev/null || true)"
  if [[ -z "$codename" && -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    codename="${VERSION_CODENAME:-}"
  fi
  [[ -z "$codename" ]] && codename="stable"

  write_file /etc/apt/sources.list.d/xanmod-release.list \
"deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org ${codename} main"

  apt-get -qq update >/dev/null 2>&1 || true

  local pkg="linux-xanmod-x64v3"
  case "$psabi" in
    x86-64-v1) pkg="linux-xanmod-x64v1" ;;
    x86-64-v2) pkg="linux-xanmod-x64v2" ;;
    x86-64-v3) pkg="linux-xanmod-x64v3" ;;
  esac

  info "安装内核包：${pkg}"
  apt-get -y install "${pkg}" >/dev/null 2>&1 || true

  ok "XanMod 内核已安装（需重启生效）"
  local rb=""
  read_tty rb "现在重启？(y/N) > " "N"

# ---------------- BBR / TCP ----------------
if [[ "$rb" == "y" || "$rb" == "Y" ]]; then
    warn "即将重启..."
    reboot || true
  else
    info "稍后手动重启：reboot"
  fi
}
