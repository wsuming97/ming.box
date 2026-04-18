
cloudinit_qga_detect_static_network() {
  # Return 0 if static networking is detected (higher risk cloud-init overrides),
  # Return 1 otherwise.
  # ifupdown
  if [[ -f /etc/network/interfaces ]]; then
    grep -Eqi '^[[:space:]]*iface[[:space:]].+[[:space:]]static' /etc/network/interfaces && return 0
    grep -Eqi '^[[:space:]]*address[[:space:]]+' /etc/network/interfaces && return 0
  fi
  if compgen -G "/etc/network/interfaces.d/*" >/dev/null 2>&1; then
    grep -RIn --line-number -E '^[[:space:]]*iface[[:space:]].+[[:space:]]static|^[[:space:]]*address[[:space:]]+' /etc/network/interfaces.d 2>/dev/null | head -n 1 >/dev/null 2>&1 && return 0
  fi

  # netplan
  if [[ -d /etc/netplan ]]; then
    grep -RIn --line-number -E '^[[:space:]]*addresses:|dhcp4:[[:space:]]*false|dhcp6:[[:space:]]*false' /etc/netplan 2>/dev/null | head -n 1 >/dev/null 2>&1 && return 0
  fi

  # NetworkManager
  if have_cmd nmcli; then
    nmcli -t -f NAME,IP4.METHOD con show --active 2>/dev/null | grep -q ':manual$' && return 0
  fi

  return 1
}

cloudinit_qga_has_instance_state() {
  [[ -d /var/lib/cloud/instance ]] && [[ -n "$(ls -A /var/lib/cloud/instance 2>/dev/null || true)" ]]
}

cloudinit_qga_safe_disable_network_if_needed() {
  # If we just installed cloud-init on a DD/non-cloud system with static IP,
  # cloud-init may generate DHCP config on next boot and break SSH.
  # To be safe, we default-disable cloud-init network management unless the user explicitly enables it.
  [[ -f "$CLOUDINIT_DISABLE_NET_FILE" ]] && return 0

  if ! have_cmd cloud-init; then return 0; fi
  # Only apply safe-disable when there is no prior cloud-init instance state (fresh install)
  if cloudinit_qga_has_instance_state; then return 0; fi

  if cloudinit_qga_detect_static_network; then
    ensure_dir "/etc/cloud/cloud.cfg.d"
    write_file "$CLOUDINIT_DISABLE_NET_FILE" "network: {config: disabled}"
    ok "已启用安全保护：默认禁止 cloud-init 接管网络（避免重启后 SSH 失联）"
    warn "如果你要使用面板“换 IP”功能：请在本菜单选择【开启 cloud-init 网络接管】后，再执行 cloud-init clean 并重启。"
  fi
}

cloudinit_qga_enable_network_management() {
  # Remove our disable file and also neutralize other 'network: {config: disabled}' lines if any.
  local changed="0"
  ensure_dir "$BACKUP_BASE"
  local bdir="${BACKUP_BASE}/cloudinit-enable-$(ts_now)"
  ensure_dir "$bdir"

  if [[ -f "$CLOUDINIT_DISABLE_NET_FILE" ]]; then
    cp -a "$CLOUDINIT_DISABLE_NET_FILE" "$bdir/" 2>/dev/null || true
    rm -f "$CLOUDINIT_DISABLE_NET_FILE" 2>/dev/null || true
    changed="1"
  fi

  # Also comment out any other disabling lines (rare but possible)
  if [[ -d /etc/cloud/cloud.cfg.d ]]; then
    local f
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      cp -a "$f" "$bdir/" 2>/dev/null || true
      sed -i -E 's/network:[[:space:]]*\{config:[[:space:]]*disabled\}/# dmitbox: network config enabled/g' "$f" 2>/dev/null || true
      changed="1"
    done < <(grep -RIl "network: {config: disabled}" /etc/cloud/cloud.cfg.d 2>/dev/null || true)
  fi
  if [[ -f /etc/cloud/cloud.cfg ]]; then
    if grep -q "network: {config: disabled}" /etc/cloud/cloud.cfg 2>/dev/null; then
      cp -a /etc/cloud/cloud.cfg "$bdir/" 2>/dev/null || true
      sed -i -E 's/network:[[:space:]]*\{config:[[:space:]]*disabled\}/# dmitbox: network config enabled/g' /etc/cloud/cloud.cfg 2>/dev/null || true
      changed="1"
    fi
  fi

  if [[ "$changed" == "1" ]]; then
    ok "已开启 cloud-init 网络接管（备份在：$bdir）"
  else
    ok "未发现 cloud-init 网络禁用项（无需开启）"
  fi
}

cloudinit_qga_find_net_disabled() {
  local hit="0"
  if [[ -d /etc/cloud/cloud.cfg.d ]]; then
    if grep -RIn --line-number "network:[[:space:]]*\{config:[[:space:]]*disabled\}" /etc/cloud/cloud.cfg.d 2>/dev/null | head -n 1 >/dev/null 2>&1; then
      hit="1"
    fi
  fi
  if [[ -f /etc/cloud/cloud.cfg ]]; then
    grep -qE "network:[[:space:]]*\{config:[[:space:]]*disabled\}" /etc/cloud/cloud.cfg 2>/dev/null && hit="1"
  fi
  echo "$hit"
}

cloudinit_qga_status() {
  echo
  echo -e "${c_bold}${c_white}换 IP 防失联：Cloud-init / QEMU Guest Agent 状态${c_reset}"
  sub_banner

  local ci="NO" qga="NO" qgas="N/A" net_dis="NO"
  have_cmd cloud-init && ci="YES"
  (have_cmd qemu-ga || have_cmd qemu-guest-agent) && qga="YES"

  if is_systemd; then

if systemctl is-active --quiet qemu-guest-agent 2>/dev/null; then qgas="active"; else qgas="inactive"; fi
  else
    qgas="(non-systemd)"
  fi

  [[ "$(cloudinit_qga_find_net_disabled)" == "1" ]] && net_dis="YES"

  print_kv "cloud-init 已安装" "$( [[ "$ci" == "YES" ]] && echo -e "${c_green}是${c_reset}" || echo -e "${c_yellow}否${c_reset}" )"
  print_kv "qemu-guest-agent 已安装" "$( [[ "$qga" == "YES" ]] && echo -e "${c_green}是${c_reset}" || echo -e "${c_yellow}否${c_reset}" )"
  print_kv "qemu-guest-agent 运行" "$qgas"
  print_kv "cloud-init 网络被禁用" "$( [[ "$net_dis" == "YES" ]] && echo -e "${c_yellow}是${c_reset}" || echo -e "${c_green}否${c_reset}" )"

  if [[ -f "$CLOUDINIT_DISABLE_NET_FILE" ]]; then
    print_kv "dmitbox 安全保护(禁用接管)" "$(echo -e "${c_yellow}已启用${c_reset}")"
  fi

  echo
  if [[ "$ci" == "YES" ]]; then
echo -e "${c_dim}cloud-init status（仅供参考）：${c_reset}"
local st=""
st="$(cloud-init status --long 2>/dev/null || true)"

echo "$st" | sed -n '1,10p'
if echo "$st" | grep -q '^status: error'; then
  # 取 detail 的第一行（通常就是失败模块）
  local detail=""
  detail="$(echo "$st" | awk 'BEGIN{p=0} /^detail:/{p=1;next} p{print; exit}')"
  if echo "$detail" | grep -q 'package-update-upgrade-install'; then
    warn "cloud-init 报错来源：package-update-upgrade-install（apt-get update 失败）。这通常不影响网络/换 IP，只影响开机时自动更新软件包。"
    echo -e "${c_dim}可选修复：运行 apt-get update 查看真实原因；若不想每次开机触发，可在本脚本里选择“禁用 cloud-init 自动 apt 更新”。${c_reset}"
  else
    warn "cloud-init 报错详情：${detail:-unknown}"
    echo -e "${c_dim}建议查看：tail -n 80 /var/log/cloud-init.log${c_reset}"
  fi
fi
  else
    warn "cloud-init 未安装：DD 系统后换 IP 很容易失联（建议先安装）"
  fi

  if [[ "$net_dis" == "YES" ]]; then
    warn "检测到 cloud-init 网络被禁用：面板换 IP 后可能不会自动更新网卡配置"
    warn "可在本脚本里执行：【修复 cloud-init 网络禁用】并建议重启"
  fi

  echo
  echo -e "${c_dim}说明：DMIT 面板的“换 IP”通常依赖 cloud-init 重新下发网络配置；缺少 cloud-init/QGA 或网络被禁用，可能导致换 IP 后 SSH 直接失联。${c_reset}"
}

cloudinit_qga_install() {
  info "安装/启用：cloud-init + qemu-guest-agent（换 IP 防失联）"
  warn "若安装过程看起来卡住：请先耐心等待下载/安装；也可以按 Ctrl+C 中断并返回菜单。"

  local interrupted="0"
  trap 'interrupted="1"' INT

  pkg_install cloud-init qemu-guest-agent

  trap - INT
  [[ "$interrupted" == "1" ]] && { warn "已中断安装，返回菜单"; return 0; }

  if is_systemd; then
    systemctl enable --now qemu-guest-agent >/dev/null 2>&1 || true
    # cloud-init/cloud-final 多为 oneshot：首次运行可能很久（且我们把输出吞掉了），
    # 会让菜单看起来“卡在完成”。因此改成：启用 + 后台启动（不阻塞菜单）。
    systemctl enable cloud-init cloud-config cloud-final >/dev/null 2>&1 || true
    [[ "${RUN_MODE:-menu}" == "menu" ]] && info "启动 cloud-init（后台，不阻塞菜单）"
    systemctl start --no-block cloud-init cloud-config cloud-final >/dev/null 2>&1 || true
  fi

  ok "已执行安装/启用（若源里无包会跳过）"
  cloudinit_qga_safe_disable_network_if_needed || true
  cloudinit_qga_status
}

cloudinit_qga_fix_network_disabled() {
  info "开启：cloud-init 网络接管（解除 network: {config: disabled}）"
  cloudinit_qga_enable_network_management
  warn "建议：执行 cloud-init clean 后重启一次，让网络元数据重新生效"
}

cloudinit_clean_and_hint_reboot() {
  if ! have_cmd cloud-init; then
    warn "cloud-init 未安装：无法 clean。可先执行【安装/启用 cloud-init + QGA】"
    return 0
  fi
  info "执行：cloud-init clean（清理旧状态，便于重新应用网络元数据）"
  cloud-init clean --logs >/dev/null 2>&1 || cloud-init clean >/dev/null 2>&1 || true
  ok "已执行 cloud-init clean"
  warn "通常建议重启一次（尤其是刚 DD 或刚换 IP 后）：reboot"
}

cloudinit_disable_pkg_updates() {
  info "禁用：cloud-init 自动 apt 更新/升级（避免 status:error）"
  if [[ ! -d /etc/cloud/cloud.cfg.d ]]; then
    mkdir -p /etc/cloud/cloud.cfg.d
  fi
  cat >"$CLOUDINIT_DISABLE_PKG_FILE" <<'EOF'

# This avoids 'cloud-init status: error' caused by transient apt-get update failures.
package_update: false
package_upgrade: false
package_reboot_if_required: false
EOF
  ok "已写入 $CLOUDINIT_DISABLE_PKG_FILE"
  warn "提示：这不会影响 cloud-init 下发网络/SSH key；只是不再自动执行 apt-get update/upgrade。"
}


cloudinit_qga_write_dmit_pve_cfg() {
  ensure_dir "/etc/cloud/cloud.cfg.d"
  # Match DMIT default-like behavior observed on original images:
  # - cloud-id: nocloud
  # - datasource_list: [ NoCloud, ConfigDrive, None ]
  # - prefer NoCloud label "cidata"
  write_file "$DMITBOX_PVE_CFG" "datasource_list: [ NoCloud, ConfigDrive, None ]
datasource:
  NoCloud:
    fs_label: cidata
"
  chmod 644 "$DMITBOX_PVE_CFG" >/dev/null 2>&1 || true
}

cloudinit_qga_install_seed_helper_systemd() {
  is_systemd || return 0
  # Helper: mount NoCloud/ConfigDrive seed media (iso/vfat) early, then stage into /var/lib/cloud/seed/nocloud-net
  write_file "$DMITBOX_SEED_SCRIPT" '#!/usr/bin/env bash
set -euo pipefail

seed_dir="/var/lib/cloud/seed/nocloud-net"
run_dir="/run/dmitbox-seed"
mkdir -p "$seed_dir" "$run_dir"

# Candidate labels used by common NoCloud / ConfigDrive implementations
labels=(cidata CIDATA config-2 CONFIG-2 configdrive CONFIGDRIVE)

find_dev_by_label() {
  local lbl="$1"
  local p="/dev/disk/by-label/$lbl"
  [[ -e "$p" ]] && readlink -f "$p" && return 0
  return 1
}

dev=""
for lbl in "${labels[@]}"; do
  if d=$(find_dev_by_label "$lbl"); then dev="$d"; break; fi
done

# Fallback: any iso9660 block device
if [[ -z "$dev" ]] && command -v blkid >/dev/null 2>&1; then
  dev=$(blkid -t TYPE=iso9660 -o device 2>/dev/null | head -n1 || true)
fi

[[ -z "$dev" ]] && exit 0

# Mount read-only (best-effort)
umount "$run_dir" >/dev/null 2>&1 || true
mount -o ro "$dev" "$run_dir" >/dev/null 2>&1 || exit 0

# NoCloud seed layout: user-data/meta-data/network-config at root
if [[ -f "$run_dir/meta-data" || -f "$run_dir/user-data" || -f "$run_dir/network-config" ]]; then
  for f in meta-data user-data network-config vendor-data; do
    [[ -f "$run_dir/$f" ]] && cp -f "$run_dir/$f" "$seed_dir/$f" >/dev/null 2>&1 || true
  done
  umount "$run_dir" >/dev/null 2>&1 || true
  exit 0
fi

# ConfigDrive (OpenStack): try to stage if present (best effort)
if [[ -d "$run_dir/openstack/latest" ]]; then
  # cloud-init can read ConfigDrive directly; we do not need to transform here.
  umount "$run_dir" >/dev/null 2>&1 || true
  exit 0
fi

umount "$run_dir" >/dev/null 2>&1 || true
exit 0
'
  chmod +x "$DMITBOX_SEED_SCRIPT" >/dev/null 2>&1 || true

  write_file "$DMITBOX_SEED_SERVICE" "[Unit]
Description=DMITBox stage cloud-init seed (NoCloud/ConfigDrive)
DefaultDependencies=no
Before=cloud-init-local.service
Wants=cloud-init-local.service

[Service]
Type=oneshot
ExecStart=$DMITBOX_SEED_SCRIPT

[Install]
WantedBy=cloud-init-local.service
"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable dmitbox-cloud-seed.service >/dev/null 2>&1 || true
}

cloudinit_qga_prepare_network_for_cloudinit_debian_ifupdown() {
  # DMIT default Debian images typically let cloud-init generate /etc/network/interfaces.d/* (ifupdown).
  # Only apply on Debian-like with ifupdown available and no active netplan yaml.
  have_cmd apt-get || return 0

  # If netplan yamls exist, don't force-convert (too risky).
  if [[ -d /etc/netplan ]] && ls /etc/netplan/*.yaml >/dev/null 2>&1; then
    warn "检测到 netplan 配置：不强制切换到 ifupdown（避免误伤）。"
    return 0
  fi

  # Ensure ifupdown installed
  pkg_install ifupdown >/dev/null 2>&1 || pkg_install ifupdown2 >/dev/null 2>&1 || true

  # Backup current network config
  ensure_dir "$BACKUP_BASE"
  local bdir="${BACKUP_BASE}/ipchange-dmitdefault-$(ts_now)"
  ensure_dir "$bdir"
  cp -a /etc/network "$bdir/" 2>/dev/null || true
  echo "$bdir" > "$DMITBOX_IPCHANGE_BACKUP_POINTER" 2>/dev/null || true

  # Minimal interfaces allowing cloud-init to drop config into interfaces.d
  ensure_dir /etc/network/interfaces.d
  write_file /etc/network/interfaces "auto lo
iface lo inet loopback

source /etc/network/interfaces.d/*
"
  chmod 644 /etc/network/interfaces >/dev/null 2>&1 || true

  # Remove any previous cloud-init generated file; it will be regenerated on boot from datasource
  rm -f /etc/network/interfaces.d/*cloud-init* 2>/dev/null || true

  # Ensure networking service enabled
  if is_systemd; then
    systemctl enable networking >/dev/null 2>&1 || true
  fi

  ok "已准备 ifupdown 结构：cloud-init 将在 /etc/network/interfaces.d/ 写入网卡配置"
  warn "提示：如果云端 metadata/seed 不可用，可能导致启动后无网；脚本已安装自动回滚保护。"
}

cloudinit_qga_install_net_rollback_protection() {
  is_systemd || return 0

  write_file "$DMITBOX_NET_ROLLBACK_SCRIPT" '#!/usr/bin/env bash
set -euo pipefail

log="/var/log/dmitbox-net-rollback.log"
ptr="/etc/dmitbox-ipchange-backup.path"

echo "[$(date -Is)] rollback-check start" >> "$log"

# wait a bit for cloud-init + networking to settle
sleep 90

# if there is a default route and at least one global IPv4, we consider it OK
if ip -4 route show default 2>/dev/null | grep -q "default"; then
  if ip -4 addr show scope global 2>/dev/null | grep -q "inet "; then
    echo "[$(date -Is)] network looks OK, no rollback" >> "$log"
    exit 0
  fi
fi

echo "[$(date -Is)] network NOT OK, attempting rollback" >> "$log"

bdir=""
[[ -f "$ptr" ]] && bdir="$(cat "$ptr" 2>/dev/null || true)"
if [[ -z "$bdir" || ! -d "$bdir" ]]; then
  # fallback: pick latest backup
  bdir="$(ls -dt /root/dmit-backup/ipchange-dmitdefault-* 2>/dev/null | head -n1 || true)"
fi

if [[ -n "$bdir" && -d "$bdir/network" ]]; then
  rm -rf /etc/network 2>/dev/null || true
  cp -a "$bdir/network" /etc/network 2>/dev/null || true
  echo "[$(date -Is)] restored /etc/network from $bdir" >> "$log"
fi

systemctl restart networking 2>/dev/null || true
systemctl restart systemd-networkd 2>/dev/null || true
systemctl restart NetworkManager 2>/dev/null || true

echo "[$(date -Is)] rollback done" >> "$log"
exit 0
'
  chmod +x "$DMITBOX_NET_ROLLBACK_SCRIPT" >/dev/null 2>&1 || true

  write_file "$DMITBOX_NET_ROLLBACK_SERVICE" "[Unit]
Description=DMITBox network rollback protection (after cloud-init)
After=cloud-final.service network-online.target
Wants=cloud-final.service network-online.target

[Service]
Type=oneshot
ExecStart=$DMITBOX_NET_ROLLBACK_SCRIPT

[Install]
WantedBy=multi-user.target
"
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable dmitbox-net-rollback.service >/dev/null 2>&1 || true
}

cloudinit_qga_preserve_ssh_auth() {
  # 目标：DD 后启用 cloud-init 时，尽量不改变现有 SSH 登录方式，避免重启锁死
  # - 尽量“保持/放宽”而不是收紧：如无法判断，默认认为允许密码登录（更不容易锁死）
  # - 永远禁止 cloud-init 删除 SSH host keys（避免指纹变化）
  mkdir -p /etc/cloud/cloud.cfg.d

  # 1) 尝试检测当前 SSH 是否允许密码登录
  local pa="unknown"
  if command -v sshd >/dev/null 2>&1; then
    # sshd -T 在不同系统/版本可能需要 root；这里容错
    pa="$(sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2; exit}')"
  fi
  if [[ "$pa" != "yes" && "$pa" != "no" ]]; then
    # 退化检测：扫描 sshd_config 及 drop-in
    local files=()
    [[ -f /etc/ssh/sshd_config ]] && files+=("/etc/ssh/sshd_config")
    if [[ -d /etc/ssh/sshd_config.d ]]; then
      while IFS= read -r -d '' f; do files+=("$f"); done < <(find /etc/ssh/sshd_config.d -maxdepth 1 -type f -name '*.conf' -print0 2>/dev/null || true)
    fi
    local hit=""
    if (( ${#files[@]} > 0 )); then
      hit="$(awk '
        BEGIN{IGNORECASE=1}
        $1 ~ /^PasswordAuthentication$/ {val=tolower($2); last=val}
        END{ if(last!="") print last; }
      ' "${files[@]}" 2>/dev/null || true)"
    fi
    if [[ "$hit" == "yes" || "$hit" == "no" ]]; then
      pa="$hit"
    else
      pa="unknown"
    fi
  fi

  # 2) 写入 cloud-init drop-in：禁止删 key；如果系统允许/不确定允许密码，则显式开启 ssh_pwauth
  local cfg="/etc/cloud/cloud.cfg.d/99-dmitbox-ssh.yaml"
  {
    echo "# Created by dmitbox: keep SSH reachable after enabling cloud-init"
    echo "disable_root: false"
    # 关键：不要让 cloud-init 删除 /etc/ssh/ssh_host_*（否则指纹变化）
    echo "ssh_deletekeys: false"
    # 如果原本允许密码，或无法判断，则开启（更不容易锁死）
    if [[ "$pa" == "yes" || "$pa" == "unknown" ]]; then
      echo "ssh_pwauth: true"
    fi
  } > "$cfg"

  # 3) 额外保险：写 sshd drop-in（优先不改主配置），只在“允许/不确定”时写入放宽项
  local dropdir="/etc/ssh/sshd_config.d"
  local dropfile=""
  if [[ -d "$dropdir" ]]; then
    dropfile="$dropdir/99-dmitbox-keep-access.conf"
    {
      echo "# Created by dmitbox: keep SSH access (avoid lockout after cloud-init/network change)"
      # 只放宽，不收紧；如果用户本来禁用了密码，我们也不强行开启
      if [[ "$pa" == "yes" || "$pa" == "unknown" ]]; then
        echo "PasswordAuthentication yes"
        echo "KbdInteractiveAuthentication yes"
        echo "ChallengeResponseAuthentication yes"
      fi
      # root 登录策略：如果用户用 root 登录，避免被默认策略挡住（仅放宽）
      echo "PermitRootLogin yes"
      echo "PubkeyAuthentication yes"
    } > "$dropfile"
  else
    # 没有 drop-in 的老系统：追加到 sshd_config（带 marker，方便回滚）
    if [[ -f /etc/ssh/sshd_config ]]; then
      if ! grep -q "DMITBOX-KEEP-ACCESS" /etc/ssh/sshd_config 2>/dev/null; then
        {
          echo ""
          echo "# --- DMITBOX-KEEP-ACCESS (added to avoid lockout) ---"
          if [[ "$pa" == "yes" || "$pa" == "unknown" ]]; then
            echo "PasswordAuthentication yes"
            echo "KbdInteractiveAuthentication yes"
            echo "ChallengeResponseAuthentication yes"
          fi
          echo "PermitRootLogin yes"
          echo "PubkeyAuthentication yes"
          echo "# --- DMITBOX-KEEP-ACCESS END ---"
        } >> /etc/ssh/sshd_config
      fi
    fi
  fi

  # 4) 立即尝试重载/重启 ssh（失败也不致命；并且加超时，避免 systemctl 卡住导致菜单无法返回）
  if is_systemd && have_cmd systemctl; then

if have_cmd timeout; then
      timeout 3s systemctl reload  --no-block ssh  >/dev/null 2>&1 || true
      timeout 3s systemctl reload  --no-block sshd >/dev/null 2>&1 || true
      timeout 5s systemctl restart --no-block ssh  >/dev/null 2>&1 || true
      timeout 5s systemctl restart --no-block sshd >/dev/null 2>&1 || true
    else
      systemctl reload  --no-block ssh  >/dev/null 2>&1 || true
      systemctl reload  --no-block sshd >/dev/null 2>&1 || true
      systemctl restart --no-block ssh  >/dev/null 2>&1 || true
      systemctl restart --no-block sshd >/dev/null 2>&1 || true
    fi
  fi


  echo "已写入 cloud-init SSH 保活配置：$cfg"
  [[ -n "$dropfile" ]] && echo "已写入 sshd drop-in：$dropfile"
  echo "提示：如果你原来就是“仅密钥登录”，上述配置不会影响；如果你用密码登录，这能显著降低重启后无法登录的概率。"
}

cloudinit_qga_dd_lockdown_network_only() {
  _need_root
  local cfg="/etc/cloud/cloud.cfg"
  local ts; ts="$(date +%Y%m%d-%H%M%S)"

  if [[ -f "$cfg" ]]; then
    local bak="${cfg}.dmitbox.bak.${ts}"
    cp -a "$cfg" "$bak"

    # DD 系统最容易踩坑：cloud-init 重新跑 users/ssh 等模块后，可能导致无法 SSH 或指纹变化。
    # 这里直接从主 cloud.cfg 里移除这些模块，保留 cloud-init 的网络接管能力。
    sed -i -E \
      -e '/^[[:space:]]*-[[:space:]]*(users-groups|ssh|set-passwords|ssh-import-id)[[:space:]]*$/d' \
      -e '/^[[:space:]]*-[[:space:]]*(ssh-authkey-fingerprints|keys-to-console)[[:space:]]*$/d' \
      -e '/^[[:space:]]*-[[:space:]]*(package-update-upgrade-install|apt-configure|apt-pipelining)[[:space:]]*$/d' \
      "$cfg"

    echo "已对 $cfg 做 DD 安全加固（备份：$bak）"
  else
    echo "未找到 $cfg，跳过 cloud-init 模块加固（不常见）。"
  fi

  # 防止 cloud-init 删除/重建 SSH HostKey（避免指纹变化）
  mkdir -p /etc/cloud/cloud.cfg.d
  cat > /etc/cloud/cloud.cfg.d/99_dmitbox_ssh_safety.cfg <<'YAML'
ssh_deletekeys: false
YAML
  chmod 0644 /etc/cloud/cloud.cfg.d/99_dmitbox_ssh_safety.cfg

  # 兜底：固化当前 sshd 的最终生效配置（含 include），避免后续被改成不能登录
  cloudinit_qga_preserve_ssh_auth
}



cloudinit_qga_apply_dmit_default_ipchange_mode() {
  info "DD 后适配：DMIT 默认换 IP 模式（NoCloud/ConfigDrive + cloud-init 接管网络）"
  warn "这会让 cloud-init 像 DMIT 原版镜像一样接管网卡配置，以便面板换 IP 不失联。"
  warn "已内置“自动回滚保护”：若重启后无网，会自动恢复原网络配置（见 /var/log/dmitbox-net-rollback.log）。"

  cloudinit_qga_install
  cloudinit_qga_preserve_ssh_auth
  # 关键：DD 后优先启用“network-only”锁定，避免 cloud-init 触碰 SSH/用户/密码/包更新。
  cloudinit_qga_dd_lockdown_network_only
  cloudinit_disable_pkg_updates || true
  cloudinit_qga_enable_network_management
  cloudinit_qga_write_dmit_pve_cfg
  cloudinit_qga_install_seed_helper_systemd
  cloudinit_qga_install_net_rollback_protection

  # Debian/ifupdown alignment (best effort)
  cloudinit_qga_prepare_network_for_cloudinit_debian_ifupdown || true

  # Force cloud-init to re-run network on next boot
  cloudinit_clean_and_hint_reboot

  ok "已完成 DMIT 默认换IP模式适配"
  warn "下一步：reboot（重启后 cloud-init 会读取 NoCloud/ConfigDrive 元数据并生成网卡配置）"
  warn "面板换 IP 后：一般需要 reboot 一次让新网络生效（与 DMIT 原版一致）"
}

cloudinit_qga_dmit_menu() {
  while true; do
    echo
    echo -e "${c_bold}${c_white}换 IP 防失联（cloud-init / QEMU Guest Agent）${c_reset}"
    sub_banner
    echo "  1) 检测状态（是否装了 cloud-init / QGA，是否禁用网络）"
    echo "  2) 安装/启用 cloud-init + QEMU Guest Agent"
    echo "  3) 开启 cloud-init 网络接管（解除 network: {config: disabled}）"
    echo "  4) cloud-init clean（建议换 IP 前/后执行，之后重启）"
    echo "  5) DD 后适配 DMIT 默认换IP（NoCloud/ConfigDrive + 接管网络）"
    echo "  6) 禁用 cloud-init 自动 apt 更新（避免 status:error）"
    echo "  0) 返回"
    local c=""
    read_tty c "选择> " ""
    case "$c" in
      1) cloudinit_qga_status; pause_up ;;
      2) cloudinit_qga_install || true; pause_up ;;
      3) cloudinit_qga_fix_network_disabled || true; pause_up ;;
      4) cloudinit_clean_and_hint_reboot || true; pause_up ;;
      5) cloudinit_qga_apply_dmit_default_ipchange_mode || true; pause_up ;;

      6) cloudinit_disable_pkg_updates || true; pause_up ;;
      0) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}
