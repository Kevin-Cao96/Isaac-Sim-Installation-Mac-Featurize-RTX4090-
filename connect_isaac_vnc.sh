#!/bin/bash
# ============================================================
# Isaac Sim VNC 连接脚本
# 在 你本机 MacBook 上运行
# ============================================================

echo "===== 连接 Isaac Sim VNC ====="
echo "用法: ./connect_isaac_vnc.sh <用户名> <主机> <端口>"
echo "示例: ./connect_isaac_vnc.sh featurize workspace.featurize.cn 29800"
echo ""

if [ "$#" -lt 3 ]; then
    echo "请提供: 用户名 主机 端口"
    echo "例如: ./connect_isaac_vnc.sh featurize workspace.featurize.cn 29800"
    exit 1
fi

USER=$1
HOST=$2
PORT=$3

echo "1. 建立 SSH 隧道（5900 -> 远程 5900）..."
echo "   输入服务器密码后窗口保持开着"
echo ""
ssh -L 5900:localhost:5900 $USER@$HOST -p $PORT

# 如果上面的 SSH 会话结束（被关闭），会执行到这里
echo ""
echo "SSH 隧道已关闭。"
echo "重新连接请再次运行此脚本。"
