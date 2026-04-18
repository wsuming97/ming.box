ok()   { echo -e "${c_green}✔${c_reset} $*"; }
info() { echo -e "${c_cyan}➜${c_reset} $*"; }
warn() { echo -e "${c_yellow}⚠${c_reset} $*"; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    warn "请用 root 运行：sudo bash ${SCRIPT_NAME}"
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }
ts_now() { date +"%Y%m%d-%H%M%S"; }
ensure_dir() { mkdir -p "$1"; }

has_tty() { [[ -r /dev/tty ]]; }

read_tty() {
  local __var="$1" __prompt="$2" __default="${3:-}"
  local __val=""
  if has_tty; then
    read -r -p "$__prompt" __val </dev/tty || true
  else
    read -r -p "$__prompt" __val || true
  fi
  __val="${__val:-$__default}"
  printf -v "$__var" "%s" "$__val"
}

read_tty_secret() {
  local __var="$1" __prompt="$2"
  local __val=""
  if has_tty; then
    read -r -s -p "$__prompt" __val </dev/tty || true
    echo >&2 || true
  else
    read -r -s -p "$__prompt" __val || true
    echo >&2 || true
  fi
  printf -v "$__var" "%s" "$__val"
}

soft_clear() {
  printf "\033[2J\033[H" 2>/dev/null || true
  printf "\033[3J" 2>/dev/null || true
  if have_cmd clear; then clear >/dev/null 2>&1 || true; fi
}

pause_up() {
  [[ "$RUN_MODE" == "menu" ]] || return 0
  echo
  local msg="↩ 回车返回上级菜单..."
  printf "%s" "$msg"
  if [[ -t 0 ]]; then
    read -r _ || true
  elif [[ -r /dev/tty ]]; then
    read -r _ </dev/tty || true
  else
    sleep 2
  fi
  echo
}



pause_dmit_main() {
  [[ "$RUN_MODE" == "menu" ]] || return 0
  echo
  local msg="↩ 回车返回主菜单..."
  printf "%s" "$msg"
  if [[ -t 0 ]]; then
    read -r _ || true
  elif [[ -r /dev/tty ]]; then
    read -r _ </dev/tty || true
  else
    sleep 2
  fi
  echo
}





write_file() {
  local path="$1"
  local content="$2"
  umask 022
  mkdir -p "$(dirname "$path")"
  printf "%s\n" "$content" > "$path"
}

sysctl_apply_all() { sysctl --system >/dev/null 2>&1 || true; }

# ---------------- pkg helper ----------------
run_with_spinner() {
  # usage: run_with_spinner "title" cmd...
  local title="$1"; shift
  local log="/tmp/dmitbox-$(ts_now).log"

  info "$title"
  warn "若长时间无输出：这通常是 dpkg 在处理 triggers（如 libc-bin/ldconfig），不一定卡死。可随时按 Ctrl+C 中断。"

  ("$@") >"$log" 2>&1 &
  local pid=$!
  local spin='|/-\\'
  local i=0
  while kill -0 "$pid" >/dev/null 2>&1; do
    local j=$(( i % 4 ))
    # shellcheck disable=SC2059
    printf "\r${c_dim}…安装/配置进行中 %c  (log: %s)${c_reset}" "${spin:j:1}" "$log"
    sleep 0.2
    i=$((i+1))
  done
  wait "$pid"; local rc=$?
  printf "\r\033[K" || true
  if [[ $rc -ne 0 ]]; then
    warn "命令返回非 0（rc=$rc）。最近日志如下："
    tail -n 40 "$log" 2>/dev/null || true
  else
    ok "完成"
  fi
  return $rc
}

pkg_install() {
  local pkgs=("$@")
  [[ "${#pkgs[@]}" -eq 0 ]] && return 0

  # In menu mode, keep user informed (otherwise apt/dnf may look "stuck").
  local quiet="1"
  [[ "${RUN_MODE:-menu}" == "menu" ]] && quiet="0"

  # Avoid interactive prompts (needrestart/dpkg conffile prompts)
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a

  if have_cmd apt-get; then
    if [[ "$quiet" == "0" ]]; then
      info "正在安装：${pkgs[*]}"
      run_with_spinner "apt-get update" apt-get -o DPkg::Lock::Timeout=30 -y update || true
      run_with_spinner "apt-get install ${pkgs[*]}" \
        apt-get -o DPkg::Lock::Timeout=30 -y \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold \
        install "${pkgs[@]}" || true
    else
      apt-get -o DPkg::Lock::Timeout=30 -qq update >/dev/null 2>&1 || true
      apt-get -o DPkg::Lock::Timeout=30 -y install "${pkgs[@]}" >/dev/null 2>&1 || true
    fi
    return 0
  fi

  if have_cmd dnf; then
    [[ "$quiet" == "0" ]] && info "正在安装：${pkgs[*]}（可能需要一点时间）"
    if [[ "$quiet" == "0" ]]; then dnf -y install "${pkgs[@]}" || true; else dnf -y install "${pkgs[@]}" >/dev/null 2>&1 || true; fi
    return 0
  fi

  if have_cmd yum; then
    [[ "$quiet" == "0" ]] && info "正在安装：${pkgs[*]}（可能需要一点时间）"
    if [[ "$quiet" == "0" ]]; then yum -y install "${pkgs[@]}" || true; else yum -y install "${pkgs[@]}" >/dev/null 2>&1 || true; fi
    return 0
  fi

  if have_cmd apk; then
    [[ "$quiet" == "0" ]] && info "正在安装：${pkgs[*]}（可能需要一点时间）"
    if [[ "$quiet" == "0" ]]; then apk add --no-cache "${pkgs[@]}" || true; else apk add --no-cache "${pkgs[@]}" >/dev/null 2>&1 || true; fi
    return 0
  fi

  warn "未识别包管理器：请手动安装 ${pkgs[*]}"
}
