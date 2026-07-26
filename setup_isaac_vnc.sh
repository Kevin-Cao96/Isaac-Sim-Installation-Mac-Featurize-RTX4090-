#!/bin/bash
# ============================================================
# Isaac Sim + VNC 一键启动脚本
# 适用于远程无显示器（headless）服务器
# ============================================================

set -e

# ========== 配置区 ==========
ISAAC_DIR="$HOME/isaacsim"
VNC_PORT=5900
DISPLAY_NUM=99
# ===========================

echo "===== Step 1: 创建虚拟显示器 ====="
# 杀掉旧的 Xvfb
kill $(pgrep Xvfb) 2>/dev/null || true
sleep 1
Xvfb :$DISPLAY_NUM -screen 0 1920x1080x24 +extension GLX +render &
sleep 1
export DISPLAY=:$DISPLAY_NUM

echo "===== Step 2: 启动窗口管理器 ====="
fluxbox &

echo "===== Step 3: 启动 VNC 服务器 ====="
kill $(pgrep x11vnc) 2>/dev/null || true
sleep 1
x11vnc -display :$DISPLAY_NUM -forever -nopw -rfbport $VNC_PORT &

echo "===== Step 4: 启动 Isaac Sim ====="
cd "$ISAAC_DIR"
DISPLAY=:$DISPLAY_NUM ./isaac-sim.sh
