#!/bin/bash
# ============================================================
# Ming.Box — 终极全栖开荒与深度调优系统
# 模块化版本 · 由 build.sh 自动拼接为单文件发布
# ============================================================

# ---------- 严格模式 ----------
set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="init.sh"
AD_TEXT=""

# ---------- 全局路径 ----------
TUNE_SYSCTL_FILE="/etc/sysctl.d/99-dmit-tcp-tune.conf"
DMIT_TCP_DEFAULT_FILE="/etc/sysctl.d/99-dmit-tcp-dmitdefault.conf"
IPV6_SYSCTL_FILE="/etc/sysctl.d/99-dmit-ipv6.conf"
IPV6_FIX_SYSCTL_FILE="/etc/sysctl.d/99-dmit-ipv6-fix.conf"
GAI_CONF="/etc/gai.conf"
BACKUP_BASE="/root/dmit-backup"

MTU_SERVICE="/etc/systemd/system/dmit-mtu.service"
MTU_VALUE_FILE="/etc/dmit-mtu.conf"

RESOLV_BACKUP="${BACKUP_BASE}/resolv.conf.orig"

SSH_ORIG_TGZ="${BACKUP_BASE}/ssh-orig.tgz"
SSH_DROPIN_DIR="/etc/ssh/sshd_config.d"
SSH_DROPIN_FILE="${SSH_DROPIN_DIR}/99-dmitbox.conf"

CLOUDINIT_DISABLE_NET_FILE="/etc/cloud/cloud.cfg.d/99-dmitbox-disable-network-config.cfg"
CLOUDINIT_DISABLE_PKG_FILE="/etc/cloud/cloud.cfg.d/99-dmitbox-disable-apt.cfg"

DMITBOX_PVE_CFG="/etc/cloud/cloud.cfg.d/99_dmitbox_pve.cfg"
DMITBOX_SEED_SCRIPT="/usr/local/sbin/dmitbox-cloud-seed.sh"
DMITBOX_SEED_SERVICE="/etc/systemd/system/dmitbox-cloud-seed.service"
DMITBOX_NET_ROLLBACK_SCRIPT="/usr/local/sbin/dmitbox-net-rollback.sh"
DMITBOX_NET_ROLLBACK_SERVICE="/etc/systemd/system/dmitbox-net-rollback.service"
DMITBOX_IPCHANGE_BACKUP_POINTER="/etc/dmitbox-ipchange-backup.path"
DMITBOX_IPCHANGE_BACKUP_MARKER="${DMITBOX_IPCHANGE_BACKUP_MARKER:-$DMITBOX_IPCHANGE_BACKUP_POINTER}"

IPV6_POOL_CONF="/etc/dmit-ipv6-pool.conf"
IPV6_POOL_SERVICE="/etc/systemd/system/dmit-ipv6-pool.service"

IPV6_RAND_CONF="/etc/dmit-ipv6-rand.conf"
IPV6_RAND_NFT="/etc/nftables.d/dmitbox-ipv6-rand.nft"
IPV6_RAND_SERVICE="/etc/systemd/system/dmit-ipv6-rand.service"

RUN_MODE="${RUN_MODE:-menu}" # menu | cli

# ---------- 统一颜色定义（DMIT + VPS 共用）----------
c_reset="\033[0m"
c_dim="\033[2m"
c_bold="\033[1m"
c_green="\033[32m"
c_yellow="\033[33m"
c_cyan="\033[36m"
c_white="\033[37m"
c_red="\033[0;31m"
c_blue="\033[0;34m"

# VPS 模块兼容别名（不再在 VPS 模块重复定义）
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
BLUE="\033[0;34m"
NC="\033[0m"
BOLD="\033[1m"
