<div align="center">

# 🧪 Daedalus

**RoboMaster 视觉算法验证模拟器**

[![Rust](https://img.shields.io/badge/Rust-Stable-orange.svg?style=for-the-badge&logo=rust)](https://www.rust-lang.org/)
[![Bevy](https://img.shields.io/badge/Bevy-Engine-3A3A3A.svg?style=for-the-badge&logo=bevy)](https://bevyengine.org/)
[![ROS2](https://img.shields.io/badge/ROS2-Optional-22314E.svg?style=for-the-badge&logo=ros)](https://www.ros.org/)

</div>

## 1. 项目做什么

Daedalus 是一个本地图形模拟器，用虚拟场景、机器人、装甲板和能量机关为视觉算法提供图像与运动目标。可以只用键盘或手柄操作，也可以通过 Talos IPC 或 ROS 2 接入外部自瞄算法，接收云台目标与模拟开火建议。

**第一次使用的完整顺序**：优先按第 3 节的项目内 Conda 流程运行 `./start.sh`，打开默认 Talos 模拟器 → 第 5.3 节逐项体验功能。无需接口时用 `./start.sh --local`；需要算法接入时再阅读第 7 节 Talos 或第 4.3/6 节 ROS。只测试已有视频则用第 4.4 节，第 4.5 节给出 Linux 打包步骤。不要从同时启用所有功能开始。

当前源码实现了：

- **场景与目标**：加载 GLB 场地、前哨站、能量机关、科技核心及装甲板模型，提供灯光、外观和部分状态变化。
- **机器人控制**：己方步兵、蓝方步兵与英雄假人；底盘移动和旋转、云台转动、假人切换，以及假人底盘倾斜。
- **物理与发射**：Avian3D 刚体、重力、碰撞、弹丸和飞镖发射；可配置空气阻力与风。默认弹丸参数为 17 mm，并非独立实现了英雄 42 mm 弹道。
- **采集与联调**：虚拟相机 RGB 图像、相机内参和位姿；Talos 共享内存；可选 ROS 图像、TF、深度派生点云、科技核心状态与云台命令。
- **辅助操作**：三种视角、截图、FPS/帧时间诊断、可选 Inspector、配置文件监听；独立视频 mock 可测试 Talos 视频输入和命令接收。

这不是完整裁判系统或自主导航系统，也不提供现成的目标检测算法。`src/telemetry/` 尚未接入主程序，不能把当前版本当作已经完成的自动标注或数据集导出工具。`P` 键生成的是静态 UAV 模型，并非完整飞行仿真。命中统计有特定的能量机关命中逻辑，不代表全部机器人装甲板计分。模拟结果不等于实机跟踪、弹道校准或射击命中验收。

### 技术栈与源码入口

| 内容 | 实现与入口 |
| --- | --- |
| 应用、场景与调度 | Rust edition 2024、Bevy 0.19；`src/main.rs`、`src/scene.rs` |
| 刚体与运动 | Avian3D 0.7；`src/systems/input.rs`、`src/systems/projectile.rs` |
| 键盘、手柄与云台跟踪 | `src/systems/controller.rs`、`src/systems/gimbal_pid.rs` |
| 目标模型与机制状态 | `src/robomaster/`、`crates/exact/`、`assets/` |
| 配置与文件监听 | Serde、TOML、notify；`config.toml`、`src/config.rs` |
| 渲染采集 | Bevy 离屏渲染与 GPU 回读；`src/capture/`、`src/capture.rs` |
| Talos IPC | memmap2、共享内存协议；`src/talos/`、`crates/talos-ipc/` |
| 可选 ROS 2 | r2r、自定义消息包；`src/ros2/`、`rm_interfaces/` |
| 可选视频 mock | ffmpeg-next；`src/bin/talos_gimbal_mock_server.rs` |
| 可选 macOS 渲染优化 | MetalFX；`crates/bevy_metalfx/` |

依赖和功能开关以 `Cargo.toml`、`Cargo.lock` 为准。下文依据当前源码整理；命令是部署操作说明，不是本次已构建或运行成功的记录。当前未固定 Rust 工具链，也没有完整的一键部署脚本或容器配方。

## 2. 先选择运行模式

| 目的 | Cargo 功能开关 | 是否需要外部环境 |
| --- | --- | --- |
| 先看场景、手动操作 | `--no-default-features` | Rust、图形与音频/输入依赖；不需要 ROS 或 Talos 客户端 |
| 与 Talos 算法联调 | 默认启用 `talos` | 上述环境，以及兼容本仓 IPC 协议的外部消费者 |
| 与 ROS 自瞄联调 | `--no-default-features --features ros2` | 上述环境、ROS 2、libclang；**先执行第 4.3 节的接口依赖修正**，再构建 overlay |
| 用已有视频测试 Talos | `--no-default-features --features talos,ffmpeg`，运行 mock binary | Rust、FFmpeg 开发库和 Talos 消费者；不启动三维场景 |

**目前不要同时启用 `ros2` 与 `talos`，也不要用 `--all-features`。** `src/main.rs` 的 `should_enable_talos_plugin(_app: &App)` 在 ROS 条件分支中引用了不存在的 `app`；这是源码可见的问题，本次没有编译复现或修复。仅写 `--features ros2` 会保留默认的 `talos`，因此 ROS 命令必须带 `--no-default-features`。环境变量 `DAEDALUS_FORCE_TALOS_CAPTURE` 不能修复这个问题。

## 3. 部署准备

### 项目内 Conda 隔离与一键启动（推荐）

此入口面向 **Linux x86_64 桌面、glibc >= 2.34（推荐 Ubuntu 22.04 或更新版本）**，保留默认的 `talos` feature；不启用 ROS 2 或 FFmpeg 的 Rust feature。Miniforge / Conda 只负责创建项目专用环境，不复用 `base`、`25shaobing_nav` 或当前已激活的环境。先准备本机 GPU 驱动及可用桌面，再执行：

```bash
cd "$HOME/Desktop/bevy_robomaster_simulator"
./start.sh
```

脚本自动定位自己所在目录，因而也可在其他目录执行 `/实际项目路径/start.sh`。它会安装锁定依赖、增量构建并打开窗口；首次需要网络、可用磁盘和较长编译时间，后续直接复用环境与构建缓存。操作前点击模拟器窗口，确保键盘焦点在它上面；关闭窗口即可退出。不要同时运行另一个 Talos 图像生产者或 mock。

本机默认 Talos 模式已经完成实际构建、窗口/模型加载、控制与发射、IPC 同步及重复启动/退出检查，记录见 `doc/20261013_conda_startup.md`。首次 Rust 编译耗时约 36 分钟，之后两次增量构建为 0.51 秒和 0.25 秒；当前环境、下载缓存与产物合计约 6 GiB，仅是本机实测，不是所有机器的时长/空间保证。该记录不覆盖 ROS、FFmpeg mock、本地无接口模式构建、实体手柄或外部算法闭环。

前提是已安装 Conda。默认检测 `$HOME/miniforge3`、`$HOME/miniconda3`、`$HOME/anaconda3`，最后检查 PATH 中的可执行文件；自定义安装路径使用：

```bash
CONDA_EXE=/实际安装路径/bin/conda ./start.sh
```

本机已有 `/home/wang/miniforge3/bin/conda`，不需要重新安装 Miniforge。其他机器没有 Conda 时，先按 [Miniforge 官方安装说明](https://github.com/conda-forge/miniforge#install) 安装对应架构的发行版；脚本不会擅自修改系统软件或下载执行另一个安装器。

隔离目录与依赖来源：

| 路径 | 内容 |
| --- | --- |
| `environment.yml` | 直接依赖清单：Rust 1.95.0、GCC/G++、pkg-config、ALSA 及插件、udev、X11、Wayland、Vulkan loader |
| `conda-linux-64.lock` | conda-forge 的完整精确包 URL、build 和 MD5；启动器以此安装，不每次重新解析版本 |
| `.runtime/conda/` | 本项目 Conda 环境；不向其他环境安装包 |
| `.runtime/conda-pkgs/` | 项目专用 Conda 下载缓存 |
| `.runtime/cargo/` | 项目专用 Cargo registry/cache，不复用其他项目的 Cargo 缓存 |
| `.runtime/target/talos/`、`.runtime/target/local/` | 按 feature 隔离的开发配置产物 |
| `.runtime/build-talos.log`、`.runtime/build-local.log` | 最近一次对应模式的构建日志 |

启动前清除继承的 PATH、`LD_LIBRARY_PATH`、Python/ROS/Conda/编译器配置，只保留桌面连接、代理、终端和显式 `RUST_LOG` 等必要变量，再激活项目环境。Rust、Cargo、C/C++ 编译器和 pkg-config 路径都来自该环境。使用单任务编译、关闭开发配置调试符号和 incremental，以降低磁盘、内存占用；不改变源码中的仿真参数。

**隔离边界**：Conda 不隔离操作系统内核、glibc、GPU 驱动、X11/Wayland 服务、声音服务或 `/tmp` IPC。图形驱动必须由宿主机提供，不能把此方案当作容器或实机通信隔离。Conda 自身可能向用户环境登记文件注册这个 prefix，但不改其他环境里的依赖。此锁不适用于 macOS、Windows、ARM，也不是 ROS/FFmpeg mock 模式的配套环境。ALSA 插件的传递依赖包含 FFmpeg 9 原生库；这不代表已启用、编译或验证 `ffmpeg-next` 8 的视频 mock。该可选模式仍须准备匹配版本及绑定生成依赖并独立验证。

Cargo 的项目及祖先目录 `.cargo/config` / `.cargo/config.toml` 仍遵循 Cargo 原生查找规则，不等同于继承的环境变量；本机已核对这些位置不存在此类配置。以后新增这类文件时，要核对 source、target、linker 与编译选项的覆盖关系，不能仅凭设置了私有 `CARGO_HOME` 就宣称忽略了所有目录级配置。

常用入口：

```bash
./start.sh --help                  # 不安装、不构建
./start.sh --setup-only            # 只建立并检查隔离环境
./start.sh --check                 # 检查现有环境，不安装、不构建
./start.sh --build-only            # 构建默认 Talos 模式，不开窗口
./start.sh --run-only              # 只运行已有默认产物，不安装、不构建
./start.sh --local                 # 构建并启动无外部接口模式
./start.sh --local --run-only      # 只运行已有本地模式产物
```

`--setup-only`、`--build-only`、`--run-only`、`--check` 不能同时使用。非图形终端可 `--build-only`，但 `--run-only` 不会转成 headless 模式。Agent 运行默认入口或 `--build-only` 仍需遵守 `AGENTS.md` 的构建授权；已有授权在同一任务内持续有效。

脚本对环境锁和实际已安装包列表做一致性检查。不要向专用环境追加其他项目依赖；锁变化或环境被修改时会拒绝继续。确需升级时，先更新 `environment.yml`、重新解析并导出完整 explicit 锁，再备份/移走旧 `.runtime/conda/` 与 `.runtime/conda-spec.sha256`，重新安装和验证；不要仅改清单而留下旧锁。复制或移动项目会改变 Conda prefix 与二进制 rpath，必须重建环境和产物，不能直接复制 `.runtime` 当作可移植发行包。

Talos 启动前如果 `/tmp/talos_ipc_meta` 或 `/tmp/talos_ipc_image_pool` 已存在，脚本拒绝启动，不会自动删除、截断它们。先核对原进程、文件所有者和会话状态，再由操作者处理确认属于自己的遗留文件。同一项目还有文件锁防止重复安装、构建和运行；不同项目的 Talos 固定路径仍需人工协调。

后面的系统依赖 / rustup 流程是**绕过此脚本的独立部署方案**；使用 Conda 入口不需要再安装另一套系统编译工具链。不要在已激活的其他环境中照搬直接 Cargo 命令来替代隔离入口。

### 3.1 Rust 与图形环境

下面的可复制流程以 **Ubuntu 22.04 桌面 + Bash + 本地 GPU** 为部署基线；ROS 使用 Humble。所有代码块使用 Bash，zsh 用户先运行 `bash` 进入 Bash，后续 source 对应 `.bash` 文件。其他平台只说明实现边界，不把 Linux 命令当作跨平台安装流程。

先确认项目已经放到本地，把下面的路径改成实际位置。本机项目位于 `$HOME/Desktop/bevy_robomaster_simulator`。后续“项目根目录”均指这个目录，每个新终端先进入该目录。

```bash
set -eo pipefail
export PROJECT_ROOT="$HOME/Desktop/bevy_robomaster_simulator"
cd "$PROJECT_ROOT"
test -f Cargo.toml && test -f Cargo.lock && test -f config.toml && test -d assets
```

主模拟器需要图形桌面和可用 GPU 驱动；SSH 无显示环境不能直接照搬桌面启动流程。WSL 需要可用的 WSLg/显示与图形驱动。`preview.enabled = false` 不是 headless 模式，也没有保证可用的 CPU 软件渲染路径。

安装基础编译、窗口、音频和输入依赖：

```bash
sudo apt-get update
sudo apt-get install build-essential curl ca-certificates python3 pkg-config \
  libx11-dev libasound2-dev libudev-dev libxkbcommon-x11-0 \
  libwayland-dev libxkbcommon-dev libvulkan1 vulkan-tools psmisc
```

**Rust 不能只要求支持 edition 2024。** 锁定的 Bevy 0.19.0 在 [该版本 manifest](https://github.com/bevyengine/bevy/blob/v0.19.0/Cargo.toml) 中要求 Rust **1.95.0**；本仓整体 MSRV 未单独声明，但至少不能低于此版本。以下选择 stable 工具链，并检查实际生效版本；旧的 1.91.x 不能满足这条依赖要求。

```bash
set -eo pipefail
if [ -f "$HOME/.cargo/env" ]; then
  source "$HOME/.cargo/env"
fi
if ! command -v rustup >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 --fail --show-error --silent \
    https://sh.rustup.rs | sh -s -- -y --profile minimal
  source "$HOME/.cargo/env"
fi
rustup update stable
rustup override set stable
rustc --version
cargo --version
python3 - <<'PY'
import subprocess
version = subprocess.check_output(['rustc', '--version'], text=True).split()[1]
numbers = tuple(int(part) for part in version.split('-')[0].split('.'))
if numbers < (1, 95, 0):
    raise SystemExit('Rust 必须 >= 1.95.0，请检查 PATH 和 rustup override')
print('Rust version prerequisite satisfied:', version)
PY
```

rustup 安装来源为 [Rust 官方安装说明](https://rust-lang.org/tools/install/)；override 只选择当前项目目录的工具链，不改 `Cargo.toml` 或锁文件。系统依赖参考 [Bevy 0.19 Linux 依赖说明](https://github.com/bevyengine/bevy/blob/v0.19.0/docs/linux_dependencies.md)。如果其他锁定依赖还要求更高版本，以 Cargo 的具体错误为准更新 stable，不降级依赖、不删除 `Cargo.lock`。

Intel/AMD 的 Ubuntu 原生 Mesa 环境可安装 `mesa-vulkan-drivers`；NVIDIA 使用与 GPU 匹配的 Ubuntu/厂商驱动，不盲目混装。WSL 使用 Windows 主机支持 WSLg 的驱动。驱动准备好后，在准备运行模拟器的图形会话检查：

```bash
printf 'DISPLAY=%s WAYLAND_DISPLAY=%s\n' "${DISPLAY:-}" "${WAYLAND_DISPLAY:-}"
vulkaninfo --summary
```

应能看到有效显示会话和 GPU 信息，而不是仅有加载失败日志；这只是图形环境预检查，最终仍需确认模拟器完成渲染。

macOS 需要 Rust 与原生编译环境；源码包含 MetalFX 可选优化，但是否可用取决于系统和 GPU。`metalfx_frame_generation` 需要 macOS 26 或更新版本及支持的设备，其他环境会忽略/退回常规路径。仓库没有提供原生 Windows 的完整部署验证记录；Talos 固定 `/tmp` 路径也需要单独适配验证。

### 3.2 项目文件与工作目录

后续命令全部从**项目根目录**执行，即同时包含以下文件的目录：

```text
Cargo.toml
Cargo.lock
config.toml
assets/
src/
crates/
third_party/r2r_msg_gen/
rm_interfaces/
```

保留 `assets/` 中的 GLB 模型和 OGG 音效，不要只复制 `src/`。配置从当前工作目录的 `config.toml` 读取；缺失或格式错误时会记录日志并使用代码默认值，未必与仓库配置一致。统一从项目根目录启动；如果绕过 Cargo 直接运行 executable，还要按第 4.5 节显式指定资产根目录，不能把配置路径与 Bevy 的资产路径视为同一规则。

隔离部署优先使用 `start.sh`。下面的直接 Cargo 命令用于已经自行配置工具链的独立部署。`cargo-wrapper.sh` 引用了当前仓库未提供的 `env.sh` / `build.sh`，其 `--no-r2r` / `--no-ros2` 分支还映射到未声明的 `no-r2r` feature，不能作为可靠的一键入口。

## 4. 构建与启动

首次运行会下载依赖并编译；`cargo run` 也会触发构建。`--locked` 用于保持现有锁文件；如果报错，不要把删除锁文件作为默认解决方式。以下命令需要在准备好环境后由操作者执行；Agent 执行构建仍须遵守 `AGENTS.md` 的授权限制。

### 4.1 最小启动：仅本地仿真

不依赖 ROS，也不创建 Talos IPC，适合第一次确认场景和控制。

```bash
set -eo pipefail
cargo run --locked -p daedalus --bin daedalus --release --no-default-features
```

等场地碰撞体和机器人加载完成，再操作。默认控制己方步兵，初始活动假人为蓝方英雄，`Tab` 可切换另一假人。窗口中的 `auto-aim`、发射统计和控制提示帮助确认当前模式。关闭窗口退出；日志里的 panic、资产加载失败或退出异常不能视作成功启动。

成功条件：日志出现 `scene loaded`，窗口有场地和机器人，按 `W/A/S/D` 可移动、方向键可转云台、`Tab` 可切换假人。此模式不产生 ROS topic 或 Talos 文件；`F5` 只是改变控制模式，没有外部接口时不会凭空产生自瞄目标，应保持关闭。

### 4.2 默认 Talos 模式

先检查第 7 节的固定映射文件是否被其他进程占用；基础依赖中的 `psmisc` 提供 `fuser`。若显示 PID，先确认是哪次实验以及是否已经退出，不启动第二个生产者，不强杀或删除他人的映射：

```bash
for mapping in /tmp/talos_ipc_meta /tmp/talos_ipc_image_pool; do
  if [ -e "$mapping" ]; then
    ls -l "$mapping"
    fuser -v "$mapping" || true
  fi
done
```

```bash
set -eo pipefail
cargo build --locked -p daedalus --bin daedalus --release
cargo run --locked -p daedalus --bin daedalus --release
```

不接消费者时也可手动观察场景；外部图像发布的背压行为见第 7 节。先启动模拟器创建映射文件，再启动协议兼容的外部算法客户端。客户端部署不包含在本仓命令中，不应凭项目名称假定任意 Talos 版本都兼容。

### 4.3 ROS 2 模式

这里给出**安装 ROS → 修正接口依赖 → 生成接口 → 构建/启动模拟器 → 检查消息**的完整顺序。已安装 Humble 的机器跳过第一步。此流程不要求同时启用 Talos，也不要求安装外部机器人驱动。

**第一步：全新 Ubuntu 22.04 安装 Humble。** 以下操作添加官方 ROS apt 源并安装系统包，执行前查看 apt 的变更清单。非 Ubuntu 22.04 不执行此块；其他发行版按对应 ROS 安装指南准备环境。

```bash
set -eo pipefail
. /etc/os-release
if [ "$ID" != ubuntu ] || [ "$VERSION_ID" != 22.04 ]; then
  printf '%s\n' '此安装块仅用于 Ubuntu 22.04，请按目标系统选择 ROS 安装方法' >&2
  exit 1
fi
sudo apt-get update
sudo apt-get install curl ca-certificates locales software-properties-common
sudo locale-gen en_US.UTF-8
export LANG=en_US.UTF-8
sudo add-apt-repository universe
ROS_SOURCE_VERSION="$(curl --fail --silent --show-error --location \
  https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
  | python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])')"
ROS_SOURCE_DEB="$(mktemp --suffix=.deb)"
curl --fail --show-error --location \
  "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_SOURCE_VERSION}/ros2-apt-source_${ROS_SOURCE_VERSION}.jammy_all.deb" \
  --output "$ROS_SOURCE_DEB"
sudo dpkg -i "$ROS_SOURCE_DEB"
sudo apt-get update
sudo apt-get install --only-upgrade systemd udev
sudo apt-get install ros-humble-ros-base
test -f /opt/ros/humble/setup.bash
```

源与系统包安装步骤依据 [ROS 2 Humble 官方安装说明](https://docs.ros.org/en/humble/Installation/Ubuntu-Install-Debs.html) 和其 [apt 源配置](https://github.com/ros2/ros2_documentation/blob/humble/source/Installation/_Apt-Repositories.rst)。使用现成且正确的 UTF-8 locale 也可以；需要 RViz 等桌面工具时额外安装 `ros-humble-desktop`。这里检查/更新 systemd、udev 是为了避免官方说明中提到的 Ubuntu 22.04 早期包依赖问题，不对整台机器无差别升级。

**第二步：安装构建工具和消息包。**

```bash
sudo apt-get install clang libclang-dev cmake python3-colcon-common-extensions \
  ros-humble-ament-cmake ros-humble-rosidl-default-generators \
  ros-humble-rosidl-default-runtime \
  ros-humble-std-msgs ros-humble-geometry-msgs ros-humble-sensor-msgs \
  ros-humble-tf2-msgs ros-humble-visualization-msgs
```

**第三步：先补齐本部署副本的 `std_msgs` 依赖声明。** 当前 `rm_interfaces` 使用 `std_msgs/Header`，但缺少 CMake 的直接 `find_package` 和 `package.xml` 中的依赖。这是前置修正，不是可以忽略的提示。下面代码只添加这两处声明：检查原结构、保留 `.before-readme-deploy` 备份，重复执行不会重复添加；源码结构不匹配时明确退出。**操作者执行此块会修改这两个文件，本次 README 编辑没有替你执行。**

在项目根目录运行：

```bash
python3 - <<'PY'
from pathlib import Path
import xml.etree.ElementTree as ET

cmake_path = Path('rm_interfaces/CMakeLists.txt')
package_path = Path('rm_interfaces/package.xml')
cmake_text = cmake_path.read_text()
package_text = package_path.read_text()
cmake_anchor = 'find_package(geometry_msgs REQUIRED)'
package_anchor = '  <depend>geometry_msgs</depend>'
if 'find_package(std_msgs REQUIRED)' not in cmake_text:
    if cmake_text.count(cmake_anchor) != 1:
        raise SystemExit('CMake 结构已变化，需人工核对后添加 std_msgs')
    cmake_text = cmake_text.replace(cmake_anchor, 'find_package(std_msgs REQUIRED)\n' + cmake_anchor)
package_xml = ET.fromstring(package_text)
if not any(node.text == 'std_msgs' for node in package_xml.findall('depend')):
    if package_text.count(package_anchor) != 1:
        raise SystemExit('package.xml 结构已变化，需人工核对后添加 std_msgs')
    package_text = package_text.replace(package_anchor, '  <depend>std_msgs</depend>\n' + package_anchor)
ET.fromstring(package_text)
for path, updated in ((cmake_path, cmake_text), (package_path, package_text)):
    original = path.read_text()
    if original == updated:
        print('Already prepared:', path)
        continue
    backup = path.with_name(path.name + '.before-readme-deploy')
    if not backup.exists():
        backup.write_bytes(path.read_bytes())
    path.write_text(updated)
    print('Prepared:', path, 'backup:', backup)
PY
```

**第四步：构建接口并启动 ROS-only 模拟器。** 前面任一步失败都先处理错误，不跳过继续执行。新 Bash 终端先进入项目根目录并加载 Rust 环境：

```bash
set -eo pipefail
source "$HOME/.cargo/env"
source /opt/ros/humble/setup.bash
export ROS_DOMAIN_ID=87
export ROS_LOCALHOST_ONLY=1
unset IDL_PACKAGE_FILTER
colcon --log-base log build --base-paths rm_interfaces \
  --packages-select rm_interfaces --build-base build --install-base install \
  --cmake-clean-cache
source install/setup.bash
ros2 pkg prefix rm_interfaces
ros2 interface show rm_interfaces/msg/GimbalCmd
cargo run --locked -p daedalus --bin daedalus --release \
  --no-default-features --features ros2
```

`87` 是示例测试域，请选择不与本机其他系统冲突的域；外部算法和检查终端必须使用相同设置。这里只面向本机联调，跨机器通信需要单独配置。域号并不足以保证与实机隔离，不要连接真实串口、驱动或运动输出。

构建和运行 Rust ROS 模式时都需要 source ROS 与本仓 `install` overlay；先生成 `rm_interfaces` 再生成 r2r 绑定。消息包或环境发生变化后，需要重新核对绑定和构建产物。保留本仓 `third_party/r2r_msg_gen` patch，不直接换成上游默认生成器。原生依赖与绑定要求参考 [r2r 说明](https://github.com/sequenceplanner/r2r/blob/master/README.md)。

成功条件：接口构建退出码为 0，`ros2 pkg prefix` 指向本次根目录下的 `install`，消息检查包含 pitch/yaw/distance/fire_advice，模拟器完成场景加载；然后按第 6 节在第二终端确认 `/image_raw` 持续输出。`ros2 topic hz` 会持续运行，读数后按 `Ctrl+C` 返回，不能把它放在后续命令前并期待自动结束。

### 4.4 视频输入 mock

这个程序不启动三维模拟器，而是把视频转为 RGB 图像写入 Talos IPC，提供模拟位姿并接收/打印云台命令。适合排查视频解码和 IPC 接口，不验证机器人运动或射击效果。

先完成第 3 节 Rust 和基础原生依赖准备，并执行第 4.2 节的映射占用检查。在 Ubuntu 22.04 安装 FFmpeg 程序与全部所需开发库，并确认 pkg-config 可以找到它们；`ffmpeg-next` 8.1.0 的 [版本说明](https://github.com/zmwangx/rust-ffmpeg/blob/v8.1.0/README.md) 包含对 FFmpeg 3.4–8.0 的兼容目标，因此 Rust crate 的版本号并不要求系统也安装 FFmpeg 8.1。

```bash
set -eo pipefail
sudo apt-get install clang libclang-dev pkg-config ffmpeg libavcodec-dev libavformat-dev \
  libavutil-dev libavdevice-dev libavfilter-dev libswresample-dev libswscale-dev
pkg-config --modversion libavcodec libavformat libavutil libavdevice \
  libavfilter libswresample libswscale
export VIDEO_INPUT="/path/to/video.mp4"
test -r "$VIDEO_INPUT"
cargo run --locked -p daedalus --bin talos_gimbal_mock_server --release \
  --no-default-features --features talos,ffmpeg -- \
  --input "$VIDEO_INPUT" --loop --fps 30 --log-every 60
```

先把 `/path/to/video.mp4` 换为实际可读文件；对 RTSP/RTMP/HTTP 地址直接设置 `VIDEO_INPUT` 为流 URL，跳过本地文件的 `test -r`，不把它当成本地路径检查。`--loop` 默认关闭，关闭时读到 EOF 就结束；`--fps` 默认 30，非正值表示不节流；`--log-every` 默认 60。这里的 `--` 用于分隔 Cargo 参数和程序参数。成功启动会打印 `talos mock server started`；连续图像和命令仍须按第 7 节由消费者核验。

mock 固定输出 1440 × 1080 RGB8，位姿为模拟值，内参也不是输入视频的实际标定参数。它与主模拟器使用同一组 IPC 文件，**不能同时启动两者**。macOS 原生依赖和其他平台构建请参考 [ffmpeg-next 构建说明](https://github.com/zmwangx/rust-ffmpeg/wiki/Notes-on-building)。

### 4.5 部署到另一台机器

有两种部署方法：**源码部署**是在目标机器复制完整项目，执行第 3 节和所选第 4 节流程；ROS 模式推荐这样做，以免把不能直接迁移的 overlay 路径当作可搬运产物。**二进制部署**需要 executable、资产、配置及动态库，不能只复制一个文件。

下面给出 **默认 Talos 模式、同架构 Ubuntu 22.04 Linux** 的打包步骤。它单独构建到 `target/package-talos/`，避免拿到之前 ROS-only 或无接口模式生成的同名 binary；不要用这个包代替 ROS/FFmpeg 模式的部署。打包前已完成第 3 节，且正在项目根目录。

**构建机：生成可搬运目录和启动脚本。** 此块执行构建并生成 `dist/`；若目标目录已存在，明确退出，不覆盖旧包。`ldd` 仅检查自己构建的可信产物。

```bash
set -eo pipefail
PROJECT_ROOT="$PWD"
BUILD_TARGET="$(rustc -vV | sed -n 's/^host: //p')"
BUILD_DIR="$PROJECT_ROOT/target/package-talos"
PACKAGE_DIR="$PROJECT_ROOT/dist/daedalus-linux"
if [ -e "$PACKAGE_DIR" ]; then
  printf '%s\n' '打包目录已存在，请另选目录或先保存旧包，不自动覆盖' >&2
  exit 1
fi
cargo build --locked -p daedalus --bin daedalus --release \
  --target "$BUILD_TARGET" --target-dir "$BUILD_DIR"
BINARY_DIR="$BUILD_DIR/$BUILD_TARGET/release"
RUST_RUNTIME_DIR="$(rustc --print target-libdir --target "$BUILD_TARGET")"
export LD_LIBRARY_PATH="$BINARY_DIR/deps:$RUST_RUNTIME_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
DEPENDENCIES="$(ldd "$BINARY_DIR/daedalus")"
printf '%s\n' "$DEPENDENCIES"
if printf '%s\n' "$DEPENDENCIES" | grep -Fq 'not found'; then
  printf '%s\n' '动态库未找到，停止打包；先修正构建机运行库路径' >&2
  exit 1
fi
mkdir -p "$PACKAGE_DIR/bin" "$PACKAGE_DIR/lib"
cp "$BINARY_DIR/daedalus" "$PACKAGE_DIR/bin/"
cp config.toml LICENSE "$PACKAGE_DIR/"
cp -a assets "$PACKAGE_DIR/"
while IFS= read -r library; do
  case "$library" in
    "$BUILD_DIR/"*|"$RUST_RUNTIME_DIR/"*) cp -L "$library" "$PACKAGE_DIR/lib/" ;;
  esac
done < <(printf '%s\n' "$DEPENDENCIES" | awk '/=> \// {sub(/^.*=> /, ""); sub(/ \(0x[0-9a-fA-F]+\).*$/, ""); print}')
cat > "$PACKAGE_DIR/run.sh" <<'SH'
#!/usr/bin/env bash
set -eo pipefail
PACKAGE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$PACKAGE_ROOT"
export BEVY_ASSET_ROOT="$PACKAGE_ROOT"
export LD_LIBRARY_PATH="$PACKAGE_ROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$PACKAGE_ROOT/bin/daedalus" "$@"
SH
chmod +x "$PACKAGE_DIR/run.sh"
PACKAGE_DEPENDENCIES="$(env LD_LIBRARY_PATH="$PACKAGE_DIR/lib" ldd "$PACKAGE_DIR/bin/daedalus")"
printf '%s\n' "$PACKAGE_DEPENDENCIES"
if printf '%s\n' "$PACKAGE_DEPENDENCIES" | grep -Fq 'not found'; then
  printf '%s\n' '包内动态库不完整，停止生成归档' >&2
  exit 1
fi
tar -C "$PROJECT_ROOT/dist" -czf "$PROJECT_ROOT/dist/daedalus-linux.tar.gz" daedalus-linux
```

目录结构应为：

```text
daedalus-linux/
  run.sh
  config.toml
  LICENSE
  bin/daedalus
  lib/                  Bevy/Rust 等构建产生的必需动态库
  assets/               完整模型与音效
```

上面的拷贝只携带构建目录和 Rust 工具链中的依赖；系统运行库与 GPU 驱动由目标系统提供，不打包 glibc 或显卡驱动。如果 `ldd` 还指向其他自定义库目录，应先在两台机器安装同版本对应库，不假定脚本已覆盖。保留本项目及依赖的许可证说明，项目许可文本见 `LICENSE`；这个打包示例不提供许可合规审查。

**目标机：安装运行库、解包、检查并启动。** 把自己生成的 `dist/daedalus-linux.tar.gz` 传到目标机当前目录；使用与构建机相同架构及相容系统，准备图形桌面和匹配的 GPU 驱动。以下示例的目的目录应不存在，以免覆盖旧配置：

```bash
set -eo pipefail
sudo apt-get update
sudo apt-get install libx11-6 libasound2 libudev1 libxkbcommon-x11-0 \
  libwayland-client0 libxkbcommon0 libvulkan1
test ! -e daedalus-linux
tar -xzf daedalus-linux.tar.gz
cd daedalus-linux
PACKAGE_DEPENDENCIES="$(env LD_LIBRARY_PATH="$PWD/lib" ldd bin/daedalus)"
printf '%s\n' "$PACKAGE_DEPENDENCIES"
if printf '%s\n' "$PACKAGE_DEPENDENCIES" | grep -Fq 'not found'; then
  printf '%s\n' '缺少系统运行库，先补齐 ldd 列出的库，不能继续启动' >&2
  exit 1
fi
./run.sh
```

启动脚本把工作目录固定到包目录，使 `config.toml` 与截图位置确定；同时设置 `BEVY_ASSET_ROOT` 为**包含 `assets/` 的目录**，不要设成 `assets/` 本身。Bevy 0.19 的资产基路径依次取 `BEVY_ASSET_ROOT`、`CARGO_MANIFEST_DIR`，否则回退到 executable 的父目录，见 [对应版本实现](https://github.com/bevyengine/bevy/blob/v0.19.0/crates/bevy_asset/src/io/file/mod.rs)。

成功条件仍是实际出现 `scene loaded`、场景可操作和所需 IPC 数据可被消费者读取，而不是 tar 或 ldd 命令退出成功。不同架构、ROS overlay 迁移、容器无头运行及远端图形转发不属于这个二进制打包示例的适用范围。

## 5. 如何操作

### 5.1 键盘

| 对象 / 功能 | 按键与行为 |
| --- | --- |
| 己方步兵移动 | `W` / `A` / `S` / `D`；左 `Shift` 加速 |
| 己方底盘旋转 | 按一次 `Q` 开启单方向连续旋转，再按关闭；不是 `Q/E` 双向按住旋转 |
| 己方云台 | 方向键；启用外部自瞄后不再使用手动云台输入 |
| 模拟弹丸 / 飞镖 | 按住 `Space` 发射弹丸；按 `G` 发射飞镖 |
| 当前假人移动 | `I` / `J` / `K` / `L`；右 `Shift` 加速 |
| 当前假人底盘旋转 | `U` 开关；没有 `O` 反向旋转映射 |
| 当前假人云台 | `C/B` 控制 yaw，`F/V` 控制 pitch；按左 `Shift` 时暂停 `C/B` 云台输入 |
| 当前假人底盘倾斜 | `[` / `]` 控制 roll；`;` / `'` 控制 pitch |
| 切换活动假人 | `Tab`，在步兵与英雄假人间循环 |
| 切换相机 | `F3`：机器人第一人称 → 第三人称 → 自由视角 → 第一人称 |
| 外部自瞄控制开关 | `F5` 切换，观察 `auto-aim=ON/OFF`；不会自动启动检测算法 |
| 截图 | `F2`，写到当前目录的 `screenshot-0.png` 等文件 |
| 调试目标状态 | 左 `Shift+C` 同时切换假人装甲外观、前哨站旋转状态和科技核心阶段；右 `Shift+C` 只触发后两项 |
| UAV 模型 | 按住 `P` 周期生成静态模型；不等于飞行控制 |

前哨站旋转状态按正向、停止、反向循环。截图编号每次启动从 0 开始，保留实验截图时应自行改名/转存，避免下次覆盖。当前没有 `F4` 调试开关；调试项由 `config.toml` 的 `[debug]` 控制。

自由视角下，`W/A/S/D` 移动相机，`N/J` 上下移动，鼠标移动直接改变视角，不要求按住鼠标拖动。此模式停止己方底盘的常规移动输入，但假人控制与其他动作并未全部禁用；`J` 同时是活动假人的移动键。采集相机跟随当前视角，做第一人称自瞄实验时应回到机器人视角，避免把第三人称/自由视角图像当成车载相机图像。

### 5.2 Xbox 风格手柄

| 功能 | 输入 |
| --- | --- |
| 己方移动 / 加速 | 左摇杆 / 按住 L3 |
| 己方手动云台 / 精细控制 | 右摇杆 / 按住 LT |
| 己方旋转 / 假人旋转开关 | LB / Y |
| 当前假人移动 / 底盘倾斜 | 方向键 / 按住 R3 并推动右摇杆 |
| 弹丸 / 飞镖 | 按住 RB / 按 X |
| 切换假人 / 相机 | Start/Menu / Select/View |
| 外部自瞄 | 按住 RT；超过阈值时启用，松开后退出手柄触发的自瞄 |

摇杆死区为 0.12，LT/RT 阈值为 0.35，精细云台输入倍率为 0.35。当前使用枚举到的第一个手柄，没有手柄选择菜单。键盘 `F5` 开关与 RT 采用“或”关系；如果 `F5` 已打开，松开 RT 不会关闭自瞄。

### 5.3 功能体验流程与预期结果

先使用第 4.1 节无接口模式，保持 `auto-aim=OFF`。这一流程只检验本地功能，不要求先搭建算法。

| 功能 | 怎么使用 | 应观察到什么 / 功能边界 |
| --- | --- | --- |
| 地面、标定板与机器人场景 | 等待 `scene loaded`，用 `F3` 切到第三人称或自由视角观察 | 场地、己方步兵与两种假人可见；这里是模型场景，不是 Nav2 地图或裁判系统 |
| 底盘移动与陀螺运动 | 第一人称/第三人称下按 `W/A/S/D`，左 Shift 加速；按 Q 开关旋转 | 移动与旋转按物理/控制参数生效；自由视角不是操作己方底盘的模式 |
| 云台手动控制 | 方向键改变己方朝向，`C/B/F/V` 控制当前假人 | 云台角度变化；己方启用自瞄后切到外部 PID 控制，不同时叠加手动瞄准 |
| 假人运动与倾斜 | `I/J/K/L`、U 和倾斜按键；Tab 更换假人 | 默认先控制英雄假人，切换后另一个模型接管输入；不是自主对抗 AI |
| 装甲板外观 | 按左 Shift+C | 假人的装甲标签/贴图按调试序列切换；该组合键还改变前哨站与科技核心状态 |
| 前哨站 | 观察模型，使用 Shift+C 切换 | 转动方向按正向 → 停止 → 反向循环，便于测试不同旋转目标；不提供完整前哨站血量裁判 |
| 大/小能量机关 | 用自由视角找到机关，等待状态轮转；返回机器人视角后瞄准并发射 | 小机关有固定转速，大机关激活阶段采用变化转速；各面按自身状态机激活、完成、超时/恢复，不靠 F5 自动命中 |
| 模拟弹丸与飞镖 | Space 发射弹丸，G 发射飞镖 | 出现发射和碰撞行为，弹丸受重力影响；气动阻力默认关闭，英雄没有独立 42 mm 发射配置 |
| 命中统计 | 观察窗口 `total/accurate/pct` | total 是发射计数，accurate 是特定能量机关有效命中，pct 为比例值而非统一装甲命中率/比赛得分 |
| 科技核心阶段灯光 | Shift+C 循环阶段，观察红蓝灯组 | 从比赛运行空闲、难度/机械臂准备，到步骤完成和恢复等九个阶段变化；这是视觉状态，不是机械臂任务执行 |
| RGB 图像、内参和位姿 | 改用 Talos 或 ROS 模式，再按对应联调章节接收 | 接收到虚拟相机数据；F3 变化会改变采集视角，算法测试应保持机器人视角 |
| 深度派生点云 | ROS 模式保持 `livox_ros.enabled=true`，检查 `/livox/lidar` | 发布相机视场内的 PointCloud2；不提供真实扫描时序、IMU 或 360° 雷达 |
| 外部自瞄 PID 和开火建议 | 消费者/算法接入后按 F5，先发送不建议开火的有效目标 | 云台跟踪外部命令；开启 fire_advice 才请求模拟开火，本仓没有自带目标检测器 |
| 截图与诊断 | F2 截图；配置 debug.diagnostics 后重启 | 当前目录保存窗口截图，控制台打印诊断；截图不是训练集标注文件 |
| 静态 UAV | P 生成 | 只生成静态模型用于观察，不实现飞行航线、速度控制或空战逻辑 |

能量机关的实现含激活时间窗与失败恢复，且部分规则是调试/仿真选择，不应称为完整赛事规则复现。科技核心的 JSON 状态在 ROS 模式可从 `/simulator/tech_core/state` 读取；Talos 另有机器人/机关真值、底盘观测和运行状态，按其结构解释，不能当成已完成的通用标注导出。

退出本地实验时关闭窗口；视频 mock 不加 `--loop` 可在文件 EOF 后结束。强制终止、异常退出和退出后的 IPC 残留须另行检查，不把进程被杀掉当作优雅退出验证。

## 6. ROS 接口与联调

节点创建名称为 `simulator`，命名空间为 `robomaster`；话题在源码中使用下表的绝对名称，不自动加该命名空间。

| 方向 | Topic | 消息类型与说明 |
| --- | --- | --- |
| 发布 | `/image_raw` | `sensor_msgs/msg/Image`；RGB8 图像 |
| 发布 | `/camera_info` | `sensor_msgs/msg/CameraInfo`；与虚拟相机有关的内参 |
| 注册但默认不发送 | `/image_compressed` | `sensor_msgs/msg/CompressedImage`；当前 `publish_compressed = false` |
| 条件发布 | `/livox/lidar` | `sensor_msgs/msg/PointCloud2`；`livox_ros.enabled` 控制 |
| 发布 | `/tf` | `tf2_msgs/msg/TFMessage` |
| 发布 | `/odom_pose`、`/gimbal_pose`、`/muzzle_pose`、`/camera_pose` | `geometry_msgs/msg/PoseStamped`；坐标系以消息 header 为准 |
| 发布 | `/simulator/marker` | `visualization_msgs/msg/Marker` |
| 发布 | `/simulator/tech_core/state` | `std_msgs/msg/String`；科技核心 JSON 状态，最多 20 Hz |
| 订阅 | `/rm_gimbal/cmd` | **`rm_interfaces/msg/GimbalCmd`**；sensor-data QoS |

外部算法需要消费 `/image_raw`、`/camera_info`，并把**匹配类型和角度约定**的命令送到 `/rm_gimbal/cmd`。这不是 `/armor_solver/cmd_gimbal`，也不能把 `auto_aim_interfaces/msg/GimbalCmd` 当成同一消息类型。仅做 topic remap 无法解决类型或单位不一致。

在另一个 Bash 终端，从项目根目录加载同一环境：

```bash
source /opt/ros/humble/setup.bash
source install/setup.bash
export ROS_DOMAIN_ID=87
export ROS_LOCALHOST_ONLY=1
ros2 node list
ros2 topic list -t
ros2 topic info /rm_gimbal/cmd --verbose
ros2 topic hz /image_raw
```

先确认图像、类型与订阅者，再在模拟器中按 `F5` 打开自瞄。可以发送不建议开火的示例消息检查命令通路；这不是外部算法或实机测试：

```bash
ros2 topic pub --once /rm_gimbal/cmd rm_interfaces/msg/GimbalCmd \
  '{yaw: 0.0, pitch: 90.0, distance: 5.0, fire_advice: false}'
```

命令角度按度传入，ROS 路径内部使用 `yaw = yaw_deg`、`pitch = pitch_deg - 90°`，再转为弧度进行跟踪。上例对应内部目标 yaw/pitch 为 0，但不是“相对于当前车身转零度”的通用指令；需结合模型方向、坐标转换和 TF 校验。`distance == -1` 表示无解并移除跟踪目标。`fire_advice: true` 会触发模拟开火，不要在初次接入时默认开启；手动 `Space` 也可以发射。

结束这一测试时，**先保持 F5 开启并发送无解命令清目标，再关闭 F5**；关闭 F5 只是停止该控制路径，不保证删除已有 tracker：

```bash
ros2 topic pub --once /rm_gimbal/cmd rm_interfaces/msg/GimbalCmd \
  '{yaw: 0.0, pitch: 90.0, distance: -1.0, fire_advice: false}'
```

当前命令处理没有明确的失联超时自动清目标机制。算法停止后若目标仍被保持，按上述顺序清理或重启实验，不要假定停掉发布者就会自动停车/停止云台跟踪。若关闭后再次开启自瞄，未清理的旧目标可能恢复跟踪。

### 点云与时间约定

`/livox/lidar` 是**虚拟深度图派生**的 `PointCloud2`，不是 Livox `CustomMsg`、真实扫描数据或完整 360° LiDAR；没有真实 IMU 与逐点相对时间。字段为 `x/y/z/intensity`（float32）与 `tag/line`（uint8），`point_step = 18`，默认 frame 为 `camera_link`。接 SLAM/导航前必须确认其输入需求，不能只改 topic 名就认为兼容。

ROS 坐标通过源码转换为前/左/上约定；TF 中包含 `map`、`odom`、`gimbal_link`、`muzzle`、`muzzle_link`、`camera_link` 和 `camera_optical_frame`，查看实际父子链后再配置算法。图像使用 `camera_optical_frame`。当前时间戳取系统时间，不提供 `/clock` 仿真时间；不要无条件给下游设置 `use_sim_time=true`。

## 7. Talos 接口与联调

默认模式使用文件映射，而不是 ROS。主程序作为生产者创建：

```text
/tmp/talos_ipc_meta
/tmp/talos_ipc_image_pool
```

**同一组文件只运行一个生产者**：不能同时启动两份默认模拟器，或让模拟器与 mock 并行。创建时会重新初始化/截断映射文件；生产者正常析构时移除自己拥有的文件，异常退出的清理不能保证。不要在仍有活跃进程时手动删除这些文件。

图像/pose 三缓冲也要求单消费者，云台命令要求单写入方；不能让两个算法客户端同时改消费状态或发命令。生产者和客户端宜使用同一普通用户，避免权限不匹配；不要为解决权限问题用 root 启动第二个生产者。

外部消费者必须匹配 `crates/talos-ipc/src/layout.rs`、`publisher.rs` 和 `shm.rs` 的契约：

- Magic 为 `0x54414C05`，协议版本为 **2**；结构是 `repr(C)`，布局、对齐和原子状态不能只按字段顺序猜测。
- RGB8 图像固定为 **1440 × 1080**，使用三缓冲；当前默认 Talos 采集尺寸不随 `capture.color` 配置变化。
- pose 槽位为 Gimbal=0、Odom=1、Muzzle=2、Camera=3；槽位 4 为兼容旧协议的 chassis observation。四元数顺序是 `[w, x, y, z]`，部分发布项使用单位旋转，不能直接当作完整标定外参。
- 消费者要消费图像及 **0–3 四个位姿槽位**，并按协议更新消费状态。图像或任一个必要 pose 的 `NEW` 标志未清除时，不发布下一组同步图像；只读取 RGB 可能只收到第一帧。序号与时间戳用于核对图像/pose 对应关系，时间戳为 UNIX 系统时间纳秒。
- 云台命令包含 `yaw_deg`、`pitch_deg`、`distance_m` 与 `fire_advice`。Talos 路径将 pitch 先取负，再经过共同的 `-90°` 变换，即内部 pitch 为 `-pitch_deg - 90°`，**不能照搬 ROS pitch 数值**。`distance_m == -1` 清除目标；`fire_advice = 1` 请求模拟开火，初次联调用 0。

模拟器端的完整接入顺序与验收点：

1. 按第 4.2 节检查占用并启动**一个**生产者；确认 `scene loaded`、映射文件建立。视频测试改用第 4.4 节，不能与模拟器并行。
2. 启动你实际使用的、匹配 version 2 的**一个**客户端，读取相机内参，并持续消费图像及 pose 0–3。本仓没有外部检测器的安装/启动脚本，因此这里不编造一个通用“算法启动命令”；没有客户端时只能验证模拟器自身与映射创建。
3. 检查连续两组以上图像的序号递增、尺寸为 1440 × 1080，并确认该组四个 pose 与图像的序号/时间戳对应；如果停在第一帧，先检查消费标志而非降低发布频率。
4. 主模拟器保持机器人视角，按 F5 开启自瞄；客户端先发送 `yaw_deg=0`、`pitch_deg=-90`、`distance_m=5`、`fire_advice=0` 的目标，核对云台方向。这里对应内部 yaw/pitch 为 0，不是相对当前姿态的零偏移；mock 仅接收/打印命令，不表现云台运动。
5. 有效目标方向验证后才在模拟器中测试 `fire_advice=1`。结束时先发送 `distance_m=-1`、`fire_advice=0` 清目标，再关闭 F5、停止客户端和生产者；异常退出按实际进程与文件状态检查。

主程序的 `connected to talos-cpp` 日志只表示自身成功打开映射，不证明外部客户端已接入。运行状态和 heartbeat 只能辅助判断生产者活动，不代表算法已经完成闭环。

可以检查映射文件是否存在，但存在不代表帧持续更新或协议兼容：

```bash
ls -l /tmp/talos_ipc_meta /tmp/talos_ipc_image_pool
```

外部客户端的构建和启动脚本不在本仓中；可参考作者的 [Talos 项目](https://github.com/Blackjack200/talos)，但接入前仍应按本仓 version 2 布局核对，不能把不同版本直接视为兼容。共享内存只减少 IPC 数据传输开销，渲染回读和图像处理仍有成本，不能据此宣称端到端零拷贝。

## 8. 配置与调参

编辑根目录 `config.toml`，保留其他配置节。下表是**仓库配置当前值**，不是所有源码 fallback 的默认值：

| 配置 | 当前值 / 用途 |
| --- | --- |
| `window.present_mode` | `auto_no_vsync`；渲染不强制垂直同步，实际速率仍取决于硬件 |
| `debug.egui` / `inspector` / `diagnostics` | `false` / `false` / `true`；Inspector 和诊断会影响性能 |
| `preview.enabled` | `true`；通信模式下显示采集预览，关闭不等于无窗口 |
| `render.shadows` / `main_camera_fxaa` | 均为 `true`；影响画面与渲染成本 |
| `render.metalfx_temporal` / `metalfx_frame_generation` | `true` / `false`；仅支持的平台/设备生效 |
| `capture.color.width` / `height` | `1440` / `1080`；ROS 启动时读取，默认 Talos 使用协议固定尺寸 |
| `capture.depth.width` / `height` / `near` / `far` | `1280` / `720` / `0.1` / `80.0`；深度采集和点云范围 |
| `livox_ros.enabled` / `publish_freq` | `true` / `10.0` Hz；只对 ROS 路径有意义 |
| `physics.fixed_hz` / `substep_count` | `120.0` / `8`；物理固定更新和子步数，不是图像帧率 |
| `vehicle.max_speed` / `gimbal_rotation_speed` | `6.0` m/s / `3.0` rad/s |
| `vehicle.gimbal_pid.yaw` / `.pitch` | 各自 `kp=50`、`ki=0`、`kd=0.1`；外部目标跟踪 PID |
| `projectile.speed` / `cooldown` / `lifetime` | `25.0` m/s / `0.05` s / `5.0` s |
| `projectile.diameter` / `mass` | `0.017` m / `0.0032` kg，即 17 mm / 3.2 g；以数值为准，原质量注释不准确 |
| `projectile.aerodynamics.enabled` | `false`；可配置阻力、空气密度和风向/风速 |
| `camera.fov` | `45.0` 度；与一般运动参数的 rad/s 单位不同 |

配置插件监听文件修改，成功解析后更新配置资源、固定步长与物理子步。**这不等于所有参数都实时生效**：窗口/插件开关、采集尺寸、相机投影和启动时生成的实体等存在初始化读取，修改后应重启并检查实际效果。运行中解析失败会保留旧配置；首次读取失败则回退代码默认值，先检查日志而不是误认为新配置已加载。

想降低渲染开销时，可先在固定实验场景下比较关闭阴影、通信采集预览或 Inspector 的效果；改动后重启，记录机器、分辨率、功能开关和实际帧率。不应随意降低物理更新频率、修改模型或强行提升点云发布频率来“保证性能”。

## 9. 常见问题

| 现象 | 优先检查 |
| --- | --- |
| `cargo run` 选错程序 / mock 缺 feature | 明确指定 `-p daedalus --bin ...`；mock 必须同时启用 `talos,ffmpeg` |
| Rust 版本过低 / lock 不匹配 | 核对实际依赖错误和工具链；保留锁文件，不随意改版本 |
| `ros2` 模式出现 `app` 未定义 | 是否忘了 `--no-default-features`，导致默认 Talos 同时启用 |
| 找不到 r2r 的 `rm_interfaces` 类型 | 先执行第 4.3 节依赖修正与接口构建，再 source overlay；同时检查终端是否继承了错误的 `IDL_PACKAGE_FILTER` |
| libclang 或 FFmpeg pkg-config 报错 | 是否安装所选模式的开发库，且库与目标架构/版本匹配；只装 FFmpeg 命令行程序不等于有开发头文件 |
| 无窗口 / 无 adapter / 黑屏 | 图形桌面、GPU 驱动、WSLg、资产加载日志；仓库的非标准 adapter 放行设置不是硬件兼容保证 |
| 配置不生效 / 场景资源缺失 | 启动目录、`config.toml` 解析日志、完整 `assets/`；修改初始化参数后重启 |
| 二进制报动态库找不到 | Bevy dynamic_linking、ROS/FFmpeg 运行库及动态加载环境；不要只复制 executable |
| ROS 有话题但无图像 | 场景是否就绪、采集资源、域号/环境、QoS；压缩话题默认不发数据 |
| 有云台命令却不转动 | `auto-aim` 是否 ON，topic/类型/角度是否一致，是否发了无解距离；无接口模式不会产生外部目标 |
| Talos 只有一帧 / 没有连续帧 | 客户端是否消费图像和 pose 0–3 的状态；是否另一个生产者重置了映射；ABI/version 是否一致 |
| 停掉算法后仍保持目标 | 当前无命令失联超时保证；显式关闭自瞄或发送无解，区分停发布者与清目标 |

本 README 不是构建、跨平台性能或联调验收报告。验证某次部署时记录 OS/GPU/Rust、feature、配置、启动命令、实际收到的图像与位姿、控制响应和退出结果。新增、删除或修改功能、接口、参数及部署入口后，应同步更新本说明和 `AGENTS.md` 中对应规则，任务改造记录放在根目录 `doc/`。

## 10. 项目信息与演示

- **作者**：Blackjack200
- **团队**：Actor&Thinker 战队
- **交流方式**：GitHub Issues / Pull Requests
- **开源协议**：AGPL v3

<div align="center">
    <img src="demo.png" width="75%">
</div>

本项目采用 **AGPL v3** 协议。开放仿真基础设施是为了提供可复现的视觉算法实验起点；扩展与部署时仍需核对依赖许可、目标环境以及实验本身的验证边界。
# bevy_rm_sim
