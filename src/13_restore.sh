
restore_all() {
  local ifc; ifc="$(default_iface)"
  info "一键还原：撤销本脚本改动（DNS/MTU/IPv6/TCP/优先级/SSH/IPv6池/随机出网）"

  rm -f "$TUNE_SYSCTL_FILE" "$DMIT_TCP_DEFAULT_FILE" >/dev/null 2>&1 || true
  rm -f "$IPV6_SYSCTL_FILE" "$IPV6_FIX_SYSCTL_FILE" >/dev/null 2>&1 || true

  if [[ -f "${BACKUP_BASE}/gai.conf.orig" ]]; then
    cp -a "${BACKUP_BASE}/gai.conf.orig" "$GAI_CONF" 2>/dev/null || true
  else
    [[ -f "$GAI_CONF" ]] && sed -i -E '/^[[:space:]]*precedence[[:space:]]+::ffff:0:0\/96[[:space:]]+[0-9]+[[:space:]]*$/d' "$GAI_CONF" || true
  fi

  if is_resolved_active && have_cmd resolvectl; then
    resolvectl revert "$ifc" >/dev/null 2>&1 || true
    resolvectl flush-caches >/dev/null 2>&1 || true
  fi
  if [[ -f "$RESOLV_BACKUP" ]]; then
    cp -a "$RESOLV_BACKUP" /etc/resolv.conf 2>/dev/null 2>&1 || true
  fi

  if is_systemd; then
    systemctl disable dmit-mtu.service >/dev/null 2>&1 || true
    systemctl stop dmit-mtu.service >/dev/null 2>&1 || true
    rm -f "$MTU_SERVICE" "$MTU_VALUE_FILE" || true

    systemctl disable dmit-ipv6-pool.service >/dev/null 2>&1 || true
    systemctl stop dmit-ipv6-pool.service >/dev/null 2>&1 || true
    rm -f "$IPV6_POOL_SERVICE" || true

    systemctl disable dmit-ipv6-rand.service >/dev/null 2>&1 || true
    systemctl stop dmit-ipv6-rand.service >/dev/null 2>&1 || true
    rm -f "$IPV6_RAND_SERVICE" >/dev/null 2>&1 || true

    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  have_cmd nft && nft delete table inet dmitbox_rand6 >/dev/null 2>&1 || true
  rm -f "$IPV6_RAND_NFT" "$IPV6_RAND_CONF" "$IPV6_POOL_CONF" >/dev/null 2>&1 || true

  ip link set dev "$ifc" mtu 1500 >/dev/null 2>&1 || true

  if [[ -f "$SSH_ORIG_TGZ" ]]; then
    tar -xzf "$SSH_ORIG_TGZ" -C / 2>/dev/null || true
    rm -f "$SSH_DROPIN_FILE" 2>/dev/null || true
    sshd_restart || true
  fi

  sysctl_apply_all
  restart_network_services_best_effort
  sleep 1

  ok "已还原（建议再跑一次“网络体检”确认状态）"
}

