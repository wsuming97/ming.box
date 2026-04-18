# ---------------- helpers ----------------
default_iface() {
  local ifc=""
  ifc="$(ip -4 route 2>/dev/null | awk '/^default/{print $5; exit}' || true)"
  [[ -n "$ifc" ]] && { echo "$ifc"; return 0; }
  ifc="$(ip -6 route 2>/dev/null | awk '/^default/{print $5; exit}' || true)"
  [[ -n "$ifc" ]] && { echo "$ifc"; return 0; }
  echo "eth0"
}

ipv6_status() {
  local a d
  a="$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo "N/A")"
  d="$(sysctl -n net.ipv6.conf.default.disable_ipv6 2>/dev/null || echo "N/A")"
  echo "all=$a default=$d"
}

has_ipv6_global_addr() { ip -6 addr show scope global 2>/dev/null | grep -q "inet6 "; }
has_ipv6_default_route() { ip -6 route show default 2>/dev/null | grep -q "^default "; }

libc_kind() {
  if have_cmd getconf && getconf GNU_LIBC_VERSION >/dev/null 2>&1; then echo "glibc"; return 0; fi
  if have_cmd ldd && ldd --version 2>&1 | head -n 1 | grep -qi musl; then echo "musl"; return 0; fi
  if have_cmd ldd && ldd --version 2>&1 | grep -qi "glibc"; then echo "glibc"; return 0; fi
  echo "unknown"
}

is_systemd() { have_cmd systemctl; }
is_resolved_active() { is_systemd && systemctl is-active --quiet systemd-resolved 2>/dev/null; }

curl4_ok() { have_cmd curl && curl -4 -sS --max-time 5 ip.sb >/dev/null 2>&1; }
curl6_ok() { have_cmd curl && curl -6 -sS --max-time 5 ip.sb >/dev/null 2>&1; }

dns_resolve_ok() {
  if have_cmd getent; then getent hosts ip.sb >/dev/null 2>&1 && return 0; fi
  have_cmd curl && curl -sS --max-time 5 ip.sb >/dev/null 2>&1
}

# ---------------- banner ----------------
banner() {
  soft_clear
  echo -e "${c_bold}${c_white}全栖开荒工具箱${c_reset}  ${c_dim}(${SCRIPT_NAME})${c_reset}"
  echo -e "${c_dim}----------------------------------------------${c_reset}"
}

sub_banner() {
  echo -e "${c_dim}----------------------------------------------${c_reset}"
  echo -e "${c_dim}----------------------------------------------${c_reset}"
}

# ---------------- 环境快照 ----------------
env_snapshot() {
  ensure_dir "$BACKUP_BASE"
  local bdir="${BACKUP_BASE}/snapshot-$(ts_now)"
  ensure_dir "$bdir"
  info "环境快照 → ${bdir}"

  for p in /etc/sysctl.conf /etc/sysctl.d /etc/gai.conf /etc/modprobe.d /etc/default/grub /etc/network /etc/netplan /etc/systemd/network /etc/resolv.conf /etc/ssh/sshd_config /etc/ssh/sshd_config.d; do
    if [[ -e "$p" ]]; then
      mkdir -p "${bdir}$(dirname "$p")"
      cp -a "$p" "${bdir}${p}" 2>/dev/null || true
    fi
  done

  {
    echo "time=$(date)"
    echo "uname=$(uname -a)"
    echo "libc=$(libc_kind)"
    echo "iface=$(default_iface)"
    echo "timezone=$( (timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || true) )"
    echo "ipv6_sysctl=$(ipv6_status)"
    echo
    echo "== ip -br a =="; ip -br a 2>/dev/null || true
    echo
    echo "== ip -4 route =="; ip -4 route 2>/dev/null || true
    echo
    echo "== ip -6 addr =="; ip -6 addr show 2>/dev/null || true
    echo
    echo "== ip -6 route =="; ip -6 route show 2>/dev/null || true
    echo
    echo "== resolv.conf =="; sed -n '1,80p' /etc/resolv.conf 2>/dev/null || true
    echo
    echo "== qdisc =="; tc qdisc show 2>/dev/null || true
    echo
    echo "== bbr =="; cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || true
    echo
    echo "== sshd -T (if available) =="; (sshd -T 2>/dev/null | sed -n '1,220p' || true)
  } > "${bdir}/state.txt"

  ok "已保存：${bdir}"
  echo "查看：less -S ${bdir}/state.txt"
}
