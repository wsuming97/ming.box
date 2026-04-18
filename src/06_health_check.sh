print_kv() { printf "%-20s %s\n" "$1" "$2"; }

health_check_core() {
  local ifc; ifc="$(default_iface)"
  local ipv6_sysctl; ipv6_sysctl="$(ipv6_status)"
  local v6_addr="NO" v6_route="NO" v4_net="NO" v6_net="NO" dns_ok="NO"

  has_ipv6_global_addr && v6_addr="YES"
  has_ipv6_default_route && v6_route="YES"
  curl4_ok && v4_net="YES"
  curl6_ok && v6_net="YES"
  dns_resolve_ok && dns_ok="YES"

  echo -e "${c_bold}${c_white}网络体检${c_reset}  ${c_dim}(接口: $ifc)${c_reset}"
  echo -e "${c_dim}----------------------------------------------${c_reset}"

  print_kv "IPv4 出网"       "$( [[ "$v4_net" == "YES" ]] && echo -e "${c_green}正常${c_reset}" || echo -e "${c_yellow}异常${c_reset}" )"
  print_kv "DNS 解析"        "$( [[ "$dns_ok" == "YES" ]] && echo -e "${c_green}正常${c_reset}" || echo -e "${c_yellow}异常${c_reset}" )"
  print_kv "IPv6 sysctl 开关" "$ipv6_sysctl"
  print_kv "IPv6 公网地址"   "$( [[ "$v6_addr" == "YES" ]] && echo -e "${c_green}有${c_reset}" || echo -e "${c_yellow}无${c_reset}" )"
  print_kv "IPv6 默认路由"   "$( [[ "$v6_route" == "YES" ]] && echo -e "${c_green}有${c_reset}" || echo -e "${c_yellow}无${c_reset}" )"
  print_kv "IPv6 出网"       "$( [[ "$v6_net" == "YES" ]] && echo -e "${c_green}正常${c_reset}" || echo -e "${c_yellow}异常${c_reset}" )"
  print_kv "当前 MTU"        "$(mtu_current || echo N/A)"
  echo -e "${c_dim}----------------------------------------------${c_reset}"

  if [[ "$dns_ok" != "YES" && "$v4_net" == "YES" ]]; then
    warn "像 DNS 问题：试试【DNS 切换】"
  fi
  if [[ "$v6_addr" == "NO" || "$v6_route" == "NO" ]]; then
    warn "IPv6 缺地址/路由：试试【体检+自动修复】或【开启 IPv6】"
  fi
}

health_check_only() {
  health_check_core
  ok "体检完成（未改动任何配置）"
}

health_check_autofix() {
  local fixed=0
  health_check_core
  echo
  info "自动修复：尝试重拉 IPv6 / 刷新 DNS（不做高风险改动）"

  if ! has_ipv6_global_addr || ! has_ipv6_default_route; then
    info "IPv6 不完整：执行“开启 IPv6（重拉地址/路由）”"
    ipv6_enable || true
    fixed=1
  fi

  if is_resolved_active && have_cmd resolvectl; then
    info "刷新 systemd-resolved DNS 缓存"
    resolvectl flush-caches >/dev/null 2>&1 || true
    fixed=1
  fi

  echo
  health_check_core
  [[ "$fixed" -eq 1 ]] && ok "已执行自动修复动作" || ok "无需修复"
}
