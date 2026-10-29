#!/bin/bash
# ============================================================
# Isaac Sim + VNC 一键启动脚本（优化版）
# 适用于远程无显示器（headless）服务器
# 优化：720p + 24 位色深 + Tight 压缩，减少网络传输量
# ============================================================

set -e

# ========== 配置区 ==========
ISAAC_DIR="$HOME/isaacsim"
VNC_PORT="${VNC_PORT:-5900}"
DISPLAY_NUM="${DISPLAY_NUM:-99}"
VNC_PASSWD="${VNC_PASSWD:-123}"
# ===========================

for cmd in Xvfb fluxbox x11vnc nvidia-smi; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "缺少命令: $cmd"
        exit 1
    fi
done

if ! nvidia-smi >/dev/null 2>&1; then
    echo "NVIDIA 驱动不可用。请先确认 nvidia-smi 能正常输出。"
    exit 1
fi

echo "===== Step 1: 创建虚拟显示器 ====="
kill $(pgrep -f "Xvfb :$DISPLAY_NUM ") 2>/dev/null || true
sleep 1
Xvfb :$DISPLAY_NUM -screen 0 1280x720x24 +extension GLX +render -noreset &
sleep 1
export DISPLAY=:$DISPLAY_NUM

echo "===== Step 2: 启动窗口管理器 ====="
fluxbox &

echo "===== Step 3: 启动 VNC 服务器 ====="
kill $(pgrep -f "x11vnc .*:$DISPLAY_NUM") 2>/dev/null || true
sleep 1
x11vnc -display :$DISPLAY_NUM -forever -rfbport "$VNC_PORT" -passwd "$VNC_PASSWD" \
    -tight -quality 5 -wait 10 -defer 10 -nocursorshape -noxdamage &

echo "===== Step 4: 启动 Isaac Sim ====="
echo "如果日志出现 vkCreateSwapchainKHR failed / backbuffers are not initialized，"
echo "说明 Xvfb 无法提供可用的 RTX Vulkan surface。请停止本脚本并改用 isaac-sim.streaming.sh。"
echo ""
cd "$ISAAC_DIR"
DISPLAY=:$DISPLAY_NUM ./isaac-sim.sh
