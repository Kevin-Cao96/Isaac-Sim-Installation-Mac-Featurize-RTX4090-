# Isaac Sim / Isaac Lab 云服务器部署指南

> 基于 2026-07 ~ 2026-08 实测经验整理：阿里云 ECS（A10）、AutoDL 容器、AutoDL Ubuntu-Nvidia 虚机。
> 覆盖 Isaac Sim 6.0.1 + Isaac Lab 3.0.0-beta2 的安装、常见问题与解决方案、平台对比、GUI 远程使用（RTX Streaming / VNC）。

---

## 一、平台对比与选型

### 1.1 概览

| 平台 | 实例形态 | GPU 示例 | 价格量级 | root | 适合场景 |
|---|---|---|---|---|---|
| 阿里云 ECS | 虚机 | A10 24G | 较高（包月/按量） | root | 长期稳定、需要弹性 IP |
| AutoDL | 容器 | 3080Ti 12G / 4090 24G / A800 | 低（按小时） | root | 短期训练、按需开机 |
| AutoDL | Ubuntu-Nvidia 虚机 | 3080Ti 12G / 4090 24G | 低（按小时） | ubuntu+sudo | 接近裸机、需要完整系统 |
| Featurize | 容器/虚机 | RTX4090 等 | 中等 | 视实例而定 | 未实测，参考官方文档 |

### 1.2 关键决策点

- **便宜优先且可随时重装**：AutoDL 容器，按小时计费，关机不收费。
- **需要长期稳定环境**：阿里云 ECS，避免抢占式实例被强制回收导致数据丢失。
- **需要完整系统权限/裸机行为**：AutoDL Ubuntu-Nvidia 虚机（用户 `ubuntu`，用 `sudo -i` 提权）。
- **需要远程看 GUI**：云服务器默认无显示器，需配合 RTX Streaming 或 VNC（见第五章）。
- **注意**：AutoDL 容器支付可能要求高校认证/高校邮箱；抢占式实例在资源紧张时会被强制回收，系统盘数据会清空。

---

## 二、Isaac Sim 安装（standalone 包）

推荐官方 standalone 包：`isaac-sim-standalone-6.0.1-linux-x86_64.zip`（约 12 GB，解压后更大，需预留 50 GB+）。

### 2.1 准备系统依赖

```bash
apt update
apt install -y unzip git wget \
  libgl1 libgl1-mesa-dev libegl1 libxt6 \
  libxrender1 libxkbcommon0 libdbus-1-3
```

> 若 `apt update` 报镜像同步错误（如 `File has unexpected size`），换阿里云源：

```bash
sed -i 's|mirrors.ucloud.cn/ubuntu|mirrors.aliyun.com/ubuntu|g' /etc/apt/sources.list
apt update
```

> 若报 `ModuleNotFoundError: No module named 'apt_pkg'`，装 `python3-apt`：

```bash
apt install -y python3-apt
```

### 2.2 下载、解压、后处理

```bash
cd ~
wget -O isaac-sim-standalone-6.0.1-linux-x86_64.zip \
  "https://downloads.isaacsim.nvidia.com/isaac-sim-standalone-6.0.1-linux-x86_64.zip"
```

国内网络会自动重定向到 `downloads.isaacsim.nvidia.cn`，速度通常更快。

```bash
mkdir -p ~/isaacsim
unzip -q isaac-sim-standalone-6.0.1-linux-x86_64.zip -d ~/isaacsim
cd ~/isaacsim && bash post_install.sh
```

### 2.3 验证

```bash
cd ~/isaacsim && ./python.sh standalone_examples/tutorials/getting_started/getting_started.py --headless
```

看到 `Simulation App Startup Complete` / `app ready` 即成功。

---

## 三、Isaac Lab 安装

### 3.1 克隆仓库并创建符号链接

```bash
cd ~
git clone https://github.com/isaac-sim/IsaacLab.git
cd IsaacLab
git checkout release/3.0.0-beta2
ln -s ~/isaacsim _isaac_sim
```

### 3.2 创建环境脚本（重要）

`isaaclab.sh` 会读取 `_isaac_sim/setup_conda_env.sh`，缺少会导致环境变量未导出：

```bash
cat > ~/IsaacLab/_isaac_sim/setup_conda_env.sh << 'EOF'
#!/bin/bash
export ISAAC_SIM_PATH="${ISAACLAB_PATH}/_isaac_sim"
export ISAAC_SIM_PYTHON="${ISAAC_SIM_PATH}/python.sh"
EOF
chmod +x ~/IsaacLab/_isaac_sim/setup_conda_env.sh
```

### 3.3 安装

```bash
cd ~/IsaacLab && bash isaaclab.sh --install
```

> **重要**：不要在 conda 环境里跑安装。`isaaclab.sh` 检测到 `CONDA_PREFIX` 时会优先用 conda Python，导致依赖装错位置。
> 先 `conda deactivate`，确认 `CONDA_PREFIX` 为空。

### 3.4 验证

```bash
cd ~/IsaacLab && bash isaaclab.sh -p scripts/tutorials/00_sim/create_empty.py --headless
```

看到 `[INFO]: Setup complete...` 即成功。

---

## 四、常见问题与解决方案

### 4.1 `isaaclab.sh` 用了 conda Python

现象：`[INFO] Using Python: "/usr/local/miniconda3/bin/python"`，且 `import lazy_loader` 报错。

解决：

```bash
conda deactivate
cd ~/IsaacLab && bash isaaclab.sh --install
```

### 4.2 pip 损坏：`cannot import name 'BuildDependencyInstallError'`

Isaac Sim 自带 pip 可能版本损坏。修复：

```bash
rm -rf ~/IsaacLab/_isaac_sim/kit/python/lib/python3.12/site-packages/pip*
~/IsaacLab/_isaac_sim/kit/python/bin/python3 -m ensurepip --upgrade
```

### 4.3 `omniverseclient` 找不到

现象：`Could not find a version that satisfies the requirement omniverseclient==2.71.1.7015`。

原因：默认/清华 PyPI 源没有 NVIDIA 私有包。

解决（配好源后重跑安装）：

```bash
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
pip config set global.extra-index-url https://pypi.nvidia.com
```

### 4.4 torch 下载极慢

916 MB 的 `torch-2.10.0+cu128` wheel，直连 PyPI 可能 100-200 KB/s。

解决：配清华源后重跑 `bash isaaclab.sh --install`；若仍慢可指定国内 PyTorch 镜像：

```bash
~/IsaacLab/_isaac_sim/kit/python/bin/python3 -m pip install torch==2.10.0+cu128 \
  --index-url https://mirrors.aliyun.com/pytorch-wheels/cu128/
```

### 4.5 缺 `libGL.so.1` / `libXt.so.6`

现象：启动时大量 `Could not load the dynamic library ... libGL.so.1` 或 `libXt.so.6`。

解决：

```bash
apt install -y libgl1 libgl1-mesa-dev libegl1 libxt6 libxrender1 libxkbcommon0 libdbus-1-3
```

### 4.6 `RuntimeError: Explicitly requested visualizer(s) ['kit'] could not be configured`

原因：部分官方教程脚本默认启用 `kit` visualizer，但 `isaaclab_visualizers[kit]` 未安装。

解决（headless 场景）：

```bash
bash isaaclab.sh -p scripts/xxx.py --viz none
```

若脚本内写死 `parser.set_defaults(visualizer=["kit"])`，注释该行后再加 `--viz none`。

### 4.7 驱动版本警告

现象：

```
Installed driver: 570.153.02
The unsupported driver range: [570.00, 570.158.01)
The recommended drivers: 580.95.05
rtx driver verification failed
```

说明：headless 物理仿真不受影响；**RTX 渲染（GUI、流媒体、摄像头截图）会失败**。

解决（需要跑 GUI 时）：升级 NVIDIA 驱动到 580+。推荐用 apt：

```bash
# 查找可用驱动版本
apt-cache search nvidia-driver | grep -E "^nvidia-driver-[0-9]+" | tail -10

# 安装最新版（如 nvidia-driver-610）
apt install -y nvidia-driver-610

# 重启
reboot
```

重启后验证：

```bash
nvidia-smi | head -4
```

注意事项：
- 云服务器装驱动可能短暂断连，SSH 断开属正常，等待 1-2 分钟重连。
- 若实例 IP/端口变化，以平台控制台显示为准。
- NVIDIA 官网手动下载 .run 文件常遇到 403/无效链接，apt 是最稳的路径。

### 4.8 抢占式实例被强制回收

现象：实例消失，系统盘数据清空，需要重装。

预防：
- 长期学习/训练用普通实例，不要选抢占式。
- 环境打包备份到数据盘/云存储。
- 被回收后按本文档重新执行安装清单（约 30-60 分钟）。

### 4.9 解压时提示 `replace ...?`

解压已存在的文件时 unzip 会询问。输入 `A`（全部覆盖）继续。

### 4.10 运行脚本时 `python: command not found`

不要直接执行 `python`，Lab 脚本一律通过：

```bash
cd ~/IsaacLab && bash isaaclab.sh -p <script.py> --headless
```

---

## 五、远程 GUI 使用（RTX Streaming / VNC）

云服务器没有物理显示器。要看 Isaac Sim 的 3D 画面，有两条路：

### 5.1 Omniverse RTX Streaming（推荐，官方方案）

原理：服务器用 `isaac-sim.streaming.sh` 启动带流媒体的 Kit 应用，客户端用 Omniverse Streaming Client 连接观看。

**服务器端启动：**

```bash
cd ~/isaacsim && OMNI_KIT_ALLOW_ROOT=1 ./isaac-sim.streaming.sh
```

- 如果以 root 运行，必须加 `OMNI_KIT_ALLOW_ROOT=1`，否则报错：
  `Omniverse Kit cannot be run as the root user without the --allow-root flag`。
- 启动成功后日志会显示 `Isaac Sim Full Streaming App is loaded.` 和 `app ready`。

**客户端连接：**

1. 在本地电脑安装 **Omniverse Streaming Client**（NVIDIA 官网下载，支持 Windows/macOS）。
2. 打开 Streaming Client，输入服务器 IP 和端口（默认 `47911` 或页面提示的端口）。
3. 连接后即可看到 Isaac Sim 的完整 GUI。

**在流媒体画面里跑自己的脚本：**

- 打开 GUI 里的 `Window -> Script Editor`，粘贴代码并运行（无需重复创建 SimulationApp，引擎已在运行）。
- 或把脚本传给流媒体实例：

```bash
cd ~/isaacsim && OMNI_KIT_ALLOW_ROOT=1 ./isaac-sim.streaming.sh \
  --/app/standalone/script=/root/xxx.py
```

**重要限制：**

- **普通 standalone 脚本（自己创建 `SimulationApp`）无法直接显示在流媒体画面里**——流媒体是独立进程，两者不互通。
- 要在流媒体画面里看效果，要么用 Script Editor，要么把脚本改成不创建 `SimulationApp` 的形式。
- 流媒体（RTX 渲染）需要驱动 580+（见 4.7），否则黑屏或报 `rtx driver verification failed`。
- 需要在云平台安全组/防火墙放行对应端口。

### 5.2 VNC（备选方案）

在服务器上装图形桌面 + VNC Server，本地用 VNC Viewer 连接整个桌面，再在桌面里启动 Isaac Sim。

```bash
# 服务器端
apt install -y xfce4 xfce4-goodies tigervnc-standalone-server tigervnc-common
vncpasswd            # 设置 VNC 密码
vncserver :1         # 启动，端口 5901

# 本地连接
# VNC Viewer 连 服务器IP:5901，进入桌面后启动 Isaac Sim GUI
```

优点：看到完整桌面；缺点：占用资源大、画面延迟高，不如 Streaming 流畅。RTX Streaming 更适合仿真场景。

### 5.3 选择建议

| 需求 | 推荐 |
|---|---|
| 看仿真 3D 画面、跑官方例子 | RTX Streaming |
| 偶尔调试、看完整桌面 | VNC |
| 只跑训练/看指标 | 都不需要，headless + 终端日志即可 |

---

## 六、常见工作流

### 6.1 headless 训练（默认）

```bash
cd ~/IsaacLab && bash isaaclab.sh -p scripts/reinforcement_learning/train.py \
  --task Isaac-Lift-Cube-Franka-v0 --num_envs 256 --rl_library rsl_rl
```

### 6.2 查看关节/资产名

```bash
# 在脚本内打印
print(env.unwrapped.scene["robot"].data.joint_names)
```

---

## 七、经验总结

- 安装 Isaac Sim 用官方 standalone 包最稳，pip 安装容易缺扩展。
- Isaac Lab 必须通过 `isaaclab.sh` 启动，不要手写 Python。
- conda 环境是最大的坑：安装和运行前先 `conda deactivate`。
- 国内网络务必先换好 pip / apt 源，再开始下载大文件。
- 抢占式实例省钱但不可靠，重要环境要及时备份。
- 遇到报错先看最顶部的 `File "... line N"`，定位到具体行再解决。
- 要跑 GUI/流媒体，先确认驱动 ≥ 580，否则 RTX 渲染失败。

---

## 参考

- Isaac Sim 官方 Quick Install：https://docs.isaacsim.omniverse.nvidia.com/latest/installation/quick-install.html
- Isaac Sim Standalone Examples：https://docs.isaacsim.omniverse.nvidia.com/latest/introduction/standalone_examples_list.html
- Isaac Lab：https://github.com/isaac-sim/IsaacLab
- Omniverse Streaming Client：https://www.nvidia.com/en-us/omniverse/download/
