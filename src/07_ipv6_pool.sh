
ipv6_prefix64_guess() {
  local ifc="${1:-$(default_iface)}"
  local a=""
  a="$(ip -6 addr show dev "$ifc" scope global 2>/dev/null | awk '/inet6/{print $2}' | grep -E '/64$' | head -n1 || true)"
  if [[ -n "$a" ]]; then
    a="${a%/64}"
    echo "$a" | awk -F: '{print $1 ":" $2 ":" $3 ":" $4}'
    return 0
  fi
  a="$(ip -6 route show 2>/dev/null | awk -v i="$ifc" '$1 ~ /\/64$/ && $0 ~ ("dev " i) {print $1; exit}' || true)"
  if [[ -n "$a" ]]; then
    a="${a%::/64}"
    echo "$a"
    return 0
  fi
  return 1
}

ipv6_list_global_128() {
  local ifc="${1:-$(default_iface)}"
  ip -6 addr show dev "$ifc" scope global 2>/dev/null \
    | awk '/inet6/{print $2}' \
    | grep -E '/128$' \
    | sed 's#/128##g'
}

ipv6_addr_exists() {
  local ifc="${1:-$(default_iface)}" addr="$2"
  ip -6 addr show dev "$ifc" 2>/dev/null | grep -q "inet6 ${addr}/128"
}

ipv6_rand_host_64() {
  if have_cmd hexdump; then
    hexdump -n8 -e '4/2 "%04x " 1' /dev/urandom 2>/dev/null | awk '{print $1 ":" $2 ":" $3 ":" $4}'
    return 0
  fi
  printf "%04x:%04x:%04x:%04x" $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536))
}

ipv6_add_128() {
  local addr="$1" ifc="${2:-$(default_iface)}"
  local valid="${3:-forever}" pref="${4:-forever}"
  if [[ "$valid" == "forever" ]]; then
    ip -6 addr add "${addr}/128" dev "$ifc" >/dev/null 2>&1 || return 1
  else
    ip -6 addr add "${addr}/128" dev "$ifc" valid_lft "$valid" preferred_lft "$pref" >/dev/null 2>&1 || return 1
  fi
  ok "已添加：${addr}/128  (dev ${ifc})"
  return 0
}

ipv6_del_128() {
  local addr="$1" ifc="${2:-$(default_iface)}"
  ip -6 addr del "${addr}/128" dev "$ifc" >/dev/null 2>&1 || true
  ok "已删除：${addr}/128"
}

ipv6_gen_n_128() {
  local n="$1" mode="${2:-persist}"
  local ifc; ifc="$(default_iface)"
  local p64; p64="$(ipv6_prefix64_guess "$ifc" || true)"
  [[ -n "${p64:-}" ]] || { warn "未识别到 /64 前缀（请确认有 /64 地址或 ::/64 路由）"; return 1; }

  local valid="forever" pref="forever"
  if [[ "$mode" == "temp" ]]; then
    valid="3600"
    pref="1200"
  fi

  local made=0 tries=0
  while [[ "$made" -lt "$n" && "$tries" -lt $((n*50)) ]]; do
    tries=$((tries+1))
    local host; host="$(ipv6_rand_host_64)"
    local addr="${p64}:${host}"
    if ipv6_addr_exists "$ifc" "$addr"; then
      continue
    fi
    if ipv6_add_128 "$addr" "$ifc" "$valid" "$pref"; then
      made=$((made+1))
    fi
  done

  if [[ "$made" -lt "$n" ]]; then
    warn "只生成了 ${made}/${n} 个（可能系统限制或重复过多）"
    return 1
  fi
  ok "完成：生成 ${made} 个 /128（${mode}）"
}

ipv6_pool_write_conf() {
  local ifc="$1" prefix64="$2" n="$3"; shift 3
  local addrs=("$@")
  {
    echo "IFACE=${ifc}"
    echo "PREFIX64=${prefix64}"
    echo "N=${n}"
    local i
    for ((i=0;i<n;i++)); do
      echo "ADDR_${i}=${addrs[$i]}"
    done
  } > "$IPV6_POOL_CONF"
}

ipv6_pool_load_conf() {
  [[ -f "$IPV6_POOL_CONF" ]] || return 1
  # shellcheck disable=SC1090
  . "$IPV6_POOL_CONF"
  [[ -n "${IFACE:-}" && -n "${PREFIX64:-}" && -n "${N:-}" ]] || return 1
  return 0
}

ipv6_pool_apply_from_conf() {
  ipv6_pool_load_conf || return 1
  local i
  for ((i=0;i<N;i++)); do
    local v="ADDR_${i}"
    local addr="${!v:-}"
    [[ -n "$addr" ]] || continue
    if ! ipv6_addr_exists "$IFACE" "$addr"; then
      ip -6 addr add "${addr}/128" dev "$IFACE" >/dev/null 2>&1 || true
    fi
  done
  ok "已应用地址池（确保 /128 都挂在 ${IFACE}）"
}

ipv6_pool_persist_enable() {
  if ! is_systemd; then
    warn "无 systemd：已仅运行时生效；如需开机自启，请自行写入网络启动脚本"
    return 0
  fi
  write_file "$IPV6_POOL_SERVICE" \
"[Unit]
Description=DMIT IPv6 Pool Apply
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c '. ${IPV6_POOL_CONF} 2>/dev/null || exit 0; for i in \$(seq 0 \$((N-1))); do eval a=\\\"\\\${ADDR_\$i}\\\"; [ -n \"\$a\" ] || continue; ip -6 addr add \"\$a/128\" dev \"\$IFACE\" >/dev/null 2>&1 || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable dmit-ipv6-pool.service >/dev/null 2>&1 || true
  systemctl restart dmit-ipv6-pool.service >/dev/null 2>&1 || true
  ok "已持久化：dmit-ipv6-pool.service"
}

ipv6_pool_disable() {
  if ipv6_pool_load_conf; then
    local i
    for ((i=0;i<N;i++)); do
      local v="ADDR_${i}"
      local addr="${!v:-}"

[[ -n "$addr" ]] || continue
      ip -6 addr del "${addr}/128" dev "$IFACE" >/dev/null 2>&1 || true
    done
  fi

  rm -f "$IPV6_POOL_CONF" >/dev/null 2>&1 || true

  if is_systemd; then
    systemctl disable dmit-ipv6-pool.service >/dev/null 2>&1 || true
    systemctl stop dmit-ipv6-pool.service >/dev/null 2>&1 || true
    rm -f "$IPV6_POOL_SERVICE" >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi
  ok "已关闭 IPv6 地址池（并清理持久化）"
}

ipv6_pool_status() {
  echo -e "${c_bold}${c_white}IPv6 地址池状态${c_reset}"
  local ifc; ifc="$(default_iface)"
  local p64; p64="$(ipv6_prefix64_guess "$ifc" || true)"
  echo -e "${c_dim}IFACE:${c_reset} ${ifc}"
  echo -e "${c_dim}PREFIX64:${c_reset} ${p64:-unknown}"
  echo
  echo -e "${c_dim}当前网卡 /64 与 /128：${c_reset}"
  ip -6 addr show dev "$ifc" scope global 2>/dev/null | sed -n '1,200p' || true
  echo
  echo -e "${c_dim}当前 /128 列表：${c_reset}"
  ipv6_list_global_128 "$ifc" || true
  echo
  if [[ -f "$IPV6_POOL_CONF" ]]; then
    echo -e "${c_dim}池配置：${c_reset} ${IPV6_POOL_CONF}"
    sed -n '1,120p' "$IPV6_POOL_CONF" 2>/dev/null || true
  else
    echo -e "${c_dim}池配置：${c_reset} (未启用)"
  fi
}
