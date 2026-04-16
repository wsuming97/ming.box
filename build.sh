#!/bin/bash
# ============================================================
# build.sh — 将 src/ 下的模块文件按编号顺序拼接为单个 init.sh
# 用法：bash build.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/src"
OUTPUT="${SCRIPT_DIR}/init.sh"
BACKUP="${OUTPUT}.bak"

# 检查 src 目录
if [ ! -d "$SRC_DIR" ]; then
    echo "❌ 错误：找不到 src/ 目录"
    exit 1
fi

# 备份旧文件
if [ -f "$OUTPUT" ]; then
    cp "$OUTPUT" "$BACKUP"
    echo "📦 已备份旧版 → init.sh.bak"
fi

# 统计模块数
modules=("$SRC_DIR"/*.sh)
module_count=${#modules[@]}
echo "🔧 发现 ${module_count} 个模块文件"

# 拼接
{
    first=1
    for f in "${modules[@]}"; do
        basename_f="$(basename "$f")"

        if [ "$first" -eq 1 ]; then
            # 第一个文件完整输出（包含 shebang）
            cat "$f"
            first=0
        else
            # 后续文件：去掉 shebang 行
            echo ""
            echo "# ══════════════════════════════════════════════════════════"
            echo "# 模块: ${basename_f}"
            echo "# ══════════════════════════════════════════════════════════"
            echo ""
            # 跳过 shebang 行（如果有的话）
            sed '1{/^#!/d;}' "$f"
        fi
    done

    echo ""
    echo "# ── 构建时间: $(date -u '+%Y-%m-%d %H:%M:%S UTC') ──"
} > "$OUTPUT"

chmod +x "$OUTPUT"

# 统计结果
total_lines=$(wc -l < "$OUTPUT")
total_bytes=$(wc -c < "$OUTPUT")
echo ""
echo "✅ 构建完成！"
echo "   📄 输出: init.sh"
echo "   📊 ${total_lines} 行 / ${total_bytes} 字节"
echo "   📦 模块: ${module_count} 个"
echo ""

# 语法检查
echo "🔍 语法检查..."
if bash -n "$OUTPUT" 2>&1; then
    echo "✅ 语法检查通过"
else
    echo "❌ 语法检查失败！请检查模块文件"
    exit 1
fi
