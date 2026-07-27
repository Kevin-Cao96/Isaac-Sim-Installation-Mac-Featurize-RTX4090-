#!/bin/bash
# ============================================================
# Isaac Sim + VNC 一键启动脚本（优化版）
# 适用于远程无显示器（headless）服务器
# 优化：720p + Tight压缩 + 低画质模式，减少网络传输量
# ============================================================

set -e

# ========== 配置区 ==========
ISAAC_DIR="$HOME/isaacsim"
VNC_PORT=5900
DISPLAY_NUM=99
VNC_PASSWD="123"
# ===========================

echo "===== Step 1: 创建虚拟显示器 ====="
kill $(pgrep Xvfb) 2>/dev/null || true
sleep 1
Xvfb :$DISPLAY_NUM -screen 0 1280x720x16 +extension GLX +render &
sleep 1
export DISPLAY=:$DISPLAY_NUM

echo "===== Step 2: 启动窗口管理器 ====="
fluxbox &

echo "===== Step 3: 启动 VNC 服务器 ====="
kill $(pgrep x11vnc) 2>/dev/null || true
sleep 1
x11vnc -display :$DISPLAY_NUM -forever -rfbport $VNC_PORT -passwd "$VNC_PASSWD" -tight -quality 5 -wait 10 -defer 10 -nocursorshape -noxdamage &

echo "===== Step 4: 启动 Isaac Sim ====="
cd "$ISAAC_DIR"
DISPLAY=:$DISPLAY_NUM ./isaac-sim.sh
