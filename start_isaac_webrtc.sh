#!/bin/bash
# Start Isaac Sim headless WebRTC streaming for a remote GPU instance.

set -euo pipefail

ISAAC_DIR="${ISAAC_DIR:-$HOME/isaacsim}"
PUBLIC_IP="${PUBLIC_IP:-}"
SIGNAL_PORT="${SIGNAL_PORT:-49100}"
STREAM_PORT="${STREAM_PORT:-47998}"

die() {
    echo "错误: $*" >&2
    exit 1
}

for cmd in nvidia-smi curl; do
    command -v "$cmd" >/dev/null 2>&1 || die "缺少命令: $cmd"
done

nvidia-smi >/dev/null 2>&1 || die "NVIDIA 驱动不可用，请先确认 nvidia-smi 正常"

if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP="$(curl -4 -fsS --max-time 10 https://ifconfig.me 2>/dev/null || true)"
fi

[ -n "$PUBLIC_IP" ] || die "无法自动获取公网 IP，请通过 PUBLIC_IP=<公网IP> 显式传入"

[[ "$SIGNAL_PORT" =~ ^[0-9]+$ ]] || die "SIGNAL_PORT 必须是数字"
[[ "$STREAM_PORT" =~ ^[0-9]+$ ]] || die "STREAM_PORT 必须是数字"

STREAM_SCRIPT="$ISAAC_DIR/isaac-sim.streaming.sh"
[ -x "$STREAM_SCRIPT" ] || die "找不到可执行文件: $STREAM_SCRIPT"

if [ "$(id -u)" -eq 0 ]; then
    export OMNI_KIT_ALLOW_ROOT=1
fi

if command -v ldconfig >/dev/null 2>&1 &&
    ! ldconfig -p 2>/dev/null | grep -q 'libnvidia-encode\.so'; then
    echo "警告: 未找到 libnvidia-encode.so，WebRTC 视频编码可能失败。" >&2
fi

echo "Isaac Sim:       $ISAAC_DIR"
echo "Public IP:       $PUBLIC_IP"
echo "Signaling port:  $SIGNAL_PORT/TCP"
echo "Media port:      $STREAM_PORT/UDP"
echo ""
echo "请确认优云智算防火墙已放行上述 TCP 和 UDP 入站端口。"
echo "等待日志出现: Isaac Sim Full Streaming App is loaded."
echo ""

cd "$ISAAC_DIR"

exec ./isaac-sim.streaming.sh \
    "--/exts/omni.kit.livestream.app/primaryStream/publicIp=${PUBLIC_IP}" \
    "--/exts/omni.kit.livestream.app/primaryStream/signalPort=${SIGNAL_PORT}" \
    "--/exts/omni.kit.livestream.app/primaryStream/streamPort=${STREAM_PORT}"
