# Isaac Sim 远程 GUI 方案 (VNC)

> 适用场景：云服务器（featurize.cn 等）上运行 Isaac Sim，在本机 MacBook 上看 GUI

---

## 为什么不用 WebRTC Streaming Client？

Isaac Sim 官方推荐用 **WebRTC Streaming Client**（信号走 TCP 49100，视频流走 UDP 47998），但云服务器通常不开放 UDP 端口，而 SSH / VS Code 的端口转发只支持 TCP，所以 WebRTC 媒体流出不来（黑屏）。

**失败的尝试：**

| 方案 | 原因 |
|---|---|
| 直连公网 IP + 端口 | featurize 防火墙拦截 |
| VS Code PORTS 面板 | 只支持 TCP 转发，WebRTC 需要 UDP |
| socat 桥接 UDP↔TCP | 端口绑定/转发链路复杂，不稳定 |
| SSH -L 隧道 | 同样只支持 TCP |

**最终方案：VNC**

VNC 全程走 **TCP 5900**，SSH 隧道可以完美转发，稳定可靠。

---

## 整体架构

```
你的 MacBook                         featurize 云服务器
┌─────────────────┐      SSH 隧道      ┌────────────────────────┐
│ VNC 客户端       │ ─── TCP 5900 ───→ │ x11vnc                 │
│ (macOS 屏幕共享) │                   │   ↓                    │
│                  │                   │ Xvfb (虚拟显示器 :99)   │
│                  │                   │   ↓                    │
│                  │                   │ fluxbox (窗口管理器)     │
│                  │                   │   ↓                    │
│                  │                   │ Isaac Sim GUI          │
└─────────────────┘                   └────────────────────────┘
```

数据流：VNC 画面 → x11vnc → SSH 隧道 → Mac 上显示

---

## 第一步：首次安装（服务器，仅一次）

### 1.1 连接 VS Code Remote SSH

VS Code → Cmd+Shift+P → `Remote-SSH: Connect to Host` →
输入 `ssh featurize@workspace.featurize.cn -p <你的端口>`
输入密码连上

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

# 下载（约 12G，约 3 分钟）
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

---

## 第二步：每天启动（服务器）

### 2.1 一键启动脚本

把 `setup_isaac_vnc.sh` 传到服务器上：

```bash
# 在你本机 Mac 终端传文件
scp -P <端口> /path/to/setup_isaac_vnc.sh featurize@workspace.featurize.cn:~/isaacsim/
```

然后在服务器的 VS Code 终端里：

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

## 第三步：连接 GUI（本机 MacBook）

### 3.1 建立 SSH 隧道

打开 MacBook 的本机终端，运行：

```bash
ssh -L 5900:localhost:5900 featurize@workspace.featurize.cn -p <你的端口>
```

输入服务器密码，**保持这个窗口开着**（关闭即断连）。

如果 VS Code 的 PORTS 面板能正常工作，也可以直接在 VS Code 底部添加 5900 端口，就不需要这条命令。

### 3.2 打开 VNC 客户端

保持隧道窗口开着，**新开一个 Mac 终端**：

```bash
open vnc://127.0.0.1:5900
```

或者：Safari 菜单 → 前往 → 连接服务器 → `vnc://127.0.0.1:5900`

成功后就能在 Mac 上看到 Isaac Sim 的完整 GUI 了（场景编辑器、属性面板、视口渲染等）。

> 如果弹出密码框，直接点连接（留空）。如果要求密码，修改 x11vnc 命令：
> `x11vnc -display :99 -forever -rfbport 5900 -passwd 你的密码 &`

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

### Q：为什么不用 WebRTC 了？

- WebRTC 视频流走 **UDP** 端口
- SSH 隧道和 VS Code 端口转发只支持 **TCP**
- featurize 控制台没有对外暴露 UDP 端口的功能
- 即使用 socat 桥接 UDP↔TCP，链路不稳定且画面黑屏
- VNC 全程走 **TCP**，SSH 隧道完美支持，画面稳定

### Q：为什么不直接公网 IP 连 VNC？

featurize 的防火墙默认拦截所有非 SSH/Jupyter 的入站端口，控制台也没有开放自定义端口映射的入口。

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
