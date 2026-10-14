# 模拟器 AGENTS.md 本地适配 改造记录

## User Intent

将其他 RoboMaster 机器人 ROS 工作区的 Agent 规则适配为本模拟器项目规则。保留双标题、编号章节、最高优先级限制、未授权编译限制、版本控制写操作限制、通用总原则、多 Agent 三阶段框架和事后改造记录要求；项目背景、模块规范、使用与部署依据实际源码重写。后续功能增减需同步维护规则。

用户指定只修改规则文件，并明确要求本次写改造记录、保存到项目根目录新建的 `doc/`。实际文件名为 `AGENTS.md`，因此使用该文件，不另建小写或单数的 agent.md。日期采用用户本地日期 2026-10-12（Asia/Shanghai）。

## Scope

仅修改根目录 `AGENTS.md`；创建 `doc/` 并新增本记录，作为用户明确要求的唯一附加交付。读取源码、配置、资源清单及相关 Skill，执行不触发构建的文档、路径和 manifest 检查。

## Out of Scope

不修改 Rust 源码、Cargo 依赖或 lockfile、TOML 参数、GLB/音频资产、ROS 消息、构建脚本、README、全局规则或已安装 Skill。不修复检查中发现的代码问题，不构建、安装依赖、运行模拟器、连接外部算法或实机，不执行 Git 写操作，不启动子 Agent，不创建治理状态、额外计划或 handoff 文件。

## Explorer Findings

### Files inspected

按模块读取入口、实际实现或定向搜索对应源码；不是仅依据 README 作判断：

- 原根规则、全局规则；Ponytail、agents-md-generator、agents-md-writer、writing-for-agents 的相关说明、writer skeleton 与 lint 脚本。
- `README.md`、`Cargo.toml`、`Cargo.lock`、`config.toml`、`src/main.rs`、`src/config.rs`、`src/scene.rs`、`src/setup.rs`。
- `src/components/infantry.rs`、`src/components/camera.rs`、`src/components/physics.rs`；systems 中 controller、input、gimbal_pid、camera、projectile、uav、debug、chassis_observation 及注册入口。
- `src/robomaster/prelude.rs`、模块注册及 armor 碰撞实现；power_rune 的状态、旋转、碰撞、更新与插件；outpost 旋转/更新；tech_core 的灯光阶段、JSON 和测试符号。
- `src/capture.rs`、`src/capture/driver.rs` 的帧提交、格式转换、缓冲池、纹理复制、异步映射与回调路径。
- `src/ros2/plugin.rs`、`src/ros2/topic.rs`、`src/ros2/prelude.rs`、`src/ros2/capture.rs`、`src/ros2/livox.rs`。
- `src/talos/plugin.rs`、`src/talos/capture.rs`、`src/talos/ground_truth.rs`；talos-ipc 的 layout、shm、publisher、subscriber、triple_buffer 与 manifest。
- `src/bin/talos_gimbal_mock_server.rs`、`src/telemetry/`、`src/handler.rs`、`src/statistic.rs`；exact 的实现/manifest，bevy_metalfx 的 manifest/公共插件及平台边界。
- `rm_interfaces/msg/GimbalCmd.msg`、`rm_interfaces/CMakeLists.txt`、`rm_interfaces/package.xml`；本地 `third_party/r2r_msg_gen` 的 manifest 与生成器条件 ABI 定义。
- `cargo-wrapper.sh`、`.gitignore`、`.githooks/pre-commit`、`.vscode/settings.json` 和 `assets/` 文件清单。

### Active logic path

主体是 Rust edition 2024 的 `daedalus` 包；workspace 还含 exact、talos-ipc、bevy_metalfx。manifest/lockfile 确认 Bevy 0.19、Avian3D 0.7、bevy-inspector-egui 0.37，默认启用 talos，可选 ros2 / ffmpeg；ROS 接口包是附属资源，不是旧规则所描述的 sentry_ws 工作区。

`main` 装配 Bevy、Avian、RoboMaster、场景和配置插件；ScenePlugin 按环境、碰撞体就绪、机器人顺序加载。输入汇入 ControllerState，系统分组处理控制、逻辑、摄像机和清理；底盘观测及发射在 PostUpdate 的 Transform 传播后处理，气动力在 FixedUpdate。外部云台目标通过限速 PID 跟踪。

场景和系统代码包含步兵/英雄假人、装甲板、前哨站、科技核心、大小能量机关、球形弹丸、飞镖、可选气动力、截图、键盘/手柄和多视角。UAV 按键路径只创建静态模型。通用 TelemetryPlugin 未在 main 注册，dispatch 中的标注与 pose 仍为空，不能宣称完整数据集导出。

### Data flow

```text
Cargo features + config.toml -> 主入口与插件选择
ScenePlugin + setup -> 模型节点/碰撞体/机器人组件
键盘/手柄 -> ControllerState -> 机器人/摄像机
外部 ROS/Talos 命令 -> GimbalAimTracker -> PID -> 云台
离屏相机 -> GPU 回读 -> ROS 图像或 Talos 快照发布
ROS 深度 -> reverse-Z 重建 -> Livox 风格 PointCloud2
fire_advice/手动发射 -> projectile_launch -> 能量机关 CollisionEnd -> 状态与统计
Talos -> 图像/内参/pose/底盘观测/有限真值/runtime_state/heartbeat
```

ROS 实际订阅 `/rm_gimbal/cmd`，类型为 rm_interfaces/GimbalCmd，sensor_data QoS；topic 定义使用绝对路径。默认 publish_compressed 为 false。Talos 通过 `/tmp/talos_ipc_meta` 和 `/tmp/talos_ipc_image_pool` 映射文件通信，协议 magic 为 0x54414C05、version 为 2，固定 RGB 图像尺寸为 1440×1080；不是 POSIX /dev/shm，也不是端到端 GPU 零拷贝。

### Risk notes

1. README 的云台订阅 topic、部分旋转按键和 F4 说明与源码不一致；规则采用源码事实，README 本轮不修改。
2. `config.toml` 热重载更新配置资源及物理时钟/子步，不自动重建所有已初始化相机、材质、冷却或采集资源；Talos 分辨率不直接使用 capture.color 配置。
3. `cargo-wrapper.sh` 的旧关闭 ROS 开关会导向 manifest 未定义的 no-r2r feature；当前本地 env.sh / build.sh 不存在，不能作为复现步骤。新规则给出按 manifest 选择 feature 的命令，并标明尚未构建/运行。
4. 模拟器与视频 mock 都是同名 IPC 文件的生产者，创建会截断文件；增加了多会话保护，不运行两个生产者验证。
5. 命中统计只针对有效 RuneHit；深度点云不是真实扫描时序模型；机器人/能量机关真值含占位字段，不能扩大为完整传感器/裁判仿真。
6. `src/main.rs` 的 should_enable_talos_plugin 参数名为 `_app`，ros2 条件分支却读取 `app`；两个 feature 同时启用时存在明确的标识符不一致。仅静态发现，未构建复现，本轮不修复。规则将双 feature 行为表述为选择意图且要求独立验证，ROS 命令使用 `--no-default-features --features ros2`。
7. 本地 `.git` 目录存在，但只读 rev-parse 未确认有效仓库；因此没有运行 git diff/status，而使用修改前备份及 SHA-256 范围检查。

### Recommended modification boundary

保留原文的规则层级和通用治理；将场景/ECS、控制/PID、物理/碰撞、RoboMaster 目标、采集/传感器、渲染、ROS、配置、Talos 规范映射到原第 6–13 节。记录路径改为 doc；环境与部署只写 manifest/代码支持的命令和必要前置条件，不引入旧项目 Conda、Nav2、行为树、自瞄检测节点或串口约束。

## Modifier Changes

### Files changed

- `AGENTS.md`：本地适配，保留双标题、0 / 0.1 / 0.2 / 0.3 及 1–18 的章节次序、三级角色、记录模板、编号禁令与内部阶段示例。
- `doc/20261012_agents_local_adaptation.md`：本次事后事实、修改和审计材料。

### Key changes

编译禁令覆盖 Cargo 的 build/check/test/run/clippy/doc 等会触发构建的命令，产物目录适配 Rust target 与可选 ROS 接口包。原 0.1 版本控制写操作和 0.2 禁止计划工具章节保持逐字一致。

项目背景补齐源码目录、技术栈、features、功能边界、实际按键与数据链；后续规范覆盖真实模块与跨模块契约。记录目录统一为根 doc；第 18 节明确新功能、删除功能或入口/接口/配置/部署变化时同步维护规则，授权范围不足时只指出缺口。

### Behavior preserved

没有改变任何模拟器、物理、控制、通信或配置运行行为；保留最小完整修改、授权构建、禁止 Git 写操作、多 Agent 显式启用和证据分层等约束。没有启用子 Agent，也未虚构独立审核。

### Behavior intentionally adjusted

仅调整 Agent 在本仓库中的工作指引：不再使用旧 sentry_ws 的路径、构建入口和模块要求；改为本项目的 Cargo features、资产层级、仿真/通信边界及根 doc 记录路径。仿真内控制不再被误当成真实硬件运动。

### Notes

用户已明确批准本次规则改写和记录创建，未额外发起设计问卷或二次确认。agents-md-generator 的 Design / Docs And Memory 分支要求额外问卷、状态与 handoff，agents-md-writer 的 Path C 要求改写前再次确认，其分层建议还会增加其他 AGENTS 文件；这些与本次明确范围和结构要求冲突，按用户要求不采用。只复用事实核验、写作和静态 lint，不修改全局或 Skill 安装。

修改前备份保留在 `/tmp/daedalus-agents-20261012/AGENTS.before.md`，用于无 Git 元数据时的 diff 和必要恢复；检查临时 JSON/diff 在收尾清理，不放入仓库。

## Auditor Review

### Checks performed

- [x] 关键路径及 feature 注册检查：源码逐模块核验；offline/no-deps Cargo metadata 退出码 0，核对 edition、默认 talos、可选 features 及 mock 的 talos+ffmpeg required-features。
- [x] diff 和修改范围检查：与修改前备份比较；修改前 155 个非生成文件的 SHA-256 清单中，154 个非 AGENTS 文件保持一致。最终扫描确认只有 AGENTS.md 修改、本记录新增。
- [x] 关键符号及接口读写方搜索：规则中 6 条只读 rg 示例均实际执行并返回匹配。
- [x] Cargo / TOML / ROS XML / 资源路径检查：6 个 TOML 文件使用现有 tomli 解析、ROS package.xml 使用 ElementTree 解析；规则中 20 个行内源码/资源路径、27 个目录索引条目和 10 个运行时模型/音效文件检查存在。
- [x] 文档静态检查：双标题、22 个编号主章节、代码围栏、尾随空白、旧工作区路径/配置残留检查通过；0.1 / 0.2 与旧文件严格一致。
- [x] AGENTS writer lint：退出码 0、0 error、15 warning。4 条是尚未生成的 target/build/install/log，10 条是被通用脚本误当文件路径的 ROS topic（包含历史错误 topic 与明确未发布的 /clock），1 条是 495 行长度建议。按源码与文义复核，无失效源码路径；用户要求保留结构并只改根规则，因此不拆分文件。
- [ ] 构建与 Rust 单元测试：无构建授权，未执行。
- [ ] 图形仿真、ROS/Talos/FFmpeg 联调、跨平台及实机验收：文档任务，不执行、不宣称通过。

静态校验脚本的标题正则曾要求 0.1 / 0.2 后存在尾点，补充索引检查时也曾误判首个文本块，导致检查器断言失败；修正为兼容原文标题并按块内容选择索引后重跑通过。这些是临时检查器问题，不是文档或产品故障，未将失败记作通过。

### Issues found

本次规则适配没有待修复问题。原源码中双 feature 的 `_app` / `app` 不一致、旧 wrapper feature 和 README 过时内容已记录，属于只读发现且超出本轮修改范围。使用/部署命令经声明核验，但没有构建或动态成功证据；未因此声称模拟器、全部 features 或外部算法闭环已验收。

### Final result

**PASS**：仅表示本次 AGENTS.md 本地适配及实际执行的文档/静态范围检查满足要求，不表示产品构建、运行或联调通过。

未执行构建：AGENTS.md 禁止在未获用户明确许可前运行构建命令。
