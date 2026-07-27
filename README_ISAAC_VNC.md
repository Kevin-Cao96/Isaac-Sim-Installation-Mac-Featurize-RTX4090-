# Isaac Sim 远程 GUI 方案 (VNC)

> 适用场景：在无显示器的远程服务器上运行 Isaac Sim，在本机通过 VNC 查看 GUI（支持 Windows / macOS / Linux）

---

## 两种方案对比

Isaac Sim 的远程 GUI 有两种方案，取决于你的云服务器是否支持开放 UDP 端口。

### 方案 A：WebRTC Streaming Client（推荐，需要 UDP）

官方推荐的方案。信号走 TCP 49100，视频流走 UDP 47998。
- **需要云平台开放 UDP 端口**（阿里云、腾讯云、AWS 等支持）
- **延迟低、画质好**（NVENC 硬编码）
- 本机安装 Streaming Client 直连，不经过 SSH 隧道

### 方案 B：VNC + SSH 隧道（备选，只需 TCP）

当云平台**不开放 UDP 端口**时（如 featurize），用 VNC 替代。
- 全程 TCP 5900，SSH 隧道即可转发
- 画质一般，有延迟
- 适合开发和调试

> 如果你用的是阿里云 ECS / 腾讯云 / AWS 等主流云平台，**建议直接走方案 A（WebRTC）**。
> 如果云平台没有安全组或端口映射功能（如 featurize），走方案 B（VNC）。

---

## 整体架构

```
你的本机                             远程服务器
┌─────────────────┐      SSH 隧道      ┌────────────────────────┐
│ VNC 客户端       │ ─── TCP 5900 ───→ ｜ x11vnc                ｜
│ (macOS 屏幕共享) ｜                   │   ↓                   ｜
│                 │                   ｜ Xvfb (虚拟显示器 :99)   │
│                 │                   ｜   ↓                   ｜ 
│                 │                   ｜ fluxbox (窗口管理器)    ｜
│                 │                   ｜   ↓                   ｜
│                 │                   ｜ Isaac Sim GUI         ｜
└─────────────────┘                   └────────────────────────┘
```

数据流：VNC 画面 → x11vnc → SSH 隧道 → Mac 上显示

---

## 第一步：首次安装（服务器，仅一次）

### 1.1 SSH 连接服务器

```bash
ssh <用户名>@<服务器IP> -p <端口>
```

> 建议使用 VS Code Remote SSH：`Cmd+Shift+P` → `Remote-SSH: Connect to Host` → 输入 SSH 命令

### 1.2 安装系统依赖

```bash
sudo apt-get update
sudo apt-get install -y xvfb x11vnc fluxbox
```

- **xvfb**：虚拟帧缓冲区，模拟一个没有物理显示器的 X 服务器
- **x11vnc**：把 X 服务的画面通过 VNC 协议传输
- **fluxbox**：轻量窗口管理器，给 Isaac Sim 提供窗口环境

### 1.3 安装 Isaac Sim

```bash
cd ~

# 下载（约 12G）
# 根据你的架构选择：x86_64 或 aarch64
wget -O isaac-sim-standalone-6.0.1-linux-x86_64.zip \
  "https://downloads.isaacsim.nvidia.com/isaac-sim-standalone-6.0.1-linux-x86_64.zip"

# 解压
mkdir -p ~/isaacsim
unzip isaac-sim-standalone-6.0.1-linux-x86_64.zip -d ~/isaacsim

# 后处理脚本（创建扩展示例的符号链接）
cd ~/isaacsim && ./post_install.sh
```

> 如果下载被代理拦截，加上 `--no-proxy`：
> `wget --no-proxy -O ...`

> **Windows 服务器**：安装步骤相同，启动脚本改为 `isaac-sim.bat`。VNC 服务器推荐使用 [TightVNC](https://www.tightvnc.com/) 或 [UltraVNC](https://www.uvnc.com/)。

---

## 第二步：每天启动（服务器）

### 2.1 一键启动脚本

> **注意：`setup_isaac_vnc.sh` 不包含在 Isaac Sim 安装包里，需要单独获取。**
> 这也是为什么直接跑 `./setup_isaac_vnc.sh` 会报 "no such file or directory"。

有三种方式获取脚本：

**方式 A：直接从 GitHub 下载到服务器**

在服务器的 VS Code 终端里运行（首次使用时执行一次即可）：

```bash
cd ~/isaacsim
wget -O setup_isaac_vnc.sh   "https://raw.githubusercontent.com/Kevin-Cao96/Isaac-Sim-Installation-Mac-Featurize-RTX4090-/main/setup_isaac_vnc.sh"
chmod +x setup_isaac_vnc.sh
```

**方式 B：本机下载后 scp 上传**

先在本机 Mac 上下载脚本：

```bash
# 在本机终端
cd ~/Downloads
wget -O setup_isaac_vnc.sh   "https://raw.githubusercontent.com/Kevin-Cao96/Isaac-Sim-Installation-Mac-Featurize-RTX4090-/main/setup_isaac_vnc.sh"
```

然后传到服务器（替换 `<端口>` 为你的 SSH 端口）：

```bash
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

echo "===== Step 1: 创建虚拟显示器 ====="
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
SCRIPT
chmod +x ~/isaacsim/setup_isaac_vnc.sh
```

脚本就位后，以后每次启动只需要在服务器的 VS Code 终端里运行：

```bash
cd ~/isaacsim && ./setup_isaac_vnc.sh
```

### 2.2 脚本做了什么事

```
Step 1: Xvfb :99 启动虚拟显示器（1920×1080，24 位色深）
Step 2: fluxbox 启动窗口管理器
Step 3: x11vnc 在 5900 端口开启 VNC 服务
Step 4: Isaac Sim 启动，输出渲染到虚拟显示器
```

等待终端出现 `Isaac Sim Full App is loaded.`（约 2 分钟）。

### 2.3 手动启动（分步）

如果一键启动失败，可以分步执行排查：

```bash
# 1. 虚拟显示器
kill $(pgrep Xvfb) 2>/dev/null
Xvfb :99 -screen 0 1920x1080x24 +extension GLX +render &
export DISPLAY=:99

# 2. 窗口管理器
fluxbox &

# 3. VNC 服务器
kill $(pgrep x11vnc) 2>/dev/null
x11vnc -display :99 -forever -nopw -rfbport 5900 &

# 4. Isaac Sim
cd ~/isaacsim
DISPLAY=:99 ./isaac-sim.sh
```

---

## 第三步：连接 GUI（本机）

### 3.1 建立 SSH 隧道（支持 Windows / macOS / Linux）

```bash
ssh -L 5900:localhost:5900 <用户名>@<服务器IP> -p <端口>
```

输入服务器密码，**保持这个窗口开着**（关闭即断连）。

> VS Code 用户：也可以直接在底部 PORTS 面板添加 5900 端口实现转发。
> Windows 用户：需要安装 [OpenSSH 客户端](https://learn.microsoft.com/zh-cn/windows-server/administration/openssh/openssh_install_firstuse) 或使用 PowerShell 内置的 SSH。

### 3.2 打开 VNC 客户端

保持 SSH 隧道窗口开着，根据你的系统选择连接方式：

**macOS：**
```bash
open vnc://127.0.0.1:5900
```
或者 Finder → 前往 → 连接服务器 → `vnc://127.0.0.1:5900`

**Windows：**
安装 [VNC Viewer](https://www.realvnc.com/en/connect/download/viewer/)（RealVNC 免费版），连接 `127.0.0.1:5900`

**Linux：**
```bash
vncviewer 127.0.0.1:5900
```

如果弹出密码框，直接点连接（留空）。如果要求密码：
```bash
# 在服务器上设置 VNC 密码
x11vnc -display :99 -forever -rfbport 5900 -passwd 你的密码 &
```

---

## 维护命令

### 查看所有进程

```bash
ps aux | grep -E 'Xvfb|isaac|fluxbox|x11vnc' | grep -v grep
```

### 查看端口

```bash
# 查看 5900（VNC）是否在监听
ss -tlnp | grep 5900

# 查看所有 Isaac Sim 相关端口
ss -tlnp | grep -E '590|491'
```

### 重启各组件

```bash
# 重启 VNC
pkill x11vnc && x11vnc -display :99 -forever -nopw -rfbport 5900 &

# 重启虚拟显示器（会同时杀掉 Isaac Sim）
kill $(pgrep Xvfb)

# 重启窗口管理器
pkill fluxbox && fluxbox &
```

### 修改 VNC 密码

```bash
pkill x11vnc && x11vnc -display :99 -forever -rfbport 5900 -passwd 123 &
```

下次连接时用密码 `123`。

---

## 常见问题

### Q：连接 VNC 看到的是 fluxbox 桌面（白色背景），没有 Isaac Sim

Isaac Sim 可能没启动或退出了。回到 VS Code 终端，检查 Isaac Sim 的输出，如果没有在运行就重新启动：

```bash
cd ~/isaacsim && DISPLAY=:99 ./isaac-sim.sh
```

### Q：$DISPLAY 环境变量

Xvfb 创建了一个编号为 `:99` 的虚拟显示器。所有需要显示 GUI 的程序启动前都要设置 `DISPLAY=:99`（或 `export DISPLAY=:99`）。

### Q：x11vnc 报 "Address already in use"

旧的 x11vnc 进程还在。先杀掉再启动：

```bash
pkill x11vnc && x11vnc -display :99 -forever -nopw -rfbport 5900 &
```

### Q：为什么在 featurize 上不能用 WebRTC？

- WebRTC 视频流走 **UDP** 端口
- featurize 控制台没有开放自定义端口的功能
- SSH 隧道和 VS Code 端口转发只支持 **TCP**
- 所以只能退而求其次用 VNC

> 阿里云 ECS、腾讯云等主流云平台有安全组功能，可以开放 UDP 端口，直接走 WebRTC。

### Q：为什么不直接公网 IP 连 VNC？

云服务器默认防火墙会拦截非 SSH 的入站端口。如果有安全组功能（阿里云等），可以开 5900 直连，但 VNC 本身不加密，SSH 隧道更安全。推荐直接用 WebRTC（如果云平台支持 UDP）。

---

## 备选：WebRTC 方案（如果未来网络条件允许）

如果服务器有公网 IP 并且防火墙开放了 UDP 端口，可以这样配置：

```bash
cd ~/isaacsim
./isaac-sim.streaming.sh \
  --/exts/omni.kit.livestream.app/primaryStream/publicIp=<公网IP> \
  --/exts/omni.kit.livestream.app/primaryStream/signalPort=49100 \
  --/exts/omni.kit.livestream.app/primaryStream/streamPort=47998
```

然后在 Mac 上用 Streaming Client 连接 `<公网IP>:49100`。需要防火墙开放：
- **49100** TCP（信令）
- **47998** UDP（媒体流）

也可以尝试 Docker Compose 的 Web Viewer（走 TCP 8210，浏览器查看），适合远程云服务器，但需要 Docker。
