
# ======================================================================
ssh_pkg_install() {
  if have_cmd apk; then
    pkg_install openssh
  else
    pkg_install openssh-server openssh-client
  fi
  if ! have_cmd sshd && [[ -x /usr/sbin/sshd ]]; then
    export PATH="$PATH:/usr/sbin:/sbin"
  fi
}

ssh_backup_once() {
  ensure_dir "$BACKUP_BASE"
  if [[ ! -f "$SSH_ORIG_TGZ" ]]; then
    info "SSH：备份原始配置 → $SSH_ORIG_TGZ"
    tar -czf "$SSH_ORIG_TGZ" /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null || \
      tar -czf "$SSH_ORIG_TGZ" /etc/ssh/sshd_config 2>/dev/null || true
    ok "SSH 原始配置已备份"
  fi
}

sshd_restart() {
  if is_systemd; then
    systemctl restart ssh  >/dev/null 2>&1 || true
    systemctl restart sshd >/dev/null 2>&1 || true
    systemctl try-restart ssh  >/dev/null 2>&1 || true
    systemctl try-restart sshd >/dev/null 2>&1 || true
  else
    service ssh restart  >/dev/null 2>&1 || true
    service sshd restart >/dev/null 2>&1 || true
  fi
}

sshd_status_hint() {
  echo -e "${c_dim}--- SSH 当前生效配置（节选）---${c_reset}"
  if have_cmd sshd; then
    sshd -T 2>/dev/null | egrep -i 'port|passwordauthentication|permitrootlogin|pubkeyauthentication|authenticationmethods|kbdinteractiveauthentication|challengeresponseauthentication|usepam|maxauthtries|logingracetime|clientaliveinterval|clientalivecountmax' || true
  else
    warn "未找到 sshd 命令，改为简单 grep："
    egrep -Rin -i 'Port|PasswordAuthentication|PubkeyAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication|UsePAM|PermitRootLogin|AuthenticationMethods' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null || true
  fi
  echo -e "${c_dim}--------------------------------${c_reset}"
}

# 便携删除配置行（避免 sed -i /I 在某些系统不兼容）
conf_strip_keys_in_file() {
  local f="$1"; shift
  [[ -f "$f" ]] || return 0
  local tmp="/tmp/.dmitbox.$$.$(basename "$f").tmp"
  awk -v KEYS="$(printf "%s|" "$@")" '
    BEGIN{
      n=split(KEYS,a,"|");
      for(i=1;i<=n;i++){ if(a[i]!=""){ k[tolower(a[i])]=1; } }
    }
    {
      line=$0
      # keep comments
      if(line ~ /^[[:space:]]*#/){ print line; next }
      # detect key as first token
      m=line
      sub(/^[[:space:]]+/,"",m)
      split(m,toks,/([[:space:]]+|=)/)
      key=tolower(toks[1])
      if(key in k){
        next
      }
      print line
    }
  ' "$f" > "$tmp" 2>/dev/null || { rm -f "$tmp" >/dev/null 2>&1 || true; return 0; }
  cat "$tmp" > "$f" 2>/dev/null || true
  rm -f "$tmp" >/dev/null 2>&1 || true
}

ssh_dropin_ensure() {
  ensure_dir "$SSH_DROPIN_DIR"
  if [[ ! -f "$SSH_DROPIN_FILE" ]]; then
    write_file "$SSH_DROPIN_FILE" "# managed by ${SCRIPT_NAME}"
  fi
  chown root:root "$SSH_DROPIN_FILE" >/dev/null 2>&1 || true
  chmod 600 "$SSH_DROPIN_FILE" >/dev/null 2>&1 || true
}

# 核心修复：清掉所有冲突项（主配置 + 其它 drop-in），确保我们的 99 生效
ssh_remove_conflicts_everywhere() {
  local keys=(
    Port PasswordAuthentication PermitRootLogin PubkeyAuthentication
    KbdInteractiveAuthentication ChallengeResponseAuthentication
    AuthenticationMethods UsePAM MaxAuthTries LoginGraceTime
    ClientAliveInterval ClientAliveCountMax PermitEmptyPasswords
  )

  # 主配置清理
  conf_strip_keys_in_file /etc/ssh/sshd_config "${keys[@]}" || true

  # drop-in 清理（除了我们自己的 99）
  if [[ -d "$SSH_DROPIN_DIR" ]]; then
    local f
    for f in "$SSH_DROPIN_DIR"/*.conf; do
      [[ -e "$f" ]] || continue
      [[ "$f" == "$SSH_DROPIN_FILE" ]] && continue
      conf_strip_keys_in_file "$f" "${keys[@]}" || true
    done
  fi
}

ssh_dropin_set_kv() {
  local key="$1" val="$2"
  ssh_dropin_ensure
  # 清理旧行（在我们的 99 内）
  conf_strip_keys_in_file "$SSH_DROPIN_FILE" "$key" || true
  printf "%s %s\n" "$key" "$val" >> "$SSH_DROPIN_FILE"
  chmod 600 "$SSH_DROPIN_FILE" >/dev/null 2>&1 || true
}

ssh_socket_disable_if_any() {
  is_systemd || return 0
  if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx "ssh.socket"; then
    if systemctl is-enabled --quiet ssh.socket 2>/dev/null; then
      warn "检测到 ssh.socket 已启用：将 disable（否则端口可能被固定在 22）"
      systemctl disable --now ssh.socket >/dev/null 2>&1 || true
    else
      systemctl stop ssh.socket >/dev/null 2>&1 || true
    fi
  fi
}

ssh_random_pass() { tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 18 || true; }

ssh_create_user_with_password() {
  local user="$1"
  local passwd="$2"

  if ! id "$user" >/dev/null 2>&1; then
    info "创建用户：$user"
    if have_cmd useradd; then
      useradd -m -s /bin/bash "$user" >/dev/null 2>&1 || true
    elif have_cmd adduser; then
      adduser -D "$user" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$user" >/dev/null 2>&1 || true
    else
      warn "没有 useradd/adduser，无法创建用户"
      return 1
    fi
  fi

  if have_cmd chpasswd; then
    echo "${user}:${passwd}" | chpasswd
  else
    if have_cmd passwd; then
      printf "%s\n%s\n" "$passwd" "$passwd" | passwd "$user" >/dev/null 2>&1 || {
        warn "设置密码失败（缺 chpasswd 且 passwd 不可用）"
        return 1
      }
    else
      warn "系统缺少 chpasswd/passwd，无法设置密码"
      return 1
    fi
  fi

  ok "已设置 ${user} 密码"
  echo -e "${c_green}${user} 密码：${passwd}${c_reset}"

  if getent group sudo >/dev/null 2>&1; then
    usermod -aG sudo "$user" >/dev/null 2>&1 || true
  elif getent group wheel >/dev/null 2>&1; then
    usermod -aG wheel "$user" >/dev/null 2>&1 || true
  fi
}

ssh_apply_base_hardening() {
  # 先清冲突、再写我们的 99，保证最终生效
  ssh_remove_conflicts_everywhere || true
  ssh_socket_disable_if_any || true
  ssh_dropin_set_kv "KbdInteractiveAuthentication" "no"
  ssh_dropin_set_kv "ChallengeResponseAuthentication" "no"
  ssh_dropin_set_kv "PermitEmptyPasswords" "no"
  ssh_dropin_set_kv "UsePAM" "yes"
  ssh_dropin_set_kv "MaxAuthTries" "3"
  ssh_dropin_set_kv "LoginGraceTime" "20"
  ssh_dropin_set_kv "ClientAliveInterval" "60"
  ssh_dropin_set_kv "ClientAliveCountMax" "2"
  ssh_dropin_set_kv "AuthenticationMethods" "any"
}

ssh_safe_enable_password_for_user_keep_root_key() {
  local user="${1:-dmit}"
  ssh_pkg_install
  ssh_backup_once

  warn "推荐模式：普通用户密码登录；root 禁止密码（仅密钥）"
  warn "建议保持当前 SSH 会话不要断开，确认新用户可登录后再退出"

  ssh_apply_base_hardening

  ssh_dropin_set_kv "PasswordAuthentication" "yes"
  ssh_dropin_set_kv "PubkeyAuthentication" "yes"
  ssh_dropin_set_kv "PermitRootLogin" "prohibit-password"

  local p; p="$(ssh_random_pass)"
  [[ -z "${p:-}" ]] && { warn "生成随机密码失败"; return 1; }
  ssh_create_user_with_password "$user" "$p" || true

  if have_cmd sshd && ! sshd -t >/dev/null 2>&1; then
    warn "sshd 配置校验失败：自动回滚"
    ssh_restore_key_login || true
    return 1
  fi

  sshd_restart
  ok "已重启 SSH（推荐模式已生效）"
  sshd_status_hint
}

ssh_enable_password_keep_key_for_user() {
  local user="${1:-root}"
  local mode="${2:-random}" # random|custom
  local passwd="${3:-}"

  ssh_pkg_install
  ssh_backup_once

  warn "中等模式：开启密码登录（保留密钥登录）"
  warn "建议保持当前 SSH 会话不要断开，确认密码可登录后再退出"

  ssh_apply_base_hardening
  ssh_dropin_set_kv "PasswordAuthentication" "yes"
  ssh_dropin_set_kv "PubkeyAuthentication" "yes"
  ssh_dropin_set_kv "PermitRootLogin" "yes"

  if [[ "$mode" == "random" ]]; then passwd="$(ssh_random_pass)"; fi
  [[ -z "${passwd:-}" ]] && { warn "密码为空：取消"; return 1; }

  if id "$user" >/dev/null 2>&1; then
    if have_cmd chpasswd; then
      echo "${user}:${passwd}" | chpasswd
    else
      printf "%s\n%s\n" "$passwd" "$passwd" | passwd "$user" >/dev/null 2>&1 || true
    fi
    ok "已设置用户密码：${user}"
    echo -e "${c_green}新密码：${passwd}${c_reset}"
  else
    warn "用户不存在：$user（未设置密码）"
  fi

  if have_cmd sshd && ! sshd -t >/dev/null 2>&1; then
    warn "sshd 配置校验失败：自动回滚"
    ssh_restore_key_login || true
    return 1
  fi

  sshd_restart
  ok "已重启 SSH（密码+密钥均可）"
  sshd_status_hint
}

ssh_password_only_disable_key_risky() {
  local user="${1:-root}"

local mode="${2:-random}" # random|custom
  local passwd="${3:-}"

  ssh_pkg_install
  ssh_backup_once

  warn "高风险模式：仅密码登录（禁用密钥）"
  warn "有锁门风险：务必保持当前 SSH 会话不断开"
  local ans=""
  read_tty ans "确认继续请输入 YES > " ""
  if [[ "${ans}" != "YES" ]]; then
    warn "已取消"
    return 0
  fi

  ssh_apply_base_hardening
  ssh_dropin_set_kv "PasswordAuthentication" "yes"
  ssh_dropin_set_kv "PubkeyAuthentication" "no"
  ssh_dropin_set_kv "PermitRootLogin" "yes"

  if [[ "$mode" == "random" ]]; then passwd="$(ssh_random_pass)"; fi
  [[ -z "${passwd:-}" ]] && { warn "密码为空：取消"; return 1; }

  if id "$user" >/dev/null 2>&1; then
    if have_cmd chpasswd; then
      echo "${user}:${passwd}" | chpasswd
    else
      printf "%s\n%s\n" "$passwd" "$passwd" | passwd "$user" >/dev/null 2>&1 || true
    fi
    ok "已设置用户密码：${user}"
    echo -e "${c_green}新密码：${passwd}${c_reset}"
  else
    warn "用户不存在：$user（未设置密码）"
  fi

  if have_cmd sshd && ! sshd -t >/dev/null 2>&1; then
    warn "sshd 配置校验失败：自动回滚"
    ssh_restore_key_login || true
    return 1
  fi

  sshd_restart
  ok "已重启 SSH（仅密码登录）"
  sshd_status_hint
}

ssh_restore_key_login() {
  ssh_backup_once
  info "SSH：恢复原来的配置（从备份还原）"
  if [[ -f "$SSH_ORIG_TGZ" ]]; then
    tar -xzf "$SSH_ORIG_TGZ" -C / 2>/dev/null || true
    rm -f "$SSH_DROPIN_FILE" 2>/dev/null || true
    sshd_restart
    ok "已恢复 SSH 原始配置并重启"
    sshd_status_hint
  else
    warn "未找到备份：$SSH_ORIG_TGZ"
  fi
}

ssh_current_ports() {
  if have_cmd sshd; then
    sshd -T 2>/dev/null | awk '$1=="port"{print $2}' | tr '\n' ' ' | sed 's/[[:space:]]*$//'
    return 0
  fi
  local ports=""
  ports="$(grep -RihE '^[[:space:]]*Port[[:space:]]+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null | awk '{print $2}' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  echo "${ports:-22}"
}

port_in_use() {
  local p="$1"
  if have_cmd ss; then
    ss -lntp 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${p}$" && return 0
  elif have_cmd netstat; then
    netstat -lntp 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${p}$" && return 0
  fi
  return 1
}

firewall_open_port_best_effort() {
  local p="$1"

  if have_cmd ufw; then
    if ufw status 2>/dev/null | grep -qi "Status: active"; then
      ufw allow "${p}/tcp" >/dev/null 2>&1 || true
      ok "已尝试放行 ufw：${p}/tcp"
      return 0
    fi
  fi

  if have_cmd firewall-cmd; then
    if firewall-cmd --state >/dev/null 2>&1; then
      firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
      ok "已尝试放行 firewalld：${p}/tcp"
      return 0
    fi
  fi

  if have_cmd iptables; then
    iptables -C INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1 || \
      iptables -I INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1 || true
    ok "已尝试放行 iptables：${p}/tcp（可能不持久）"
    return 0
  fi

  warn "未检测到可用防火墙工具：请自行放行 ${p}/tcp"
  return 0
}

ssh_set_port() {
  local newp="$1"

  [[ "$newp" =~ ^[0-9]+$ ]] || { warn "端口必须是数字"; return 1; }
  if (( newp < 1 || newp > 65535 )); then warn "端口范围 1-65535"; return 1; fi
  if (( newp < 1024 )); then warn "不建议使用 1024 以下端口"; fi

  local cur_ports; cur_ports="$(ssh_current_ports || echo "22")"
  if echo " $cur_ports " | grep -q " ${newp} "; then
    warn "端口 ${newp} 已在 SSH 当前配置中"
    return 0
  fi

  if port_in_use "$newp"; then
    warn "端口 ${newp} 似乎已被占用（请换一个）"
    return 1
  fi

  ssh_pkg_install
  ssh_backup_once

  warn "更换 SSH 端口会影响新连接"
  warn "强烈建议保持当前 SSH 会话不要断开"
  warn "请先测试：ssh -p ${newp} user@你的IP"

  ssh_apply_base_hardening
  ssh_dropin_set_kv "Port" "$newp"
  firewall_open_port_best_effort "$newp"

  if have_cmd sshd && ! sshd -t >/dev/null 2>&1; then
    warn "sshd 配置校验失败：将恢复备份"
    ssh_restore_key_login || true
    return 1
  fi

  sshd_restart
  ok "已尝试切换 SSH 端口 → ${newp}"

  echo -e "${c_dim}--- 立即验证 ---${c_reset}"
  sshd -T 2>/dev/null | egrep -i 'port|passwordauthentication|permitrootlogin|pubkeyauthentication|authenticationmethods' || true

ss -lntp 2>/dev/null | grep -E "sshd|:${newp}\b|:22\b" || true

  echo -e "${c_green}提示：请用新端口测试登录成功后，再退出当前会话${c_reset}"
  echo -e "${c_dim}当前端口：$(ssh_current_ports)${c_reset}"
}

ssh_dmit_menu() {
  while true; do
    echo
    echo -e "${c_bold}${c_white}SSH 工具（安全优先）${c_reset}"
    sub_banner
    echo "  1) 创建新用户 + 密码登录（root 仅密钥，更安全）"
    echo "  2) 开启密码登录（保留密钥）"
    echo "  3) 仅密码登录（禁用密钥，高风险）"
    echo "  4) 更换 SSH 端口（并尝试放行防火墙）"
    echo "  5) 恢复 SSH 原始配置（用备份还原）"
    echo "  6) 查看 SSH 当前生效状态（含端口）"
    echo "  0) 返回"
    local c=""
    read_tty c "选择> " ""
    case "$c" in
      1)
        local u=""
        read_tty u "新用户名（默认 dmit）> " "dmit"
        ssh_safe_enable_password_for_user_keep_root_key "$u" || true
        pause_up
        ;;
      2)
        local u="" m="" p=""
        read_tty u "用户名（默认 root）> " "root"
        echo "  1) 随机密码"
        echo "  2) 自定义密码"
        read_tty m "选择> " ""
        if [[ "$m" == "1" ]]; then
          ssh_enable_password_keep_key_for_user "$u" "random" "" || true
        elif [[ "$m" == "2" ]]; then
          read_tty_secret p "设置密码（输入不回显）> "
          ssh_enable_password_keep_key_for_user "$u" "custom" "$p" || true
        else
          warn "无效选项"
        fi
        pause_up
        ;;
      3)
        local u="" m="" p=""
        read_tty u "用户名（默认 root）> " "root"
        echo "  1) 随机密码"
        echo "  2) 自定义密码"
        read_tty m "选择> " ""
        if [[ "$m" == "1" ]]; then
          ssh_password_only_disable_key_risky "$u" "random" "" || true
        elif [[ "$m" == "2" ]]; then
          read_tty_secret p "设置密码（输入不回显）> "
          ssh_password_only_disable_key_risky "$u" "custom" "$p" || true
        else
          warn "无效选项"
        fi
        pause_up
        ;;
      4)
        echo -e "${c_dim}当前 SSH 端口：$(ssh_current_ports)${c_reset}"
        local p=""
        read_tty p "输入新端口（建议 20000-59999）> " ""
        ssh_set_port "$p" || true
        pause_up
        ;;
      5) ssh_restore_key_login || true; pause_up ;;
      6)
        sshd_status_hint
        echo -e "${c_dim}当前端口：$(ssh_current_ports)${c_reset}"
        pause_up
        ;;
      0) return 0 ;;
      *) warn "无效选项"; pause_up ;;
    esac
  done
}
