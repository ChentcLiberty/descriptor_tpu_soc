#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Titan-TPU V2 环境配置脚本
# Author: Chen Weidong
# Date: 2026-01-21
# ═══════════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════════
# EDA 工具路径配置
# ═══════════════════════════════════════════════════════════════════════════════

# VCS 路径
export VCS_HOME=/home/jjt/install/synopsys/vcs/vcs/T-2022.06

# Verdi 路径（关键！用于 FSDB 波形生成）
export VERDI_HOME=/home/jjt/install/synopsys/verdi/verdi/T-2022.06

# Design Compiler 路径
export DC_HOME=/home/jjt/install/synopsys/dc/syn/T-2022.03-SP2

# ═══════════════════════════════════════════════════════════════════════════════
# License 配置
# ═══════════════════════════════════════════════════════════════════════════════

export SNPSLMD_LICENSE_FILE=27000@localhost

# ═══════════════════════════════════════════════════════════════════════════════
# PATH 配置
# ═══════════════════════════════════════════════════════════════════════════════

export PATH=${VCS_HOME}/bin:${PATH}
export PATH=${VERDI_HOME}/bin:${PATH}
export PATH=${DC_HOME}/bin:${PATH}

# ═══════════════════════════════════════════════════════════════════════════════
# 项目路径配置
# ═══════════════════════════════════════════════════════════════════════════════

export TITAN_TPU_ROOT=/home/jjt/TitanTPU

# ═══════════════════════════════════════════════════════════════════════════════
# 验证环境配置
# ═══════════════════════════════════════════════════════════════════════════════

echo "═══════════════════════════════════════════════════════════════════"
echo "🚀 Titan-TPU V2 环境配置"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "📂 EDA 工具路径:"
echo "  VCS_HOME    = ${VCS_HOME}"
echo "  VERDI_HOME  = ${VERDI_HOME}"
echo "  DC_HOME     = ${DC_HOME}"
echo ""
echo "📂 项目路径:"
echo "  TITAN_TPU_ROOT = ${TITAN_TPU_ROOT}"
echo ""
echo "🔑 License:"
echo "  SNPSLMD_LICENSE_FILE = ${SNPSLMD_LICENSE_FILE}"
echo ""

# 验证关键文件是否存在
if [ -f "${VERDI_HOME}/share/PLI/VCS/LINUX64/novas.tab" ]; then
    echo "✅ Verdi PLI 库找到: ${VERDI_HOME}/share/PLI/VCS/LINUX64/"
else
    echo "❌ 警告: Verdi PLI 库未找到!"
fi

if [ -f "${VCS_HOME}/bin/vcs" ]; then
    echo "✅ VCS 可执行文件找到"
else
    echo "❌ 警告: VCS 可执行文件未找到!"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "✅ 环境配置完成！"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "💡 使用方法:"
echo "  source env_setup.sh"
echo ""
