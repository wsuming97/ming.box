# 🤖 ming.box — AI 专用代理配置

iOS 全平台代理配置，专为 AI 高强度使用场景定制。  
Claude / Gemini / OpenAI / Copilot 独立分流，防 DNS 泄露，按地区自动测速。

---

## 📱 一键导入

| APP | 配置链接 | 导入方式 |
|-----|---------|---------|
| **Shadowrocket**（小火箭） | `https://raw.githubusercontent.com/wsuming97/ming.box/main/shadowrocket-ai.conf` | 配置 → + → 粘贴链接 → 下载 → 使用配置 |
| **Quantumult X**（圈X） | `https://raw.githubusercontent.com/wsuming97/ming.box/main/quantumultx-ai.conf` | ⚙️ → 配置文件 → 下载 → 粘贴链接 |
| **Loon** | `https://raw.githubusercontent.com/wsuming97/ming.box/main/loon-ai.conf` | 配置 → 从URL下载 → 粘贴链接 |

> ⚠️ 导入后需要**重新添加你的节点订阅**，配置文件不包含节点信息。

---

## ✨ 功能特性

### 🧠 AI 服务独立分流

每个 AI 服务独立选择节点，互不影响。某个 IP 被风控？只换对应的组就行。

| 策略组 | 覆盖服务 | 建议节点 |
|--------|---------|---------|
| 🧠 Claude | claude.ai / anthropic.com / claudeusercontent.com 等 | 美国（风控最严） |
| 💎 Gemini | gemini.google.com / aistudio / deepmind / notebooklm 等 | 日本 / 美国 |
| 🤖 OpenAI | chatgpt.com / openai.com / sora.com / Azure CDN 等 | 日本 / 美国（封 HK） |
| 🛠 Copilot | githubcopilot.com / copilot.microsoft.com 等 | 美国 |
| 🔮 OtherAI | Cursor / Perplexity / Grok / Midjourney / Mistral / HuggingFace / Poe / v0.dev / Replit 等 | 美国 / 日本 |

总计覆盖 **51 条 AI 域名**。

### 🛡 DNS 防泄露

| 措施 | 说明 |
|------|------|
| 禁用系统 DNS | 运营商 DNS 不参与解析 |
| DoH 加密 | 国内域名走 `doh.pub` / `dns.alidns.com`，全程加密 |
| AI 域名走海外 DNS | AI 相关域名走 Cloudflare `1.1.1.1` 解析，防 DNS 污染 |
| IPv6 关闭 | 防止 IPv6 泄露真实位置 |
| WebRTC 拦截 | 屏蔽 STUN 协议，防浏览器泄露 |

### 📺 流媒体 & 社交分流

YouTube / Netflix / Disney+ / TikTok / Telegram / Twitter / Google / Microsoft / Apple，每个独立选择节点。

### ⚡ 按地区自动测速

自动选择延迟最低的节点，每 5 分钟测速一次：

🇭🇰 香港 · 🇹🇼 台湾 · 🇯🇵 日本 · 🇸🇬 新加坡 · 🇰🇷 韩国 · 🇺🇸 美国

### 🎵 TikTok 解锁

默认解锁美国区（配置内有日本/韩国/台湾区可切换）。

---

## 🔧 导入后必做

1. **添加节点订阅**：导入配置后订阅会被清空，需要重新添加你的机场订阅链接
2. **选择节点**：为各策略组选择合适的节点
3. **断开重连**：修改配置后务必关闭 → 重新打开连接

### 圈X 额外步骤

如需 TikTok 解锁和 Google 防跳转功能，需要安装并信任 MITM 证书：

```
⚙️ → MitM → 生成证书 → 安装证书
→ iPhone 设置 → 通用 → 关于本机 → 证书信任设置 → 启用
→ 回到圈X → 开启 MitM 和 重写 开关
```

---

## 🧪 验证

导入并连接后，访问以下网站检查是否有泄露：

- DNS 泄露测试：[ip.net.coffee/dns](https://ip.net.coffee/dns/)
- IP 泄露测试：[ipleak.net](https://ipleak.net/)
- WebRTC 测试：[browserleaks.com/webrtc](https://browserleaks.com/webrtc)

---

## 📋 规则来源

| 来源 | 用途 |
|------|------|
| [blackmatrix7/ios_rule_script](https://github.com/blackmatrix7/ios_rule_script) | 分流规则（AI / 流媒体 / 社交 / 国内外） |
| [limbopro/Profiles4limbo](https://github.com/limbopro/Profiles4limbo) | 毒奶配置框架 & AI 补充规则 |
| [w37fhy/QuantumultX](https://github.com/w37fhy/QuantumultX) | 按地区自动测速正则 |
| [KOP-XIAO/QuantumultX](https://github.com/KOP-XIAO/QuantumultX) | 资源解析器 |
| [Semporia/TikTok-Unlock](https://github.com/Semporia/TikTok-Unlock) | TikTok 解锁重写 |
| [Koolson/Qure](https://github.com/Koolson/Qure) | 策略组图标 |

---

## 📄 License

MIT
