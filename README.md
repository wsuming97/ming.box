# 🚀 Ming.Box — 终极全栖开荒与深度调优系统

> 一键搞定 VPS 新机初始化 + DMIT 深度调优，SSH 上去一行命令就能用。

## ⚡ 一键使用

SSH 登录你的 VPS（需 root 权限），执行：

```bash
bash <(curl -sL https://raw.githubusercontent.com/wsuming97/ming.box/main/init.sh)
```

或使用 wget：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/wsuming97/ming.box/main/init.sh)
```

> 🔒 脚本需要 root 权限运行，支持 Debian / Ubuntu / CentOS / Rocky / Alma / Alpine 等主流系统。

---

## 📋 功能一览

脚本包含两大模块，通过顶层菜单一键切换：

### 🛡️ 模块一：新机防御与优化阵列

快速完成全新 VPS 的安全加固和性能优化，支持**一键全自动**串行执行（选 0）。

| 功能 | 说明 |
|------|------|
| 📦 系统更新 | `apt update && upgrade` + 安装 curl/wget/nano/sudo |
| 🕐 时区校正 | 设置为 `Asia/Shanghai` |
| 💾 SWAP 管理 | 交互式创建/删除虚拟内存，自定义大小 |
| 🛡️ Fail2ban | SSH 防暴力破解，3 次错误封 24 小时 |
| 🔑 SSH 安全 | 修改端口为 55520 + 密钥登录（yuju 版） |
| ⚡ BBRx 加速 | jerry048/Tune 内核调优 + BBRx 拥塞控制 |

### 🛠️ 模块二：极客实验与深水专区（DMIT Box）

面向 DMIT 等高端 VPS 的深度网络调优工具箱。

<details>
<summary><b>🌐 网络工具（点击展开）</b></summary>

| 编号 | 功能 | 说明 |
|------|------|------|
| 1 | 网络体检 | 检测 IPv4/IPv6/DNS/MTU 状态 |
| 2 | 体检+自动修复 | 自动重拉 IPv6 地址/刷新 DNS |
| 3 | 开启 IPv6 | 重拉地址和路由，修复 RA/SLAAC |
| 4 | 关闭 IPv6 | 系统级 sysctl 禁用 |
| 5 | DNS 切换 | Cloudflare / Google / Quad9 |
| 6 | DNS 恢复 | 回到备份状态 |
| 7 | MTU 工具 | 自动探测 / 手动设置 / 开机持久化 |
| 8-10 | IPv4/IPv6 优先级 | 切换系统解析优先级 |
| 11 | IPv6 /64 工具 | 地址池管理 / NAT66 随机出网 |

</details>

<details>
<summary><b>🚄 TCP/BBR 调优（点击展开）</b></summary>

| 编号 | 功能 | 说明 |
|------|------|------|
| 12 | TCP 通用调优 | BBR + FQ + 缓冲区优化 |
| 13 | 恢复 Linux 默认 | CUBIC + pfifo_fast |
| 14 | 恢复 DMIT 默认 | DMIT 原厂 TCP 参数 |
| 15 | BBR 检测 | 检查内核 BBR 支持情况 |
| 16 | 安装 BBRv3 | XanMod 内核（需重启） |

</details>

<details>
<summary><b>🔐 系统/安全（点击展开）</b></summary>

| 编号 | 功能 | 说明 |
|------|------|------|
| 17 | 时区设置 | Asia/Shanghai |
| 18 | SSH 安全工具 | 密码/密钥/端口管理 |
| 19 | DD 重装系统 | 一键重装 Debian/Ubuntu/CentOS/Alpine 等 |

</details>

<details>
<summary><b>🧪 测试脚本（点击展开）</b></summary>

| 编号 | 功能 |
|------|------|
| GB5 | Geekbench 5 性能测试 |
| Bench | bench.sh 综合测试 |
| 回程 | 三网回程路由测试 |
| IP 质量 | IP.Check.Place 检测 |
| NodeQuality | 节点质量测试 |
| Telegram | Telegram 延迟测试 |
| 流媒体 | 流媒体解锁检测 |

</details>

<details>
<summary><b>🧰 工具（点击展开）</b></summary>

| 编号 | 功能 | 说明 |
|------|------|------|
| 21 | 一键还原 | 撤销脚本所有改动（DNS/MTU/IPv6/TCP/SSH） |
| 22 | 环境快照 | 保存当前系统网络配置（方便发工单） |
| 23 | 换 IP 防失联 | cloud-init / QGA 自动适配新 IP |

</details>

---

## 🔧 系统要求

- **权限**：root
- **系统**：Debian 10+ / Ubuntu 20.04+ / CentOS 7+ / Rocky 8+ / Alma 8+ / Alpine
- **架构**：x86_64 / ARM64
- **依赖**：curl 或 wget（脚本会自动安装缺失工具）

---

## ⚠️ 注意事项

- 脚本会在 `/root/dmit-backup/` 下自动备份原始配置，可使用「一键还原」恢复
- DD 重装系统功能**会清空系统盘**，请谨慎使用
- BBRv3 / BBRx 需要重启才能生效
- SSH 端口修改后请记住新端口，避免锁自己

---

## 📜 License

MIT
