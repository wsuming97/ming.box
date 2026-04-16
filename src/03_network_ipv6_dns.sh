
# ---------------- 时区：中国 ----------------
set_timezone_china() {
  info "时区：设置为中国（Asia/Shanghai）"
  pkg_install tzdata

  if have_cmd timedatectl; then
    timedatectl set-timezone Asia/Shanghai >/dev/null 2>&1 || true
  fi

  if [[ -e /usr/share/zoneinfo/Asia/Shanghai ]]; then
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime || true
    echo "Asia/Shanghai" > /etc/timezone 2>/dev/null || true
  fi

  local tz
  tz="$( (timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "unknown") )"
  ok "当前时区：$tz"
}

# ---------------- 重启网络服务 ----------------
restart_network_services_best_effort() {
  if ! is_systemd; then
    warn "无 systemd：跳过网络服务重启"
    return 0
  fi

  local restarted=0
  if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
    info "重启：systemd-networkd"
    systemctl restart systemd-networkd >/dev/null 2>&1 || true
    restarted=1
  fi
  if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    info "重启：NetworkManager"
    systemctl restart NetworkManager >/dev/null 2>&1 || true
    restarted=1
  fi
  if systemctl is-active --quiet networking 2>/dev/null; then
    info "重启：networking"
    systemctl restart networking >/dev/null 2>&1 || true
    restarted=1
  fi

  if [[ "$restarted" -eq 0 ]]; then
    info "尝试重启常见网络服务（忽略错误）"
    systemctl restart networking >/dev/null 2>&1 || true
    systemctl restart systemd-networkd >/dev/null 2>&1 || true
    systemctl restart NetworkManager >/dev/null 2>&1 || true
  fi
}

ipv6_rand_pause_keep_conf() {
  have_cmd nft && nft delete table inet dmitbox_rand6 >/dev/null 2>&1 || true
  if is_systemd; then
    systemctl stop dmit-ipv6-rand.service >/dev/null 2>&1 || true
  fi
}

ipv6_rand_resume_if_configured() {
  [[ -f "$IPV6_RAND_CONF" ]] || return 0
  [[ -f "$IPV6_RAND_NFT" ]] || return 0

  ipv6_rand_load_conf || return 0

  local i
  for ((i=0;i<N;i++)); do
    local addr_var="ADDR_${i}"
    local addr_val="${!addr_var:-}"
    [[ -n "$addr_val" ]] || continue
    if ! ipv6_addr_exists "$IFACE" "$addr_val"; then
      ip -6 addr add "${addr_val}/128" dev "$IFACE" >/dev/null 2>&1 || true
    fi
  done

  ipv6_rand_apply_nft_runtime || { warn "随机出网恢复失败（nft 未加载）"; return 0; }

  if is_systemd && [[ -f "$IPV6_RAND_SERVICE" ]]; then
    systemctl restart dmit-ipv6-rand.service >/dev/null 2>&1 || true
  fi

  ok "已自动恢复：随机出网 IPv6（之前启用过）"
}

ipv6_disable() {
  info "IPv6：关闭（系统级禁用）"
  ipv6_rand_pause_keep_conf || true

  rm -f "$IPV6_FIX_SYSCTL_FILE" || true

  write_file "$IPV6_SYSCTL_FILE" \
"net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1"
  sysctl_apply_all
  ok "IPv6 已关闭（sysctl: $(ipv6_status)）"
}

_ipv6_enable_runtime_all_ifaces() {
  for f in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
    [[ -e "$f" ]] || continue
    echo 0 > "$f" 2>/dev/null || true
  done
}

_ipv6_find_disable_sources() {
  echo -e "${c_yellow}${c_bold}--- IPv6 开启失败排查 ---${c_reset}"
  echo -e "${c_dim}[启动参数]${c_reset} $(cat /proc/cmdline 2>/dev/null || true)"
  if grep -qw "ipv6.disable=1" /proc/cmdline 2>/dev/null; then
    warn "发现 ipv6.disable=1：必须改 GRUB/引导并重启"
  fi
  echo
  echo -e "${c_dim}[sysctl 覆盖]${c_reset}"
  (grep -RIn --line-number -E 'net\.ipv6\.conf\.(all|default|lo)\.disable_ipv6[[:space:]]*=[[:space:]]*1' \
    /etc/sysctl.conf /etc/sysctl.d 2>/dev/null || true) | sed -n '1,140p'
  echo
  echo -e "${c_dim}[模块黑名单]${c_reset}"
  (grep -RIn --line-number -E '^[[:space:]]*blacklist[[:space:]]+ipv6|^[[:space:]]*install[[:space:]]+ipv6[[:space:]]+/bin/true' \
    /etc/modprobe.d 2>/dev/null || true) | sed -n '1,140p'
  echo -e "${c_yellow}${c_bold}------------------------${c_reset}"
}


_ipv6_ra_status() {
  local ar da aa da2
  ar="$(sysctl -n net.ipv6.conf.all.accept_ra 2>/dev/null || echo "N/A")"
  da="$(sysctl -n net.ipv6.conf.default.accept_ra 2>/dev/null || echo "N/A")"
  aa="$(sysctl -n net.ipv6.conf.all.autoconf 2>/dev/null || echo "N/A")"
  da2="$(sysctl -n net.ipv6.conf.default.autoconf 2>/dev/null || echo "N/A")"
  echo "accept_ra: all=${ar} default=${da} | autoconf: all=${aa} default=${da2}"
}

_grub_rebuild_best_effort() {
  if have_cmd update-grub; then
    update-grub >/dev/null 2>&1 || true
    return 0
  fi
  if have_cmd grub2-mkconfig; then
    if [[ -f /boot/grub2/grub.cfg ]]; then
      grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 || true
    elif [[ -f /boot/grub/grub.cfg ]]; then
      grub2-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || true
    else
      grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 || true
    fi
    return 0
  fi
  return 0
}

_ipv6_remove_cmdline_disable_from_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  # remove token ipv6.disable=1 (keep file readable)
  sed -i 's/\<ipv6\.disable=1\>//g; s/[[:space:]]\{2,\}/ /g; s/" \+/"/g' "$f" 2>/dev/null || true
}

ipv6_hard_repair() {
  info "IPv6：强力修复（DD 后常见：修 GRUB/黑名单/RA/SLAAC）"

  ensure_dir "$BACKUP_BASE"
  local bdir="${BACKUP_BASE}/ipv6-hardfix-$(ts_now)"
  ensure_dir "$bdir"
  cp -a /etc/default/grub "$bdir/" 2>/dev/null || true
  cp -a /etc/default/grub.d "$bdir/" 2>/dev/null || true
  cp -a /etc/modprobe.d "$bdir/" 2>/dev/null || true
  cp -a /etc/sysctl.conf "$bdir/" 2>/dev/null || true
  cp -a /etc/sysctl.d "$bdir/" 2>/dev/null || true
  ok "已备份关键配置 → ${bdir}"

  local need_reboot=0

  # 1) cmdline disable
  if grep -qw "ipv6.disable=1" /proc/cmdline 2>/dev/null; then
    warn "检测到启动参数 ipv6.disable=1：将尝试从 GRUB 配置中移除（需重启生效）"
    _ipv6_remove_cmdline_disable_from_file /etc/default/grub
    shopt -s nullglob
    for f in /etc/default/grub.d/*.cfg; do
      _ipv6_remove_cmdline_disable_from_file "$f"
    done
    shopt -u nullglob
    _grub_rebuild_best_effort
    need_reboot=1
  fi

  # 2) modprobe blacklist
  shopt -s nullglob
  for f in /etc/modprobe.d/*.conf; do
    [[ -f "$f" ]] || continue
    if grep -Eq '^[[:space:]]*(blacklist[[:space:]]+ipv6|install[[:space:]]+ipv6[[:space:]]+/bin/true)' "$f" 2>/dev/null; then
      warn "发现 ipv6 模块黑名单：$f（将注释相关行）"
      sed -i -E 's/^[[:space:]]*(blacklist[[:space:]]+ipv6)/# ipv6fix: \1/g; s/^[[:space:]]*(install[[:space:]]+ipv6[[:space:]]+\/bin\/true)/# ipv6fix: \1/g' "$f" 2>/dev/null || true
    fi
  done
  shopt -u nullglob

  # 3) sysctl fix (persist)
  write_file "$IPV6_FIX_SYSCTL_FILE" "# managed by ${SCRIPT_NAME} (ipv6 hardfix)
net.ipv6.conf.all.disable_ipv6=0
net.ipv6.conf.default.disable_ipv6=0
net.ipv6.conf.lo.disable_ipv6=0

net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.default.accept_ra=2
net.ipv6.conf.all.autoconf=1
net.ipv6.conf.default.autoconf=1"

  # runtime apply
  if have_cmd modprobe; then modprobe ipv6 >/dev/null 2>&1 || true; fi
  sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.all.accept_ra=2 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.accept_ra=2 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.all.autoconf=1 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.autoconf=1 >/dev/null 2>&1 || true
  _ipv6_enable_runtime_all_ifaces
  sysctl_apply_all

  restart_network_services_best_effort
  sleep 2

  # then run normal enable flow (includes pool apply + status)
  ipv6_enable || true

  if [[ "$need_reboot" -eq 1 ]]; then
    warn "已修改 GRUB 去除 ipv6.disable=1：必须重启后 IPv6 才可能恢复"
  fi
}

ipv6_enable() {
  info "IPv6：开启（自动重拉地址/默认路由）"

  rm -f "$IPV6_SYSCTL_FILE" || true

  # persist: DD 后常见需要开启 RA/SLAAC（不然没默认路由/没自动地址）
  write_file "$IPV6_FIX_SYSCTL_FILE" "# managed by ${SCRIPT_NAME} (ipv6 fix)
net.ipv6.conf.all.disable_ipv6=0
net.ipv6.conf.default.disable_ipv6=0
net.ipv6.conf.lo.disable_ipv6=0
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.default.accept_ra=2
net.ipv6.conf.all.autoconf=1
net.ipv6.conf.default.autoconf=1"

  if have_cmd modprobe; then
    modprobe ipv6 >/dev/null 2>&1 || true
  fi

  sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.all.accept_ra=2 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.accept_ra=2 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.all.autoconf=1 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.autoconf=1 >/dev/null 2>&1 || true
  _ipv6_enable_runtime_all_ifaces
  sysctl_apply_all

  restart_network_services_best_effort
  sleep 2
  _ipv6_enable_runtime_all_ifaces

  ipv6_pool_apply_from_conf >/dev/null 2>&1 || true

  local st; st="$(ipv6_status)"

  echo -e "${c_dim}--- IPv6 状态快照 ---${c_reset}"
  echo -e "${c_dim}sysctl:${c_reset} $st"
  echo -e "${c_dim}RA/SLAAC:${c_reset} $(_ipv6_ra_status)"
  echo -e "${c_dim}地址:${c_reset}"
  ip -6 addr show 2>/dev/null || true
  echo -e "${c_dim}路由:${c_reset}"
  ip -6 route show 2>/dev/null || true
  echo -e "${c_dim}---------------------${c_reset}"

  if echo "$st" | grep -q "all=0" && echo "$st" | grep -q "default=0" \
     && has_ipv6_global_addr && has_ipv6_default_route; then
    ok "IPv6 已可用（有公网 IPv6 + 默认路由）"
    ipv6_rand_resume_if_configured || true
  else
    warn "IPv6 未完整（缺公网 IPv6 或默认路由）"
    warn "如果 DMIT 面板未分配 IPv6，本机不会凭空生成公网 IPv6"
    _ipv6_find_disable_sources
  fi
}

gai_backup_once() {
  ensure_dir "$BACKUP_BASE"
  if [[ -f "$GAI_CONF" ]] && [[ ! -f "${BACKUP_BASE}/gai.conf.orig" ]]; then
    cp -a "$GAI_CONF" "${BACKUP_BASE}/gai.conf.orig" || true
    ok "已备份 gai.conf.orig"
  fi
}

prefer_ipv4() {
  info "网络：优先 IPv4（系统解析优先级）"
  local kind; kind="$(libc_kind)"
  if [[ "$kind" != "glibc" ]]; then
    warn "非 glibc：此方式无效（Alpine/musl 常见），可用：关闭 IPv6 或应用层 -4"
    return 0
  fi
  gai_backup_once
  touch "$GAI_CONF"
  sed -i -E '/^[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+[0-9]+[[:space:]]*$/d' "$GAI_CONF"
  printf "\n# %s managed: prefer IPv4\nprecedence ::ffff:0:0/96  100\n" "$SCRIPT_NAME" >> "$GAI_CONF"
  ok "已设置：IPv4 优先"
}

prefer_ipv6() {
  info "网络：优先 IPv6（恢复默认倾向）"
  local kind; kind="$(libc_kind)"
  if [[ "$kind" != "glibc" ]]; then
    warn "非 glibc：此方式无效；要更强制 IPv6：确保 IPv6 可用，并应用层 -6"
    return 0
  fi
  gai_backup_once
  touch "$GAI_CONF"
  sed -i -E '/^[[:space:]]*#[[:space:]]*'"${SCRIPT_NAME}"'[[:space:]]*managed: prefer IPv4[[:space:]]*$/d' "$GAI_CONF" || true
  sed -i -E '/^[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+[0-9]+[[:space:]]*$/d' "$GAI_CONF" || true
  ok "已恢复：IPv6 倾向（默认）"
}

restore_gai_default() {
  info "网络：恢复 gai.conf（回到备份状态）"
  if [[ -f "${BACKUP_BASE}/gai.conf.orig" ]]; then
    cp -a "${BACKUP_BASE}/gai.conf.orig" "$GAI_CONF" || true
    ok "已恢复 gai.conf.orig"
  else
    warn "未找到 gai.conf.orig：改为移除脚本写入规则"
    prefer_ipv6 || true
  fi
}
