# Isaac Sim 远程 GUI 方案

> 在无显示器的远程服务器上运行 Isaac Sim，在本机查看 GUI（支持 Windows / macOS / Linux）

---

## 选哪个方案？

| 你的云平台 | 推荐方案 | 原因 |
|---|---|---|
| **阿里云 ECS** / 腾讯云 / AWS | ✅ **方案 A：WebRTC 直连** | 有安全组，能开 UDP 端口，延迟低画质好 |
| **featurize** / 恒源云 / 无端口映射 | ✅ **方案 B：VNC + SSH 隧道** | 平台不支持 UDP，VNC 走 TCP 也能用 |

---

## 方案 A：WebRTC 直连（推荐，需要云平台开放 UDP）

> 适用于阿里云 ECS、腾讯云、AWS 等支持安全组的云平台。

### A1. 选择 ECS 实例

Isaac Sim 需要 GPU 带 **RT Core**：

| 实例规格 | GPU | VRAM | RT Core | 适用 |
|---|---|---|---|---|
| **ecs.gn7i-c16g1.4xlarge** | NVIDIA A10 | 24 GB | ✅ | **推荐** |
| ecs.gn6i | T4 | 16 GB | ✅ | 最低配置 |
| ecs.gn7v | A100 | 40/80 GB | ❌ | **不支持** (无 RT Core) |

> A100 没有 RT Core 和 NVENC 编码器，Isaac Sim 的 livestreaming 和渲染都不支持。

**推荐配置**：`gn7i-c16g1.4xlarge`（16 vCPU / 60 GiB / A10 24GB）
**操作系统**：Ubuntu 24.04（选"预装 NVIDIA 驱动 + CUDA"的公共镜像）
**带宽**：至少 10 Mbps（按量计费）
**登录方式**：密钥对或密码均可

### A2. 安全组配置

实例创建后，去阿里云控制台 → **安全组** → **配置规则** → **添加入方向**：

| 优先级 | 协议 | 端口 | 授权对象 | 说明 |
|---|---|---|---|---|
| 1 | TCP | 49100 | 0.0.0.0/0 | WebRTC 信令 |
| 1 | UDP | 47998 | 0.0.0.0/0 | WebRTC 视频流 |

> 安全建议：授权对象改成你的公网 IP（百度搜"我的 IP"），只允许你本机连接。

### A3. 安装 Isaac Sim

SSH 登录服务器：

```bash
# 阿里云默认 root 登录
ssh root@你的公网IP

# 安装依赖
apt update && apt install -y wget unzip

# 下载（~12 GB，10 Mbps 约 20 分钟）
cd ~
wget -O isaac-sim-standalone-6.0.1-linux-x86_64.zip \
  "https://downloads.isaacsim.nvidia.com/isaac-sim-standalone-6.0.1-linux-x86_64.zip"

# 解压
mkdir -p ~/isaacsim
unzip isaac-sim-standalone-6.0.1-linux-x86_64.zip -d ~/isaacsim

# 后处理
cd ~/isaacsim && ./post_install.sh
```

### A4. 启动 Streaming

```bash
cd ~/isaacsim
./isaac-sim.streaming.sh \
  --allow-root \
  --/exts/omni.kit.livestream.app/primaryStream/publicIp=你的公网IP \
  --/exts/omni.kit.livestream.app/primaryStream/signalPort=49100 \
  --/exts/omni.kit.livestream.app/primaryStream/streamPort=47998
```

等待终端出现 `Isaac Sim Full Streaming App is loaded.`（约 2 分钟）。

### A5. 本机连接

在本机打开 **Isaac Sim WebRTC Streaming Client**（从 [NVIDIA 下载页面](https://docs.isaacsim.omniverse.nvidia.com/latest/installation/download.html) 获取），填写：

| 字段 | 值 |
|---|---|
| Server Address | 你的实例公网 IP |
| Signal Port | 49100 |
| Stream Port | 47998 |

点 **Connect**，画面通过 UDP 直连，NVENC 硬编码，延迟极低。

### A6. 停止计费

不需要时在阿里云控制台**停止实例**：

- 计算资源（vCPU + 内存）停止计费
- 系统盘和数据盘仍收费
- **固定公网 IP 可能会变**——下次启动后 IP 可能不同
- 建议使用**弹性公网 IP（EIP）** 保持 IP 不变

---

## 方案 B：VNC + SSH 隧道（备选，仅需 TCP）

> 适用于 featurize、恒源云等不开放 UDP 端口 / 无安全组的云平台。

### B1. 首次安装（服务器，仅一次）

#### 安装系统依赖

```bash
# 以 Ubuntu 为例
sudo apt-get update
sudo apt-get install -y xvfb x11vnc fluxbox
```

- **xvfb**：虚拟帧缓冲区，模拟物理显示器
- **x11vnc**：把 X 服务的画面通过 VNC 传输
- **fluxbox**：轻量窗口管理器，给 Isaac Sim 提供窗口环境

#### 安装 Isaac Sim

```bash
cd ~

# 下载（~12 GB，根据带宽约 3-30 分钟）
wget -O isaac-sim-standalone-6.0.1-linux-x86_64.zip \
  "https://downloads.isaacsim.nvidia.com/isaac-sim-standalone-6.0.1-linux-x86_64.zip"

# 解压
mkdir -p ~/isaacsim
unzip isaac-sim-standalone-6.0.1-linux-x86_64.zip -d ~/isaacsim

# 后处理
cd ~/isaacsim && ./post_install.sh
```

> 下载被代理拦截时加 `--no-proxy`：`wget --no-proxy -O ...`

#### 获取一键启动脚本

`setup_isaac_vnc.sh` 不包含在 Isaac Sim 安装包里，有三种方式获取：

**方式 A（推荐）：直接从 GitHub 下载到服务器**

```bash
cd ~/isaacsim
wget -O setup_isaac_vnc.sh \
  "https://raw.githubusercontent.com/Kevin-Cao96/Isaac-Sim-Installation-Mac-Featurize-RTX4090-/main/setup_isaac_vnc.sh"
chmod +x setup_isaac_vnc.sh
```

**方式 B：本机下载后 scp 上传**

```bash
# 本机 Mac 终端
cd ~/Downloads
wget -O setup_isaac_vnc.sh \
  "https://raw.githubusercontent.com/Kevin-Cao96/Isaac-Sim-Installation-Mac-Featurize-RTX4090-/main/setup_isaac_vnc.sh"

# 传到服务器
scp -P <端口> ~/Downloads/setup_isaac_vnc.sh <用户名>@<服务器IP>:~/isaacsim/
```

**方式 C：直接在服务器上用 cat 创建**

```bash
cat > ~/isaacsim/setup_isaac_vnc.sh << 'SCRIPT'
#!/bin/bash
set -e
ISAAC_DIR="$HOME/isaacsim"
VNC_PORT=5900
DISPLAY_NUM=99
VNC_PASSWD="123"

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
x11vnc -display :$DISPLAY_NUM -forever -rfbport $VNC_PORT -passwd "$VNC_PASSWD" -nocursorshape -noxdamage &

echo "===== Step 4: 启动 Isaac Sim ====="
cd "$ISAAC_DIR"
DISPLAY=:$DISPLAY_NUM ./isaac-sim.sh
SCRIPT
chmod +x ~/isaacsim/setup_isaac_vnc.sh
```

### B2. 每天启动

```bash
cd ~/isaacsim && ./setup_isaac_vnc.sh
```

脚本会自动完成：

| 步骤 | 操作 |
|---|---|
| Step 1 | Xvfb :99 启动虚拟显示器（1280×720，16 位色深） |
| Step 2 | fluxbox 启动窗口管理器 |
| Step 3 | x11vnc 在 5900 端口开启 VNC 服务（密码 123） |
| Step 4 | Isaac Sim 启动，渲染到虚拟显示器 |

等待终端出现 `Isaac Sim Full App is loaded.`（约 2 分钟）。

#### 手动启动（分步，用于排查）

```bash
# 1. 虚拟显示器
kill $(pgrep Xvfb) 2>/dev/null
Xvfb :99 -screen 0 1280x720x16 +extension GLX +render &
export DISPLAY=:99

# 2. 窗口管理器
fluxbox &

# 3. VNC 服务器
kill $(pgrep x11vnc) 2>/dev/null
x11vnc -display :99 -forever -rfbport 5900 -passwd 123 -nocursorshape -noxdamage &

# 4. Isaac Sim
cd ~/isaacsim
DISPLAY=:99 ./isaac-sim.sh
```

### B3. 本机连接

#### 建立 SSH 隧道

```bash
# 本机终端，替换为你的服务器信息
ssh -L 5900:localhost:5900 <用户名>@<服务器IP> -p <端口>
```

输入密码，**保持这个窗口开着**。

> VS Code Remote SSH 用户：也可在底部 PORTS 面板添加 5900 端口。如果点不亮，用上面这条命令。

#### 打开 VNC 客户端

保持隧道窗口开着，根据系统选择：

**macOS：**
```bash
open vnc://127.0.0.1:5900
```
或 Finder → 前往 → 连接服务器 → `vnc://127.0.0.1:5900`

**Windows：**
安装 [VNC Viewer](https://www.realvnc.com/en/connect/download/viewer/)，连接 `127.0.0.1:5900`

**Linux：**
```bash
vncviewer 127.0.0.1:5900
```

VNC 密码：`123`

### B4. 维护命令

```bash
# 查看进程
ps aux | grep -E 'Xvfb|isaac|fluxbox|x11vnc' | grep -v grep

# 查看端口
ss -tlnp | grep -E '590|491'

# 重启 VNC
pkill x11vnc && x11vnc -display :99 -forever -rfbport 5900 -passwd 123 -nocursorshape -noxdamage &

# 重启虚拟显示器（会同时杀掉 Isaac Sim）
kill $(pgrep Xvfb)

# 修改 VNC 密码
pkill x11vnc && x11vnc -display :99 -forever -rfbport 5900 -passwd 你的密码 &
```

---

## FAQ

### Q：VNC 画面卡顿怎么办？

VNC + SSH 隧道的延迟主要由网络和加密开销导致，可以优化：

```bash
# 1. 降低分辨率 + 16bit 色深（减少传输量）
Xvfb :99 -screen 0 1280x720x16 ...

# 2. SSH 用更快的加密算法
ssh -c aes128-gcm@openssh.com -L 5900:localhost:5900 ...

# 3. 或者直接换方案 A（WebRTC），不走隧道
```

如果卡得没法用，说明你的云平台不适合 VNC，建议换到阿里云等支持 UDP 的平台走方案 A。

### Q：连接 VNC 看到 fluxbox 桌面（白色背景），没有 Isaac Sim

Isaac Sim 可能没启动或退出了。检查终端输出，重新启动：

```bash
cd ~/isaacsim && DISPLAY=:99 ./isaac-sim.sh
```

### Q：x11vnc 报 "Address already in use"

旧的 x11vnc 还在：

```bash
pkill x11vnc && x11vnc -display :99 -forever -rfbport 5900 -passwd 123 -nocursorshape -noxdamage &
```

### Q：阿里云 ECS 启动报 "cannot run as root"

加 `--allow-root`：

```bash
./isaac-sim.sh --allow-root
# 或
./isaac-sim.streaming.sh --allow-root --/exts/...
```

### Q：WebRTC 连接黑屏

检查：
1. 安全组是否开放了 **UDP 47998**（光开 TCP 不够）
2. 实例的 `publicIp` 参数是否填了正确的公网 IP
3. 等待 Isaac Sim 完全加载（`Isaac Sim Full Streaming App is loaded.`）
4. 防火墙是否拦截了 UDP（部分云平台需要额外放行）

### Q：为什么 featurize 不能用 WebRTC？

featurize 的控制台没有开放自定义端口（UDP）的功能，而 WebRTC 视频流必须走 UDP。SSH 隧道只支持 TCP，所以只能用 VNC。

### Q：实例停机后公网 IP 变了怎么办？

阿里云固定公网 IP 的实例，停机后重启 IP 可能变化。解决：
- 在控制台将固定公网 IP 转为**弹性公网 IP（EIP）**
- EIP 即使停机也保留，且可随时绑定/解绑

### Q：可以去哪里下载 WebRTC Streaming Client？

去 Isaac Sim [下载页面](https://docs.isaacsim.omniverse.nvidia.com/latest/installation/download.html)，Latest Release 区域下载对应平台的版本。

---

## 仓库文件

| 文件 | 用途 | 适用方案 |
|---|---|---|
| [setup_isaac_vnc.sh](setup_isaac_vnc.sh) | 服务器一键启动 VNC + Isaac Sim | 方案 B（VNC） |
| [connect_isaac_vnc.sh](connect_isaac_vnc.sh) | 本机 SSH 隧道 + VNC 连接 | 方案 B（VNC） |
| [README_ISAAC_VNC.md](README_ISAAC_VNC.md) | 本文件 | 两套方案 |
