
ipv6_rand_write_conf() {
  local ifc="$1" prefix64="$2" n="$3"
  shift 3
  local addrs=("$@")

  mkdir -p "$(dirname "$IPV6_RAND_CONF")" "$(dirname "$IPV6_RAND_NFT")" >/dev/null 2>&1 || true
  {
    echo "IFACE=${ifc}"
    echo "PREFIX64=${prefix64}::/64"
    echo "N=${n}"
    local i
    for ((i=0;i<n;i++)); do
      echo "ADDR_${i}=${addrs[$i]}"
    done
  } > "$IPV6_RAND_CONF"
}

ipv6_rand_load_conf() {
  [[ -f "$IPV6_RAND_CONF" ]] || return 1
  # shellcheck disable=SC1090
  . "$IPV6_RAND_CONF"
  [[ -n "${IFACE:-}" && -n "${PREFIX64:-}" && -n "${N:-}" ]] || return 1
  return 0
}

ipv6_rand_render_nft() {
  {
    echo "table inet dmitbox_rand6 {"
    echo "  chain outmark {"
    echo "    type route hook output priority mangle; policy accept;"
    echo "    ct state new oifname \"${IFACE}\" ip6 daddr != ${PREFIX64} ip6 daddr != fe80::/10 ip6 daddr != ff00::/8 ct mark set numgen random mod ${N};"
    echo "  }"
    echo "  chain post {"
    echo "    type nat hook postrouting priority srcnat; policy accept;"
    local i
    for ((i=0;i<N;i++)); do
      local addr_var="ADDR_${i}"
      local addr_val="${!addr_var:-}"
      echo "    oifname \"${IFACE}\" ct mark ${i} ip6 daddr != ${PREFIX64} ip6 daddr != fe80::/10 ip6 daddr != ff00::/8 snat to ${addr_val};"
    done
    echo "  }"
    echo "}"
  }
}

ipv6_rand_apply_nft_runtime() {
  pkg_install nftables >/dev/null 2>&1 || true
  have_cmd nft || { warn "未找到 nft 命令，无法启用随机出网 IPv6"; return 1; }

  mkdir -p "$(dirname "$IPV6_RAND_NFT")" >/dev/null 2>&1 || true
  ipv6_rand_render_nft > "$IPV6_RAND_NFT"

  if ! nft -c -f "$IPV6_RAND_NFT" >/dev/null 2>&1; then
    warn "nft 规则语法校验失败：$IPV6_RAND_NFT"
    echo
    nl -ba "$IPV6_RAND_NFT" | sed -n '1,200p'
    echo
    warn "你也可以手动跑：nft -c -f $IPV6_RAND_NFT"
    return 1
  fi

  nft delete table inet dmitbox_rand6 >/dev/null 2>&1 || true
  if ! nft -f "$IPV6_RAND_NFT" >/dev/null 2>&1; then
    warn "nft 规则加载失败：$IPV6_RAND_NFT"
    return 1
  fi

  ok "已启用（runtime）：每个新连接随机选择出网 IPv6（N=${N}）"
  return 0
}

ipv6_rand_persist_systemd() {
  is_systemd || { warn "无 systemd：已仅 runtime 生效（重启会丢）"; return 0; }

  write_file "$IPV6_RAND_SERVICE" \
"[Unit]
Description=DMIT IPv6 Random Outbound (per-connection)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'nft delete table inet dmitbox_rand6 >/dev/null 2>&1 || true; nft -f ${IPV6_RAND_NFT} >/dev/null 2>&1 || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable dmit-ipv6-rand.service >/dev/null 2>&1 || true
  systemctl restart dmit-ipv6-rand.service >/dev/null 2>&1 || true
  ok "已持久化（systemd）：dmit-ipv6-rand.service"
}

ipv6_rand_enable_from_pool() {
  local want_n="$1"
  local ifc; ifc="$(default_iface)"
  local p64; p64="$(ipv6_prefix64_guess "$ifc" || true)"
  [[ -n "${p64:-}" ]] || { warn "未识别到 /64 前缀（prefix64）"; return 1; }

  local addrs=()
  while IFS= read -r ip; do
    [[ -n "$ip" ]] && addrs+=("$ip")
  done < <(ipv6_list_global_128 "$ifc")

  if [[ "${#addrs[@]}" -lt "$want_n" ]]; then
    warn "当前 /128 数量不足：需要 ${want_n} 个，但只有 ${#addrs[@]} 个"
    warn "请先在 IPv6 地址池里新增一些 /128，再启用随机出网"
    return 1
  fi

  local chosen=("${addrs[@]:0:$want_n}")
  ipv6_rand_write_conf "$ifc" "$p64" "$want_n" "${chosen[@]}"
  ipv6_rand_load_conf || { warn "写入配置失败"; return 1; }
  ipv6_rand_apply_nft_runtime || return 1
  ipv6_rand_persist_systemd || true

  echo -e "${c_dim}已使用以下出网 IPv6 池：${c_reset}"
  printf "%s\n" "${chosen[@]}"
  return 0
}

ipv6_rand_disable() {
  have_cmd nft && nft delete table inet dmitbox_rand6 >/dev/null 2>&1 || true

  rm -f "$IPV6_RAND_NFT" >/dev/null 2>&1 || true
  rm -f "$IPV6_RAND_CONF" >/dev/null 2>&1 || true

  if is_systemd; then
    systemctl disable dmit-ipv6-rand.service >/dev/null 2>&1 || true
    systemctl stop dmit-ipv6-rand.service >/dev/null 2>&1 || true
    rm -f "$IPV6_RAND_SERVICE" >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  ok "已关闭随机出网 IPv6（并清理持久化）"
}

ipv6_rand_selftest() {
  local n="${1:-10}"
  (( n >= 2 )) || n=10

  pkg_install curl >/dev/null 2>&1 || true

have_cmd curl || { warn "未安装 curl，无法自检"; return 1; }

  if ! curl6_ok; then
    warn "IPv6 出网异常（curl -6 失败），先修复 IPv6 再自检"
    return 1
  fi

  local url="ip.sb"
  local tmp="/tmp/dmitbox_rand6_test.$$.txt"
  : > "$tmp"

  info "自检：连续 ${n} 次 curl -6 ${url}（观察源 IPv6 是否变化）"
  local i
  for ((i=1;i<=n;i++)); do
    local ip
    ip="$(curl -6 -sS --max-time 6 "$url" 2>/dev/null | tr -d '\r' | head -n1 || true)"
    echo "$ip" >> "$tmp"
    printf "%2d) %s\n" "$i" "${ip:-FAIL}"
    sleep 0.3
  done

  echo
  local total uniq
  total="$(grep -v '^$' "$tmp" | wc -l | tr -d ' ')"
  uniq="$(grep -v '^$' "$tmp" | sort -u | wc -l | tr -d ' ')"

  echo -e "${c_bold}结果：${c_reset} 共 ${total} 次，出现 ${uniq} 个不同的源 IPv6"
  echo -e "${c_dim}去重列表：${c_reset}"
  grep -v '^$' "$tmp" | sort -u | sed -n '1,120p'

  if [[ "$uniq" -ge 2 ]]; then
    ok "随机出网看起来在变化 ✅"
  else
    warn "看起来没有变化：可能未启用随机出网 / 连接复用 / 目标站缓存（建议多测几次或换目标站）"
    echo -e "${c_dim}可替换目标：curl -6 -s https://ifconfig.co${c_reset}"
  fi

  rm -f "$tmp" >/dev/null 2>&1 || true
  return 0
}

ipv6_rand_status() {
  echo -e "${c_bold}${c_white}随机出网 IPv6 状态${c_reset}"
  if [[ -f "$IPV6_RAND_CONF" ]]; then
    echo -e "${c_dim}配置：${c_reset}${IPV6_RAND_CONF}"
    sed -n '1,120p' "$IPV6_RAND_CONF" 2>/dev/null || true
  else
    echo -e "${c_dim}未启用（配置文件不存在）${c_reset}"
  fi
  echo
  echo -e "${c_dim}nft 规则：${c_reset}"
  if have_cmd nft; then
    nft list table inet dmitbox_rand6 2>/dev/null || echo "(无)"
    echo
    echo -e "${c_dim}语法校验（nft -c）：${c_reset}"
    nft -c -f "$IPV6_RAND_NFT" >/dev/null 2>&1 && echo "OK" || echo "FAIL (查看：nl -ba $IPV6_RAND_NFT | sed -n '1,120p')"
  else
    echo "(未安装 nft)"
  fi
  echo
  echo -e "${c_dim}快速验证（多次 curl 观察 src 是否变化）：${c_reset}"
  echo "  for i in {1..6}; do curl -6 -s ip.sb; echo; done"
}

ipv6_pool_generate_and_enable_rand() {
  local n="$1"
  local ifc; ifc="$(default_iface)"
  local p64; p64="$(ipv6_prefix64_guess "$ifc" || true)"
  [[ -n "${p64:-}" ]] || { warn "未识别到 /64 前缀"; return 1; }

  info "一键：生成 ${n} 个 /128（持久）并启用随机出网"
  local made=0 tries=0
  local addrs=()
  while [[ "$made" -lt "$n" && "$tries" -lt $((n*60)) ]]; do
    tries=$((tries+1))
    local host; host="$(ipv6_rand_host_64)"
    local addr="${p64}:${host}"
    if ipv6_addr_exists "$ifc" "$addr"; then
      continue
    fi
    if ipv6_add_128 "$addr" "$ifc" "forever" "forever"; then
      addrs+=("$addr")
      made=$((made+1))
    fi
  done

  if [[ "$made" -lt "$n" ]]; then
    warn "只生成了 ${made}/${n} 个"
    return 1
  fi

  ipv6_pool_write_conf "$ifc" "$p64" "$n" "${addrs[@]}"
  ipv6_pool_persist_enable || true

  ipv6_rand_write_conf "$ifc" "$p64" "$n" "${addrs[@]}"
  ipv6_rand_load_conf || true
  ipv6_rand_apply_nft_runtime || true
  ipv6_rand_persist_systemd || true

  ok "完成：已生成 /128 池并启用随机出网"
}

ipv6_tools_dmit_menu() {
  local ifc; ifc="$(default_iface)"
  while true; do
    echo
    echo -e "${c_bold}${c_white}IPv6 /64 工具（地址池 / 随机出网）${c_reset}  ${c_dim}(接口: ${ifc})${c_reset}"
    sub_banner
    echo "  1) 查看当前 IPv6 状态（/64 与 /128）"
    echo "  2) 新增 /128（持久：forever）"
    echo "  3) 新增 /128（临时：1小时有效）"
    echo "  4) 删除一个 /128（手动输入）"
    echo "  5) 启用：出网随机 IPv6（从现有 /128 里选前 N 个）"
    echo "  6) 关闭：出网随机 IPv6"
    echo "  7) 查看：随机出网 IPv6 状态"
    echo "  8) 一键：生成 N 个 /128 + 立刻启用随机出网（推荐）"
    echo "  9) 关闭：IPv6 地址池（删除池内 /128 + 取消持久化）"
    echo "  10) 自检：随机出网是否真的在变（连续测试）"
    echo "  11) 强力修复 IPv6（DD 后无 IPv6：修 GRUB/黑名单/RA）"
    echo "  0) 返回"
    local c=""
    read_tty c "选择> " ""

    case "$c" in
      1) ipv6_pool_status; pause_up ;;
      2)
        local n=""
        read_tty n "生成多少个 /128（默认 3）> " "3"
        [[ "$n" =~ ^[0-9]+$ ]] || { warn "必须是数字"; pause_up; continue; }
        ipv6_gen_n_128 "$n" "persist" || true
        pause_up

;;
      3)
        local n=""
        read_tty n "生成多少个 /128（默认 1）> " "1"
        [[ "$n" =~ ^[0-9]+$ ]] || { warn "必须是数字"; pause_up; continue; }
        ipv6_gen_n_128 "$n" "temp" || true
        pause_up
        ;;
      4)
        local a=""
        read_tty a "输入要删除的 /128（如 2605:...:....）> " ""
        [[ -n "$a" ]] || { warn "不能为空"; pause_up; continue; }
        ipv6_del_128 "$a" "$ifc" || true
        pause_up
        ;;
      5)
        local n=""
        read_tty n "随机池大小 N（建议 3~10，默认 5）> " "5"
        [[ "$n" =~ ^[0-9]+$ ]] || { warn "N 必须是数字"; pause_up; continue; }
        (( n >= 2 )) || { warn "N 至少 2"; pause_up; continue; }
        ipv6_rand_enable_from_pool "$n" || true
        pause_up
        ;;
      6) ipv6_rand_disable || true; pause_up ;;
      7) ipv6_rand_status; pause_up ;;
      8)
        local n=""
        read_tty n "生成并随机出网：N（建议 3~10，默认 5）> " "5"
        [[ "$n" =~ ^[0-9]+$ ]] || { warn "N 必须是数字"; pause_up; continue; }
        (( n >= 2 )) || { warn "N 至少 2"; pause_up; continue; }
        ipv6_pool_generate_and_enable_rand "$n" || true
        pause_up
        ;;
      9) ipv6_pool_disable || true; pause_up ;;
      10)
        local n=""
        read_tty n "自检次数（默认 10）> " "10"
        [[ "$n" =~ ^[0-9]+$ ]] || n="10"
        ipv6_rand_selftest "$n" || true
        pause_up
        ;;
      11) ipv6_hard_repair || true; pause_up ;;
      0) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}
