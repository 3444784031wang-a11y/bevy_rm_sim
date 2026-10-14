# Conda 隔离环境与一键启动 改造记录

日期：2026-10-13。时间统一使用 Asia/Shanghai；原始运行日志的 UTC 时间加 8 小时对应本文时间。

## User Intent

用户要求在本项目建立 Conda 环境，将依赖与其他环境隔离，提供运行后打开模拟器的 `start.sh`，实际验证功能后写报告。

本次落实的是 Linux x86_64 桌面的默认 Talos 模拟器，不把创建环境、编译成功或开窗单独当作完整验收。

## Scope

- 新增根目录 `start.sh`、`environment.yml`、`conda-linux-64.lock`。
- 建立并实际使用 `.runtime/conda` 项目专用环境；Conda/Cargo 缓存和编译产物保存在 `.runtime/`。
- 更新 README 部署入口、项目规则中的环境/产物约定和 `.gitignore`。
- 在已获得的安装、构建及图形运行授权范围内，构建默认 `daedalus`，检查控制、发射、视角、图像/位姿/云台 IPC、启动保护及退出。
- 保存本报告、必要截图和结构化验证证据。

## Out of Scope

- 不修改 Rust 仿真源码、`Cargo.toml`、`Cargo.lock`、`config.toml`、模型或 ROS 消息定义。
- 不实现此前讨论的红蓝切换、弹丸切换、重置位置或长按车辆放置。
- 不修改 base、`25shaobing_nav` 或用户全局 Rust 工具链，不安装系统级 GPU 驱动。
- 不构建/运行 ROS、FFmpeg mock、`--local` 模式，不连接真实硬件或外部自瞄算法。
- 不执行 Git 暂存、提交、推送、分支、合并、发布等写操作；不启动子 Agent。

## Explorer Findings

### Files inspected

- `Cargo.toml`、`Cargo.lock`：workspace、默认 Talos feature、二进制和编译配置。
- `src/main.rs`、`src/config.rs`、`config.toml`、`src/scene.rs`、`src/setup.rs`：入口、配置路径、插件、场景就绪和模型初始化。
- `src/systems/controller.rs`、`camera.rs`、`debug.rs`、`projectile.rs`、`src/statistic.rs`：按键、视角、截图和发射计数。
- `src/talos/plugin.rs`、`capture.rs`、`ground_truth.rs`：自瞄开关、云台命令、采集及真值。
- `crates/talos-ipc/src/layout.rs`、`publisher.rs`、`subscriber.rs`、`shm.rs`、`triple_buffer.rs`：共享布局、同步握手、固定映射文件和所有者清理。
- `AGENTS.md`、`README.md`、`.gitignore`：授权边界、现有部署说明及生成目录。
- 实际 Conda 元数据、锁定 Bevy 包 manifest、宿主机 Vulkan/X11 信息与进程动态库映射。

### Active logic path

```text
start.sh 定位根目录并解析参数
-> env -i 清除继承环境
-> 平台/glibc、项目文件、项目会话锁检查
-> 按 explicit 锁创建项目 Conda prefix（首次）
-> 检查锁摘要与已安装包列表
-> 激活 Conda 编译器、Rust 和原生库
-> cargo build --locked -p daedalus --bin daedalus（默认 Talos）
-> 检查桌面和既有 IPC 文件
-> exec 已构建程序
-> 完成场景加载、仿真控制、采集和 IPC
-> 关闭窗口，释放资源并清理本次生产者映射文件
```

`--run-only` 跳过安装和构建；`--check` 不安装、不编译、不运行模拟器。`--local` 使用 `--no-default-features` 和单独产物目录，其运行不在本次验收覆盖中。

### Data flow

键盘窗口事件进入既有 Bevy Input/ECS 系统，驱动底盘、云台、假人、视角和发射；相机离屏渲染通过 GPU 回读发布 Talos RGB 图像及四路同帧位姿。

验证消费者只访问本次生产者的映射文件，按源码的三缓冲 CAS 语义同时消费 image 与 Gimbal/Odom/Muzzle/Camera，核对序号及 UNIX 纳秒时间戳。命令只发送到仿真 IPC；F5 控制接收，`distance_m = -1` 清除跟踪目标。

### Risk notes

- Conda 隔离用户态工具链/库，不隔离内核、glibc、GPU 驱动、桌面、声音服务或 `/tmp`。
- 该 explicit 锁要求 Linux x86_64、glibc >= 2.34；本机 Ubuntu 22.04 满足。项目路径改变后必须重建 prefix 和带原路径 rpath 的产物。
- Talos 名称固定，跨项目仍需协调。脚本对已存在文件一律拒绝，不自动删除或截断；项目会话锁不能替代所有跨项目生产者协调。
- Bevy `dynamic_linking` 需要对应 Bevy/Rust 动态库，不能只复制一个 executable。
- ALSA 插件有较多 conda-forge 传递依赖，包含 FFmpeg 9 和其他媒体库；这不是 `ffmpeg-next` 8 视频 mock 的验收环境。
- Cargo 仍查找项目及祖先目录的 `.cargo/config` / `.cargo/config.toml`；本机已确认不存在。私有 Cargo 缓存不等于忽略所有目录级配置，未来新增配置需复核覆盖关系。

### Recommended modification boundary

只调整安装/启动脚本、原生依赖声明、文档和生成目录忽略规则；保持仿真逻辑、Cargo 锁和配置不变。不为环境任务顺手修复场景、弹道或可选 ROS 组合问题。

## Modifier Changes

### Files changed

| 文件/目录 | 改动 |
| --- | --- |
| `start.sh` | 可执行一键入口、环境清理、安装/检查/构建/运行选项和保护措施 |
| `environment.yml` | 项目原生工具链及直接依赖清单 |
| `conda-linux-64.lock` | 最终 153 个已安装包的完整精确 URL/build/MD5 |
| `.gitignore` | 忽略 `/.runtime/`，不提交环境、缓存和产物 |
| `README.md` | 推荐 Conda 流程、隔离边界、使用/维护方法及实测记录入口 |
| `AGENTS.md` | 同步启动入口、依赖锁和 `.runtime` 约定，保留原优先级、授权、Git 和记录规则 |
| `doc/20261013_conda_startup.md` | 本次事后报告 |
| `doc/20261013_conda_startup/` | 6 张运行截图和 `validation.json` |

### Key changes

1. 使用项目 prefix `.runtime/conda`，不复用当前激活环境。检测现有 Miniforge/Miniconda/Anaconda，也允许显式绝对路径 `CONDA_EXE`。
2. Rust/Cargo 固定为 1.95.0，GCC/G++、pkg-config、ALSA 及插件、udev、X11、Wayland 和 Vulkan loader 从该环境提供；Cargo 自身 Rust 依赖仍按未改动的 `Cargo.lock` 解析。
3. 新进程使用清理后的环境。桌面连接、必要代理、终端及显式 `RUST_LOG` 保留，Python/ROS/其他 Conda、编译器和库路径不继承。
4. 使用开发配置、单任务、关闭调试符号和 incremental；默认 Talos 产物 `.runtime/target/talos/debug/daedalus`。不修改源码仿真频率、物理参数或 Cargo profile 正文。
5. 运行时固定项目 CWD 和 `BEVY_ASSET_ROOT`，提供匹配的 Bevy、Rust、Conda 动态库路径。
6. 通过锁摘要与实际 explicit 包列表检查环境漂移；重复会话、未知参数、互斥操作、无图形桌面和既有 IPC 文件明确失败。

### Behavior preserved

默认 Talos、原生场景、键盘/手柄映射、碰撞、云台 PID、弹丸/飞镖、F3/F5/F2、协议布局与所有仿真配置保持原样。受保护源码和 Cargo/配置文件的 SHA-256 检查通过。

### Behavior intentionally adjusted

启动和构建不再受其他已激活环境的 PATH、库路径或 Cargo 设置影响；首次安装/构建后可复用项目缓存。启动前拒绝覆盖既有 Talos 文件，同项目禁止同时安装、构建或启动第二个会话。

### Notes

本机执行：

```bash
cd /home/wang/Desktop/bevy_robomaster_simulator
./start.sh              # 推荐，一键增量构建并打开默认 Talos 模拟器
./start.sh --run-only   # 已有产物，只运行，不安装或构建
./start.sh --check      # 只检查已有隔离环境
```

其他选项见 `./start.sh --help` 与 README 第 3 节。操作前确保窗口获得焦点。

安装和构建通过工具授权执行：最初的 `./start.sh --build-only` 授权明确包含联网安装、默认 Talos 编译、单任务开发配置和 `.runtime/target/talos` 产物范围。后续同范围构建复用授权。没有把运行授权自动当作任意构建或发布授权。

## Auditor Review

由主 Agent 完成事实确认、修改和复查，没有虚构独立 Explorer/Modifier/Auditor 子 Agent。

### Checks performed

- [x] 关键路径：真实 entry/features、CWD/资产、编译器与动态库来源、IPC 布局和退出清理。
- [x] diff：以 `/tmp/daedalus-conda-20261013/` 修改前备份比较文档及忽略规则；未初始化/写入 Git。
- [x] 定向搜索：控制消费者、F2/F3/F5、启动调度、命令处理和三缓冲握手。
- [x] YAML/锁结构与 Markdown 检查；本次不修改 XML/launch。
- [x] `bash -n start.sh`。
- [x] `shellcheck --exclude=SC1091 start.sh`；仅排除静态分析器无法定位动态 Conda source 的检查，其他警告已修复。
- [x] 已获得明确构建许可；默认 binary/package/features/产物位置均符合授权。
- [x] 完整构建成功和最终一键入口的增量构建/窗口运行。
- [x] 实际控制、HUD、截图、位姿/真值、IPC 和退出检查。
- [x] Rust/ROS/第三方源码及 `Cargo.toml`、`Cargo.lock`、`config.toml` 的哈希保持检查。

#### 环境与构建

| 项目 | 实测 |
| --- | --- |
| 系统 | Ubuntu 22.04.5 / Linux x86_64，X11 `DISPLAY=:1` |
| Conda | 现有 `/home/wang/miniforge3/bin/conda`，26.7.2 |
| 环境 | `/home/wang/Desktop/bevy_robomaster_simulator/.runtime/conda`，153 个包 |
| Rust/Cargo | 1.95.0 / 1.95.0；全局 rustup 工具链仍为原来的 1.91.1 |
| 原生库 | ALSA 1.2.16.1 + alsa-plugins 1.2.12、udev 262、X11 1.8.13、Vulkan loader 1.4.357 |
| 图形后端 | 实际选中 NVIDIA GeForce RTX 3050 Laptop GPU / 580.178.04 / Vulkan |
| 编译 | `cargo build --locked --package daedalus --bin daedalus`，默认 Talos，开发配置 |
| 首次完整 Rust 编译 | Cargo 报告成功，35 分 46 秒；该次脚本退出异常见下方问题记录 |
| 最终脚本构建复验 | `./start.sh --build-only`，退出 0，Cargo 0.51 秒 |
| 一键入口实际构建 | `./start.sh`，Cargo 0.25 秒，随后打开窗口 |
| 完整 explicit 锁 | 离线 `conda create --dry-run --file conda-linux-64.lock` 退出 0，未创建测试 prefix |
| 空间 | `.runtime` 约 6.0 GiB，包括环境、下载缓存和 Rust 产物；不是可移植发行包 |

实际运行进程的 `/proc/<pid>/maps` 确认 `libasound`、Pulse ALSA 插件、`libudev`、`libvulkan`、Rust `libstd` 与 Bevy dylib 来自项目环境/目标目录。系统 GPU 驱动和 glibc 仍由宿主机提供，这是明确的隔离边界。

最终环境从 `/tmp` 使用绝对脚本路径，注入其他项目的 `CONDA_PREFIX`、`LD_LIBRARY_PATH`、`CARGO_HOME`、`PYTHONPATH`、无效 `RUSTFLAGS` 和 `CC` 后仍能启动，日志确认 `scene loaded`。进程 CWD 与实际 Cargo/Conda 路径均回到本项目。

#### 功能验证

| 检查 | 实际观察 | 结果 |
| --- | --- | --- |
| 场景/渲染 | 模型、装甲外观和 HUD 可见；日志出现 `scene loaded` | PASS，非全部材质/场景视觉验收 |
| 己方底盘 | W 后 Odom 位置变化约 0.17 m；初始位置附近存在碰撞，未测试长距离路径 | PASS |
| 云台 | 方向键后 Gimbal 四元数产生明显变化，代表有效输入响应 | PASS |
| 三种视角 | F3 循环，Camera 位姿改变；自由视角 W/N 移动得到位置变化，再回到跟随视角 | PASS |
| 假人控制/切换 | Tab 前 I 改变蓝方 label 1 目标，Tab 后 I 改变 label 3 目标约 0.46 m | PASS |
| 旋转开关 | HUD 分别显示 `gyro=ON`、`remote-gyro=ON`，随后关闭 | PASS |
| 弹丸 | 持续 Space 后 HUD `total` 从 15 增到 30 | PASS，仅发射响应，不代表命中验收 |
| 飞镖 | G 后 HUD `total` 从 30 增到 31 | PASS，仅发射响应，不代表完整弹道精度 |
| 截图 | F2 生成有效 1280×720 PNG，人工视图检查 HUD 与模型 | PASS |
| Talos 图像 | meta 3712 B、图像池 13,996,800 B；1440×1080 RGB8、magic `0x54414C05`、协议 2 | PASS |
| 四路位姿同步 | 消费 image 及 Gimbal/Odom/Muzzle/Camera，每次核对同帧 seq 和 timestamp_ns；序号持续增长 | PASS |
| 自瞄接收开关 | F5 对应 runtime 状态 0→1→0，OFF 时命令仍 pending，ON 后被消费 | PASS |
| IPC 云台命令 | `yaw_deg=30`、`pitch_deg=-90`、`distance_m=3` 改变 Gimbal 四元数 | PASS |
| IPC 开火建议 | 在新的运行会话连续发送 100 次 `fire_advice=1`，HUD `total=8` | PASS，受既有冷却逻辑约束 |
| 无解清除 | `distance_m=-1` 在 ON 状态被消费，然后关闭自瞄接收 | PASS；未用内部反射检查组件 |

键盘自动验证使用只投递给本次模拟器窗口的 X11 KeyPress/KeyRelease，每个步骤前恢复焦点；这是应用输入路径的仿真测试，不是实体手柄验证。

证据：

- `doc/20261013_conda_startup/validation.json`：按键前后位姿、假人真值、自瞄状态、最终 IPC 断言和退出码。
- `third-person.png`、`chassis-spin.png`、`remote-spin.png`：窗口模型/HUD、两种旋转开关。
- `projectile-shot.png`、`dart-shot.png`：发射计数 30→31。
- `ipc-fire-advice.png`：新会话自瞄 ON、外部连续建议发射计数 8。
- `.runtime/build-talos.log`、`run-talos-fixed-audio.log`、`repeat-run.log`：保留的本机构建/运行日志，不作为版本控制交付物。

#### 保护与退出

| 检查 | 实测 |
| --- | --- |
| 重复会话 | 构建中和进程运行中分别尝试第二会话，退出 1，明确拒绝 |
| 既有 IPC | 使用 O_EXCL 创建本次所有的短暂测试文件，启动退出 1，文件内容未被截断；核对 inode 后仅清理该测试文件 |
| 无显示环境 | 删除 DISPLAY/WAYLAND_DISPLAY 后 `--run-only` 退出 1，没有启动窗口 |
| 无效/互斥选项 | 明确返回非零，不执行安装、构建或应用 |
| 最终完整环境首次退出 | PID 600779，经窗口正常关闭，退出 0，约 31 分钟验证会话结束 |
| 最终环境重复退出 | PID 603401，从其他目录/污染环境启动后正常关闭，退出 0 |
| IPC 清理 | 每次最终正常关闭后两个本次映射文件均消失；没有删除其他生产者文件 |

### Issues found

1. **环境解析名称纠正**：conda-forge 的包名是 `libvulkan-loader`，不是首次探测的 `vulkan-loader`。已按解析结果修正清单和锁。
2. **安装阶段缺少音频插件**：首轮 48 包环境开窗时 ALSA 报缺少 Pulse/JACK 等插件。停止会话后安装 `alsa-plugins` 及精确传递依赖，最终锁为 153 包；最终两次日志不再有 ALSA 缺库错误。
3. **首轮退出异常**：未完整音频环境的第一次窗口关闭返回 139。后来完整环境两次退出均为 0，但没有取得足以证明唯一根因的调用栈；GDB attach 被运行环境拒绝，没有提升系统 ptrace 权限，也没有把“唯一根因已定位”写成事实。此初始失败保留为历史证据，后续首次启动/驱动变更仍应关注退出表现。
4. **构建中的脚本修改**：首次 Cargo 已成功编译，但执行中的脚本被本次更新后，原 shell 流在尾部报引号 EOF，整次脚本退出 2。随后停止该调用，完成脚本编辑及语法/ShellCheck 检查，最终不再边执行边修改；缓存构建和一键运行复验均成功。这不是 Cargo 或最终脚本的编译失败。
5. **测试输入投递问题**：最初 XTest 未给窗口送达有效按键，后续测试中其他窗口也会抢焦点。没有把那些无响应记录当作项目功能失败或成功；改用窗口定向事件和逐步恢复焦点，以位姿、状态及截图确认响应。
6. **单条开火建议与冷却**：源码的 `ProjectileCooldown` 在 `projectile_launch` 被调用时 tick，单条建议可能被冷却限制而不发射。本次未改仿真逻辑，改用连续建议验证实际发射，记录计数 8，不宣称每个 fire_advice 必然对应一发。
7. **既有视觉/资源限制**：GLB 加载存在 `Unknown vertex attribute COLOR_1` 警告；初始位置附近目标/模型遮挡，画面较暗，移动可受碰撞限制。没有因此改模型、出生位置、灯光或仿真配置，也不把本次截图当作完整视觉质量验收。
8. **未覆盖项**：ROS、FFmpeg mock、`--local` 实际构建运行、实体手柄/震动、声音听感、命中/打符完整闭环、外部算法、跨平台及专门长时间压力测试均未验收。宿主声音服务可用和音频缺库消除不等于已经听验所有音效。

### Final result

**PASS：本次默认 Talos 模式的项目内 Conda 隔离、一键构建启动、已列出的基本功能/IPC、保护措施与最终两次正常退出检查通过。**

PASS 不表示上述未覆盖功能、视觉质量、外部算法或实机已经验收；初始失败和既有边界均已单独记录。源码、Cargo 锁与仿真参数保持不变。
