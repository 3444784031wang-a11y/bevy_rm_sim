# README 部署与使用说明 改造记录

## User Intent

用户要求：“该项目如何部署，如何使用，读取源码，写在readme里”。依据实际源码、配置和依赖说明补齐部署、启动和操作文档，不能只沿用旧 README 的功能宣称。

后续追加要求：“要求写在文件里的方法完整可行，说明功能”。本轮继续补全安装、前置修正、打包启动、联调结束处理以及逐项功能体验，避免只指出阻塞而没有给出解决步骤。

## Scope

更新根目录 `README.md`，并按 `AGENTS.md` 要求在根目录 `doc/` 保存本次事后改造记录。仅修改文档，不执行安装、构建、模拟器启动或外部联调。

本轮额外在 `/tmp/` 的接口文件副本验证 README 内嵌的依赖修正脚本，绝不对项目源文件执行该脚本。沿用并更新本记录，不另建重复事实报告。

## Out of Scope

- 不修改 Rust、ROS 消息、CMake、配置、锁文件、模型或资产。
- 不修复探索发现的双 feature 源码问题、ROS 包依赖声明或包装器旧开关。
- 不安装系统依赖，不配置外部算法客户端，不访问真实硬件或已有 IPC 会话。
- 不执行 Git 暂存、提交、推送、合并或其他版本控制写操作。
- 不验证跨平台运行、渲染性能、命令闭环、协议兼容或实机效果。

## Explorer Findings

### Files inspected

- 规则与原说明：`AGENTS.md`、原 `README.md`。
- 依赖与启动：`Cargo.toml`、`Cargo.lock`、`cargo-wrapper.sh`、`src/main.rs`、`src/setup.rs`、`src/scene.rs`。
- 配置与操作：`config.toml`、`src/config.rs`、`src/systems/controller.rs`、`src/systems/input.rs`、`src/systems/camera.rs`、`src/systems/debug.rs`、`src/systems/gimbal_pid.rs`。
- 物理与功能边界：`src/systems/projectile.rs`、`src/systems/uav.rs`、`src/handler.rs`、`src/robomaster/outpost/`、`src/robomaster/tech_core/`、`src/telemetry/`、`assets/`。
- 采集与 ROS：`src/capture.rs`、`src/capture/`、`src/ros2/topic.rs`、`src/ros2/plugin.rs`、`src/ros2/capture.rs`、`src/ros2/image.rs`、`src/ros2/livox.rs`。
- ROS 类型与构建声明：`rm_interfaces/msg/GimbalCmd.msg`、`rm_interfaces/CMakeLists.txt`、`rm_interfaces/package.xml`、`third_party/r2r_msg_gen/`。
- Talos 与视频工具：`src/talos/plugin.rs`、`src/talos/capture.rs`、`src/talos/ground_truth.rs`、`crates/talos-ipc/src/layout.rs`、`crates/talos-ipc/src/shm.rs`、`crates/talos-ipc/src/publisher.rs`、`src/bin/talos_gimbal_mock_server.rs`。
- 本机 ROS CLI 的 `ros2topic/verb/pub.py` 与 `info.py`，仅检查文档所用参数，不启动 ROS 节点。

系统依赖交叉核对采用 Bevy、r2r、ffmpeg-next 和 ROS 官方仓库文档。另检查 Bevy **v0.19.0** 的 `crates/bevy_asset/src/io/file/mod.rs`，确认资产根目录优先级，避免把当前工作目录误当作直接运行 binary 时的默认资产目录。相关来源链接写入 README；外部说明不替代本仓锁定版本与目标机器验证。

本轮又核对 Bevy **v0.19.0** 的 `Cargo.toml`（`rust-version = 1.95.0`）、ffmpeg-next **v8.1.0** 的兼容说明，以及 ROS Humble 官方 apt 源和 locale 安装说明。当前本机 `rustc` 为 **1.91.1**，低于已确认的 Bevy 依赖要求；未升级本机工具链，README 已提供安装/选择 stable 和版本前置检查。

### Active logic path

主程序创建窗口、物理与配置插件，按 `ScenePlugin` 加载环境和碰撞体，随后生成己方步兵、步兵假人与英雄假人。`ControllerState` 合并键盘/手柄输入；相机、底盘、手动云台及外部目标 PID 根据模式工作。

Cargo 默认启用 `talos`；本地无接口模式显式关闭默认功能；ROS-only 模式关闭默认功能后仅启用 `ros2`。视频 mock 是独立 binary，要求同时启用 `talos`、`ffmpeg`。

当前 `src/main.rs` 的函数参数名 `_app` 与 ROS 条件分支中使用的 `app` 不一致，因此同时启用 ROS/Talos 的构建路径存在源码问题。记录事实并避免在部署命令中选择该组合，没有编译复现或修复。

### Data flow

```text
config.toml + assets/ → 场景/ECS/物理 → 相机离屏采集
  → Talos RGB + 同步 pose → 外部消费者 → IPC 云台目标 → PID / 模拟发射
  或 ROS image_raw + camera_info + TF/pose → 外部算法
    → /rm_gimbal/cmd (rm_interfaces/msg/GimbalCmd) → PID / 模拟发射

视频输入 → FFmpeg 解码/转换 → Talos mock RGB 与模拟 pose → 外部消费者
```

ROS 命令 pitch 变换为 `pitch_deg - 90°`，Talos 路径变换为 `-pitch_deg - 90°`，两条通路不能照抄角度。`distance == -1` / `distance_m == -1` 表示无解；没有明确的失联自动超时清目标机制。键盘 `F5` 与手柄 RT 决定是否启用外部自瞄跟踪。

Talos 同步帧的下一次发布依赖图像及 pose 0–3 被消费；只读图像可能停在第一帧。主程序和 mock 使用相同固定映射文件，不允许两个生产者并行。ROS 点云由虚拟深度图生成，并非真实 Livox 扫描或 `CustomMsg`。

### Risk notes

- 原 README 的 `/armor_solver/cmd_gimbal`、`Q/E`、`U/O`、`F4` 和鼠标拖动说明与源码不符。
- 原“完整自动标注闭环”“CPU/GPU 渲染支持”“高帧率与时间一致性保证”等描述缺少当前实现或验收依据。
- `rm_interfaces` 使用 `std_msgs`，但缺少直接的 `find_package` 与 package 依赖声明，可能阻塞全新 ROS 环境部署。
- `cargo-wrapper.sh` 引用仓库不存在的辅助脚本，旧开关映射到未声明 feature，不应作为可靠部署入口。
- Rust 工具链未固定，完整 MSRV 未声明；已核实至少要满足 Bevy 的 Rust 1.95.0 要求，本机旧工具链不能作为部署基线。原生库、图形驱动、FFmpeg 兼容和 MetalFX 可用性仍需目标机器验证。
- Bevy 启用动态链接，单个 executable 不是完整部署产物。配置依赖当前工作目录，资产路径还依赖 Bevy 环境变量或 executable 位置。
- 热重载替换配置资源不代表窗口、采集尺寸、投影或初始化实体自动重建。
- 有效 Git 元数据不可用，采用修改前备份、文件 diff 和 SHA-256 快照审查；不初始化仓库。

### Recommended modification boundary

仅把已经核对的部署与使用说明写入 README，保留项目名称、作者、团队、演示和许可证信息。邻近源码问题标为已知限制，不借文档任务扩大为功能修复；README 不宣称本次完成了部署或运行验收。

## Modifier Changes

### Files changed

- `README.md`
- `doc/20261012_readme_deployment_usage.md`

### Key changes

1. 重新说明功能、技术栈和源码入口，区分已实现能力与未接入/未验证内容。
2. 增加本地仿真、默认 Talos、ROS-only、FFmpeg mock 四种模式，明确 package、binary、features 和锁文件使用。
3. 补充 Rust/图形/原生依赖、ROS overlay 生成与 source 顺序、目标机器分发与动态库限制。
4. 为直接运行 executable 补充 `BEVY_ASSET_ROOT`，区分配置工作目录和资产定位。
5. 修正键盘控制，增加手柄操作、自由视角注意事项、截图覆盖与调试组合键说明。
6. 列出实际 ROS topic/类型、系统时间与点云限制，提供 `fire_advice: false` 的命令示例。
7. 说明 Talos version 2、固定文件、尺寸、pose 顺序、消费握手、角度变换和单生产者限制。
8. 增加配置当前值、热重载边界、常见故障及后续文档同步要求。
9. 按用户追加要求补上 Ubuntu/Bash 部署基线、Rust 安装与版本门槛、图形环境预检查、首次启动成功条件；ROS 不再只有外部安装链接，补齐官方源与系统包准备步骤。
10. 将 ROS 缺失依赖变为明确的前置修正步骤：内嵌脚本在部署副本中保留备份、检查结构并添加两处声明；再构建接口、检查 overlay 与消息、启动 ROS-only 模式。主仓库依赖文件不变。
11. 补齐默认 Talos 模式 Linux 二进制打包：独立产物目录、动态库识别与拷贝、配置/资产/许可证、运行脚本、目标机器依赖检查与启动，不覆盖旧包。
12. 新增 15 项功能的“怎么用 / 应观察什么 / 实现边界”；补充 Talos 单生产者/单消费者与接入检查、ROS/Talos 清目标顺序、mock 开始前的 IPC 检查和 FFmpeg 开发库检查。

### Behavior preserved

所有源码、资产、参数、默认 features、消息/IPC 布局和运行行为保持不变。`AGENTS.md` 与上一任务记录保持不变；本次没有新增或删减功能，仅校正使用说明。

### Behavior intentionally adjusted

没有运行行为调整。文档不再推荐存在已知问题的功能组合或包装器开关，不再把未接入/未验证能力描述为完整功能。

内嵌 ROS 前置修正与打包脚本是给操作者的具体部署操作，分别会修改其部署副本的接口声明、生成 target/dist 产物；README 已明示这些影响。本次没有在项目目录执行这些步骤。

### Notes

没有启用子 Agent；探索、修改和独立复查由主 Agent 完成，不虚构多 Agent 审计。文档中的安装、构建、启动和 ROS 命令仅做语法/契约检查，没有实际执行。

临时检查最初假定 Python 提供 `tomllib`，但当前 Python 为 3.10；改用已安装的 `tomli`，未安装依赖。检查器另修正了 `cargo --version` 与 ROS 消息类型名的分类，随后完整检查通过；这些中间检查器错误不属于项目构建失败。

追加完整性复核使用独立临时副本验证 ROS 修正脚本的首次执行、重复执行、备份内容与源码结构不匹配时的非零退出；版本检查也确认能拒绝本机 Rust 1.91.1。对 README 内嵌 `run.sh` 仅检查 Bash 语法与目录/资产根/动态库环境契约，没有伪造已编译程序进行运行验收。

打包脚本的动态库路径解析使用含空格路径样本检查通过，并核对构建机和包内两个 `not found` 阻断条件；未执行真实打包或启动。

## Auditor Review

### Checks performed

- [x] 关键路径及 feature 注册检查：交叉核对 main、manifest、场景和两条通信路径。
- [x] diff 和修改范围检查：首次任务对 156 个已有文件建立快照；追加完整性复核对包括本记录在内的 157 个已有非生成文件建立 SHA-256 快照，使用修改前备份进行 diff，最终变动仅为 README 与本记录。
- [x] 关键符号及接口读写方搜索：控制映射、自瞄门控、角度转换、无解处理、采集尺寸和 Talos 背压。
- [x] Cargo/TOML/ROS 接口/资源路径检查：只读 `cargo metadata --no-deps --offline --format-version 1` 成功；本轮 6 条 Cargo 构建/启动示例与实际 binary/features 契约一致，避免同时启用 ROS/Talos；23 个源码/资源/消息引用和 12 个 ROS topic 引用核对通过。首轮核对的 34 项配置值和对应表项保持不变。
- [x] 文档静态检查：本轮 21 个 fenced blocks 闭合；18 个 Bash 代码块及内嵌启动脚本通过 `bash -n`，不执行部署命令；2 段 Python AST 合法；2 条 ROS 示例 YAML 与 `GimbalCmd.msg` 字段一致且关闭开火建议；TOML、消息字段、演示图与许可证路径、章节编号核对通过。
- [x] 前置修正脚本验证：只在 `/tmp/` 的实际接口副本执行，首次添加恰好一份 std_msgs 声明、备份与原文件逐字一致、重复执行无新增变化、结构不匹配时非零退出且不写入；Rust 版本门槛拒绝本机 1.91.1。
- [ ] 编译、图形运行、ROS/Talos 联调、跨平台和实机检查：未授权且不属于本次文档交付的实际验收范围，未执行。
- [ ] 如需构建，已取得用户明确许可：本次没有构建授权。

### Issues found

文档范围内发现的不准确说明已校正。源码中的 ROS/Talos 双 feature 变量名问题、`std_msgs` 依赖声明缺口与包装器旧开关仍存在：前者通过选择单通路避免，ROS 部署必须先执行已提供且经临时副本检查的依赖修正，包装器改用直接 Cargo 命令。主仓库没有修复这些源码，也没有构建验证。整体部署实测还需相容 Rust、GPU/桌面、相应系统库与明确构建/运行授权；外部 Talos 检测算法不是本仓提供的组件，README 没有编造其启动命令。运行时协议兼容、真实图像/pose 与算法响应仍需另行验收。

### Final result

**PASS：本次 README 文档更新与实际执行的静态检查通过。** 不代表项目构建、目标机器部署、图形运行或算法联调通过。

未执行构建：AGENTS.md 禁止在未获用户明确许可前运行构建命令。
