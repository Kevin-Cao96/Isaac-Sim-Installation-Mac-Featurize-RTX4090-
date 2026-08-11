# Isaac Sim / Isaac Lab 云服务器部署指南

> 基于 2026-07 ~ 2026-08 实测经验整理：阿里云 ECS（A10）、AutoDL 容器、AutoDL Ubuntu-Nvidia 虚机。
> 覆盖 Isaac Sim 6.0.1 + Isaac Lab 3.0.0-beta2 的安装、常见问题与解决方案、平台对比。

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

现象：`Installed driver: 570.153.02`，`The unsupported driver range: [570.00, 570.158.01)`。

说明：headless 物理仿真不受影响；需要 RTX 渲染（摄像头/流媒体）时建议升级驱动至 580.95.05+。

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

## 五、常见工作流

### 5.1 headless 训练（默认）

```bash
cd ~/IsaacLab && bash isaaclab.sh -p scripts/reinforcement_learning/train.py \
  --task Isaac-Lift-Cube-Franka-v0 --num_envs 256 --rl_library rsl_rl
```

### 5.2 观察 GUI

云服务器无显示器。可选：
- Omniverse Streaming Client（`isaac-sim.streaming.sh` + WebRTC Streaming Client）
- VNC（需要图形环境）
- 本地安装 Isaac Sim 直接跑 GUI（最简单，但需要 RTX 显卡）

headless 训练时建议直接看终端指标（`Mean reward`、`success_rate`），无需 GUI。

### 5.3 查看关节/资产名

```bash
# 在脚本内打印
print(env.unwrapped.scene["robot"].data.joint_names)
```

---

## 六、经验总结

- 安装 Isaac Sim 用官方 standalone 包最稳，pip 安装容易缺扩展。
- Isaac Lab 必须通过 `isaaclab.sh` 启动，不要手写 Python。
- conda 环境是最大的坑：安装和运行前先 `conda deactivate`。
- 国内网络务必先换好 pip / apt 源，再开始下载大文件。
- 抢占式实例省钱但不可靠，重要环境要及时备份。
- 遇到报错先看最顶部的 `File "... line N"`，定位到具体行再解决。

---

## 参考

- Isaac Sim 官方 Quick Install：https://docs.isaacsim.omniverse.nvidia.com/latest/installation/quick-install.html
- Isaac Sim Standalone Examples：https://docs.isaacsim.omniverse.nvidia.com/latest/introduction/standalone_examples_list.html
- Isaac Lab：https://github.com/isaac-sim/IsaacLab
