
# ---------------- DNS 切换/恢复 ----------------
dns_backup_once() {
  ensure_dir "$BACKUP_BASE"
  if [[ -e /etc/resolv.conf ]] && [[ ! -e "$RESOLV_BACKUP" ]]; then
    cp -a /etc/resolv.conf "$RESOLV_BACKUP" 2>/dev/null || true
    ok "已备份 resolv.conf.orig"
  fi
}

dns_apply_resolved() {
  local ifc="$1"; shift
  local dns_list=("$@")
  resolvectl dns "$ifc" "${dns_list[@]}" >/dev/null 2>&1 || true
  resolvectl flush-caches >/dev/null 2>&1 || true
}

dns_apply_resolvconf() {
  local dns_list=("$@")
  dns_backup_once
  {
    echo "# managed by ${SCRIPT_NAME}"
    for d in "${dns_list[@]}"; do echo "nameserver $d"; done
    echo "options timeout:2 attempts:2"
  } > /etc/resolv.conf
}

dns_set() {
  local which="$1"; local ifc="$2"
  local dns1 dns2
  case "$which" in
    cloudflare) dns1="1.1.1.1"; dns2="1.0.0.1" ;;
    google) dns1="8.8.8.8"; dns2="8.8.4.4" ;;
    quad9) dns1="9.9.9.9"; dns2="149.112.112.112" ;;
    *) warn "未知 DNS 方案"; return 1 ;;
  esac

  info "DNS：切换到 ${which}"
  if is_resolved_active && have_cmd resolvectl; then
    dns_apply_resolved "$ifc" "$dns1" "$dns2"
    ok "已通过 systemd-resolved 应用（$ifc）"
  else
    dns_apply_resolvconf "$dns1" "$dns2"
    ok "已写入 /etc/resolv.conf"
  fi

  if dns_resolve_ok; then ok "DNS 解析：正常"; else warn "DNS 解析：仍异常（可试另一组 DNS）"; fi
}

dns_switch_dmit_menu() {
  local ifc; ifc="$(default_iface)"
  while true; do
    echo
    echo -e "${c_bold}${c_white}DNS 切换（更换解析服务器）${c_reset}  ${c_dim}(接口: $ifc)${c_reset}"
    sub_banner
    echo "  1) Cloudflare  (1.1.1.1 / 1.0.0.1)"
    echo "  2) Google      (8.8.8.8 / 8.8.4.4)"
    echo "  3) Quad9       (9.9.9.9 / 149.112.112.112)"
    echo "  0) 返回"
    local c=""
    read_tty c "选择> " ""
    case "$c" in
      1) dns_set "cloudflare" "$ifc"; pause_up ;;
      2) dns_set "google" "$ifc"; pause_up ;;
      3) dns_set "quad9" "$ifc"; pause_up ;;
      0) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

dns_restore() {
  local ifc; ifc="$(default_iface)"
  info "DNS：恢复到脚本运行前的状态"
  if is_resolved_active && have_cmd resolvectl; then
    resolvectl revert "$ifc" >/dev/null 2>&1 || true
    resolvectl flush-caches >/dev/null 2>&1 || true
    ok "已对 $ifc 执行 resolvectl revert"
  fi

  if [[ -e "$RESOLV_BACKUP" ]]; then
    cp -a "$RESOLV_BACKUP" /etc/resolv.conf 2>/dev/null 2>&1 || true
    ok "已恢复 /etc/resolv.conf（来自备份）"
  else
    warn "未找到备份：$RESOLV_BACKUP"
  fi

  if dns_resolve_ok; then ok "DNS 解析：正常"; else warn "DNS 解析：仍异常（检查上游/防火墙）"; fi
}

mtu_current() {
  local ifc; ifc="$(default_iface)"
  ip link show "$ifc" 2>/dev/null | awk '/mtu/{for(i=1;i<=NF;i++) if($i=="mtu"){print $(i+1); exit}}' || true
}

ping_payload_ok_v4() {
  local host="$1" payload="$2"
  ping -4 -c 1 -W 1 -M do -s "$payload" "$host" >/dev/null 2>&1
}

mtu_probe_v4_value() {
  local host="1.1.1.1"
  if ! ping -4 -c 1 -W 1 "$host" >/dev/null 2>&1; then host="8.8.8.8"; fi
  if ! ping -4 -c 1 -W 1 "$host" >/dev/null 2>&1; then
    echo -e "${c_yellow}⚠ IPv4 ping 不通，无法探测 MTU（先检查网络）${c_reset}" >&2
    return 1
  fi

  echo -e "${c_cyan}➜${c_reset} MTU 探测：对 ${host} 做 DF 探测" >&2
  local lo=1200 hi=1472 mid best=0
  while [[ $lo -le $hi ]]; do
    mid=$(( (lo + hi) / 2 ))
    if ping_payload_ok_v4 "$host" "$mid"; then
      best="$mid"; lo=$((mid + 1))
    else
      hi=$((mid - 1))
    fi
  done

  if [[ "$best" -le 0 ]]; then
    echo -e "${c_yellow}⚠ 未探测到可用值${c_reset}" >&2
    return 1
  fi

  local mtu=$((best + 28))
  echo -e "${c_green}✔${c_reset} 推荐 MTU=${mtu}" >&2
  echo "$mtu"
}

mtu_apply_runtime() {
  local mtu="$1"
  local ifc; ifc="$(default_iface)"
  info "MTU：临时设置（$ifc → $mtu）"
  if ! ip link set dev "$ifc" mtu "$mtu" >/dev/null 2>&1; then
    warn "设置失败：请确认网卡名/权限/MTU 值是否合理"
    return 1
  fi
  ok "已临时生效（当前 MTU=$(mtu_current || echo N/A)）"
}

mtu_enable_persist_systemd() {
  local mtu="$1"
  local ifc; ifc="$(default_iface)"
  if ! is_systemd; then
    warn "无 systemd：无法用 service 持久化"
    return 1
  fi

  write_file "$MTU_VALUE_FILE" "IFACE=${ifc}
MTU=${mtu}
"
  write_file "$MTU_SERVICE" \
"[Unit]
Description=DMIT MTU Apply
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c '. ${MTU_VALUE_FILE} 2>/dev/null || exit 0; ip link set dev \"\$IFACE\" mtu \"\$MTU\"'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable dmit-mtu.service >/dev/null 2>&1 || true
  systemctl restart dmit-mtu.service >/dev/null 2>&1 || true
  ok "已持久化（systemd）：dmit-mtu.service"
}

mtu_disable_persist() {
  info "MTU：移除持久化设置（恢复由系统接管）"
  if is_systemd; then
    systemctl disable dmit-mtu.service >/dev/null 2>&1 || true
    systemctl stop dmit-mtu.service >/dev/null 2>&1 || true
    rm -f "$MTU_SERVICE" "$MTU_VALUE_FILE" || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    ok "已移除 dmit-mtu.service"
  else
    warn "无 systemd：无需移除 service"
  fi
  warn "运行时 MTU 不会自动回到 1500，如需可执行：ip link set dev $(default_iface) mtu 1500"
}

mtu_dmit_menu() {
  while true; do
    local cur; cur="$(mtu_current || echo "")"
    echo
    echo -e "${c_bold}${c_white}MTU 工具（探测/设置/持久化）${c_reset}  ${c_dim}(接口: $(default_iface)，当前: ${cur:-N/A})${c_reset}"
    sub_banner
    echo "  1) 自动探测 MTU（只显示推荐值）"
    echo "  2) 手动设置 MTU（临时生效）"
    echo "  3) 探测并设置 MTU（临时生效）"
    echo "  4) 探测并设置 MTU（开机自动生效）"
    echo "  5) 移除 MTU 开机自动设置"
    echo "  0) 返回"
    local c=""
    read_tty c "选择> " ""

    case "$c" in
      1)
        local mtu=""
        mtu="$(mtu_probe_v4_value || true)"
        [[ -n "${mtu:-}" ]] && ok "推荐 MTU：$mtu" || true
        pause_up
        ;;
      2)
        local mtu=""
        read_tty mtu "输入 MTU（如 1500/1480/1460/1450）> " ""
        [[ "$mtu" =~ ^[0-9]+$ ]] || { warn "输入无效"; pause_up; continue; }
        mtu_apply_runtime "$mtu" || true
        pause_up
        ;;
      3)
        local mtu=""
        mtu="$(mtu_probe_v4_value || true)"
        if [[ -n "${mtu:-}" ]]; then
          mtu_apply_runtime "$mtu" || true
        else
          warn "探测失败：未设置"
        fi
        pause_up
        ;;
      4)
        local mtu=""
        mtu="$(mtu_probe_v4_value || true)"
        if [[ -n "${mtu:-}" ]]; then
          mtu_apply_runtime "$mtu" || true
          mtu_enable_persist_systemd "$mtu" || true
        else
          warn "探测失败：未设置"
        fi
        pause_up
        ;;
      5) mtu_disable_persist || true; pause_up ;;
      0) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}

