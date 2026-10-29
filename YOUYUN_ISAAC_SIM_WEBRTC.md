# 优云智算部署 Isaac Sim 并通过 WebRTC 查看 GUI

本文以 Isaac Sim 6.0.1 standalone 包为例，介绍如何在优云智算 GPU 实例上运行
headless Isaac Sim，并通过 Isaac Sim WebRTC Streaming Client 查看完整 GUI。

这套方案不依赖 VNC 或 Xvfb。服务器只负责 RTX 渲染和视频编码，本地客户端负责显示窗口，
因此不会出现 VNC 虚拟显示下的 `vkCreateSwapchainKHR failed` 和
`backbuffers are not initialized` 循环错误。

## 一、整体结构

```text
本地电脑
  Isaac Sim WebRTC Streaming Client
          │
          │ TCP 49100  signaling
          │ UDP 47998  media stream
          ▼
优云智算实例
  Isaac Sim headless
  RTX 4090 / NVIDIA driver / NVENC
```

需要放行的端口：

| 端口 | 协议 | 用途 | 是否必需 |
|---|---|---|---|
| `49100` | TCP | WebRTC signaling | 是 |
| `47998` | UDP | WebRTC 视频流 | 是 |
| `8210` | TCP | Docker Compose 网页版查看器 | 否 |

> `8210` 只用于浏览器版 Web Viewer。使用 native WebRTC Streaming Client 时，
> 只需要 `49100/TCP` 和 `47998/UDP`。

## 二、实例要求

建议配置：

- GPU：RTX 4090 24 GB，或满足 Isaac Sim RTX 要求且带 RT Cores 的 NVIDIA GPU。
- 系统：Ubuntu 22.04 / 24.04 x86_64。
- 内存：建议 32 GB 以上。
- 存储：至少预留 50 GB，下载和解压 standalone 包会占用较大空间。
- 出站网络：允许访问 NVIDIA 下载站和 Isaac Sim 资产地址。

在实例中检查 GPU：

```bash
nvidia-smi
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
```

如果优云智算提供的是容器实例，不要在容器里执行 `apt install nvidia-driver-*`。
容器使用宿主机驱动；驱动不兼容时应在平台侧更换镜像或实例规格。

## 三、配置优云智算防火墙

在优云智算控制台找到该实例的“防火墙”“安全组”或“端口放行”页面，添加入站规则：

```text
TCP 49100  允许  本地电脑当前公网 IP
UDP 47998  允许  本地电脑当前公网 IP
```

如果需要浏览器版 Web Viewer，再增加：

```text
TCP 8210   允许  本地电脑当前公网 IP
```

只放行 TCP 端口不够。WebRTC 的 signaling 使用 TCP，但视频流使用 UDP；
如果 `47998/UDP` 未放行，客户端通常能完成连接，却会黑屏或没有画面。

出于安全考虑，不要直接把端口开放给 `0.0.0.0/0`。Isaac Sim 的流媒体端点默认没有认证，
应尽量只允许自己的公网 IP：

```bash
# 查询本地电脑当前公网 IP
curl -4 -sS https://ifconfig.me
echo
```

家庭宽带公网 IP 可能变化，重连失败时应先检查防火墙源地址是否仍匹配。

如果实例系统内部也启用了 UFW，还需要执行：

```bash
sudo ufw allow 49100/tcp comment 'Isaac Sim WebRTC signaling'
sudo ufw allow 47998/udp comment 'Isaac Sim WebRTC media'
sudo ufw status
```

如果系统没有启用 UFW，可以跳过这一步；优云智算平台防火墙仍然必须配置。

## 四、获取实例公网地址

从优云智算控制台复制实例的公网 IP 或 SSH 地址，并在实例中确认：

```bash
curl -4 -sS https://ifconfig.me
echo
```

把输出记为 `PUBLIC_IP`。如果该值与优云智算控制台显示的公网地址不同，以控制台地址为准；
客户端和 Isaac Sim 必须使用同一个对外可达地址。

```bash
export PUBLIC_IP="<优云智算实例公网IP>"
echo "$PUBLIC_IP"
```

实例重启后公网 IP 可能变化，需要同步更新防火墙规则和启动参数。

## 五、安装 Isaac Sim 6.0.1

如果实例中已经安装 Isaac Sim，可以直接跳到“启动 WebRTC Streaming”。

### 5.1 安装基础依赖

```bash
sudo apt update
sudo apt install -y unzip wget curl git \
  libgl1 libegl1 libxt6 libxrender1 libxkbcommon0 libdbus-1-3 \
  vulkan-tools
```

如果当前用户是 root，可以省略 `sudo`。

### 5.2 下载并解压

```bash
cd ~
df -h

wget -O isaac-sim-standalone-6.0.1-linux-x86_64.zip \
  "https://downloads.isaacsim.nvidia.com/isaac-sim-standalone-6.0.1-linux-x86_64.zip"

mkdir -p ~/isaacsim
unzip -q isaac-sim-standalone-6.0.1-linux-x86_64.zip -d ~/isaacsim
cd ~/isaacsim
bash post_install.sh
```

如果 `unzip` 询问是否覆盖已有文件，确认目录无误后可以选择全部覆盖。

### 5.3 验证 headless 启动

```bash
cd ~/isaacsim
./python.sh \
  standalone_examples/tutorials/getting_started/getting_started.py --headless
```

看到 `Simulation App Startup Complete` 或 `app ready`，说明 standalone 安装和 GPU
计算链路基本正常。

再检查 WebRTC 编码所需的 NVIDIA encode 库：

```bash
ldconfig -p | grep libnvidia-encode
```

正常情况下应看到 `libnvidia-encode.so`。如果缺失，说明容器或镜像没有完整透传
NVIDIA 图形/编码驱动。

## 六、启动 WebRTC Streaming

### 6.1 使用仓库脚本

在实例中下载本仓库后，执行：

```bash
chmod +x start_isaac_webrtc.sh
PUBLIC_IP="<优云智算实例公网IP>" ./start_isaac_webrtc.sh
```

如果 Isaac Sim 不在默认目录，可以覆盖路径和端口：

```bash
ISAAC_DIR="$HOME/isaacsim" \
PUBLIC_IP="<优云智算实例公网IP>" \
SIGNAL_PORT=49100 \
STREAM_PORT=47998 \
./start_isaac_webrtc.sh
```

### 6.2 手动启动

```bash
cd ~/isaacsim

export OMNI_KIT_ALLOW_ROOT="${OMNI_KIT_ALLOW_ROOT:-1}"

./isaac-sim.streaming.sh \
  --/exts/omni.kit.livestream.app/primaryStream/publicIp="${PUBLIC_IP}" \
  --/exts/omni.kit.livestream.app/primaryStream/signalPort=49100 \
  --/exts/omni.kit.livestream.app/primaryStream/streamPort=47998
```

启动过程中会先出现：

```text
Started primary stream server on signal port 49100 and stream port 47998
```

应用加载完成后应出现：

```text
Isaac Sim Full Streaming App is loaded.
```

只有看到 `Full Streaming App is loaded`，才表示 Isaac Sim 已准备好接受客户端连接。
首次启动需要编译和缓存 shader，等待几分钟属于正常现象。

### 6.3 检查监听端口

```bash
ss -lntp | grep 49100
ss -lunp | grep 47998
```

没有 `ss` 时可以安装：

```bash
sudo apt install -y iproute2
```

## 七、在本地电脑连接

1. 从 NVIDIA 官方文档下载并安装 **Isaac Sim WebRTC Streaming Client**：

   https://docs.isaacsim.omniverse.nvidia.com/6.0.1/installation/manual_livestream_clients.html

2. Windows 启动 `.exe`，macOS 打开 `.dmg` 后将应用拖入 Applications，
   Linux 使用对应的 `.deb` 安装包。
3. 启动 Isaac Sim WebRTC Streaming Client。
4. 服务器地址填写优云智算实例的 `PUBLIC_IP`。
5. 使用默认端口连接：

   - signaling：`49100/TCP`
   - media：`47998/UDP`

6. 连接成功后即可看到完整的 Isaac Sim GUI。

如果客户端只能填服务器地址，则保持默认端口，不要填写旧的 `47911`；
`47911` 是旧版 Omniverse Streaming Client 的端口，不适用于本文的 WebRTC 流程。

## 八、容器实例的启动方式

如果优云智算实例本身运行 Isaac Sim 官方容器，必须使用 host network。

```bash
docker run -it --rm \
  --name isaac-sim-webrtc \
  --entrypoint bash \
  --gpus all \
  --network=host \
  -e ACCEPT_EULA=Y \
  -e PRIVACY_CONSENT=Y \
  -e PUBLIC_IP="${PUBLIC_IP}" \
  nvcr.io/nvidia/isaac-sim:6.0.1
```

进入容器后启动：

```bash
./runheadless.sh -v \
  --/exts/omni.kit.livestream.app/primaryStream/publicIp="${PUBLIC_IP}" \
  --/exts/omni.kit.livestream.app/primaryStream/signalPort=49100 \
  --/exts/omni.kit.livestream.app/primaryStream/streamPort=47998
```

不要用 Docker bridge 网络加 `-p 49100:49100 -p 47998:47998` 代替 host network。
Isaac Sim 的 WebRTC SDK 会绑定 `ISAACSIM_HOST` 对应的真实网卡地址，端口映射通常会导致
signaling 能连上但没有视频流。

如果平台没有提供 Docker 操作权限，应使用“优云智算镜像市场中的 Isaac Sim 镜像”，或按
第五、六节直接使用 standalone 包。

## 九、连通性排查

### 9.1 客户端无法连接

在服务器确认 Isaac Sim 已加载，并检查 TCP signaling：

```bash
ss -lntp | grep 49100
```

在本地电脑测试：

```bash
nc -vz "<PUBLIC_IP>" 49100
```

不通时依次检查：

- 优云智算防火墙是否添加了 `49100/TCP`。
- 防火墙源 IP 是否等于本地电脑当前公网 IP。
- `PUBLIC_IP` 是否与控制台显示一致。
- Isaac Sim 是否已经出现 `Full Streaming App is loaded`。

### 9.2 能连接但黑屏

优先检查 UDP：

```text
47998/UDP 是否放行
```

在服务器确认监听：

```bash
ss -lunp | grep 47998
```

如果只放行了 TCP，WebRTC signaling 可能成功，但视频 media stream 无法建立。
这是“能连上但黑屏”的最常见原因。

### 9.3 一直停在加载界面

首次启动需要编译 shader，可能需要数分钟。查看日志：

```bash
grep -R "Isaac Sim Full Streaming App is loaded" \
  ~/.nvidia-omniverse/logs/Kit -n | tail -20
```

同时在服务器查看 Isaac Sim 进程是否仍在运行：

```bash
pgrep -af "isaacsim|isaac-sim"
```

### 9.4 仍出现 `backbuffers are not initialized`

先结束 VNC/Xvfb 中启动的旧 Isaac Sim：

```bash
pkill -f isaac-sim.sh || true
pkill -f isaac-sim.streaming.sh || true
```

然后从 SSH 终端重新执行：

```bash
PUBLIC_IP="<优云智算实例公网IP>" ./start_isaac_webrtc.sh
```

WebRTC 流程不会启动 Xvfb，也不需要在 VNC 桌面里再次打开 Isaac Sim。如果仍报
`vkCreateSwapchainKHR failed`，应检查 NVIDIA Vulkan 驱动和容器 GPU 透传，
而不是继续修改 VNC。

### 9.5 端口被占用

```bash
ss -lntup | grep -E "49100|47998|8210"
```

结束旧 Isaac Sim 进程后重新启动。多实例部署时，每个实例必须使用不同的
`SIGNAL_PORT` 和 `STREAM_PORT`，并分别配置防火墙。

## 十、推荐检查顺序

```bash
nvidia-smi
ldconfig -p | grep libnvidia-encode
curl -4 -sS https://ifconfig.me
ss -lntp | grep 49100
ss -lunp | grep 47998
```

全部正常后，再启动本地 Isaac Sim WebRTC Streaming Client。

## 十一、安全注意事项

- Isaac Sim WebRTC 流媒体端点默认不提供认证或加密。
- 防火墙只允许自己的公网 IP，避免对外开放全部地址。
- 使用完毕后关闭 WebRTC 端口或停止实例。
- 如需公开访问，应增加 VPN、反向代理、TLS 和身份认证。

## 参考

- Isaac Sim WebRTC Streaming Client：
  https://docs.isaacsim.omniverse.nvidia.com/6.0.1/installation/manual_livestream_clients.html
- Isaac Sim 容器部署与 Streaming 端口：
  https://docs.isaacsim.omniverse.nvidia.com/6.0.1/installation/install_container.html
- Isaac Sim 系统要求：
  https://docs.isaacsim.omniverse.nvidia.com/6.0.1/installation/requirements.html
- Isaac Sim 云端部署示例：
  https://docs.isaacsim.omniverse.nvidia.com/6.0.1/installation/install_advanced_cloud_setup_aws.html
