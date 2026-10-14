# AGENTS.md

# 项目 Agent 行为准则

本文件是本仓库中 AI 编码 Agent 的统一行为规范。所有代码修改、审计、重构、调参和文档任务都应先读取并遵守本文件。

本仓库是 Daedalus RoboMaster 视觉算法验证模拟器，主体为 Rust / Bevy 应用，不是机器人 ROS 工作区。它通过场景、物理、离屏图像采集及可选 ROS 2 / Talos 通信，为外部自瞄和打符算法提供仿真输入与控制反馈。修改以可复现、最小完整改动和可审计为原则；源码存在、编译通过、仿真运行和外部算法联调是不同验证层级，不能互相替代。

---

## 0. 最高优先级限制：编译构建限制

未经用户明确允许，禁止执行会触发编译、链接或代码生成的命令，包括 `cargo build`、`cargo check`、`cargo test`、`cargo run`、`cargo clippy`、`cargo rustc`、`cargo doc`、`colcon build`、CMake、Make、Ninja，以及间接调用这些命令的脚本。允许只读搜索、文件检查、TOML / XML / Python 静态解析、`cargo fmt --all -- --check` 和确定不触发构建的检查。需要构建时，先说明命令、package / binary / feature 范围和产物目录，取得授权后执行。

同一任务已明确获得的构建授权持续有效，不重复询问。不能确认命令是否触发构建时，先检查脚本；仍不能确定且没有相应授权时再询问。执行已构建程序不等于构建授权，且仍须遵守第 0.3 节的外部系统边界。

Rust 命令从仓库根目录执行，默认产物位于 `target/`；改变 `CARGO_TARGET_DIR` 时应说明实际位置。可选 ROS 接口包的产物使用根目录 `build/`、`install/`、`log/`。不得手工修改这些生成目录，应修改源码或配置后在授权范围内重新构建。

`cargo-wrapper.sh` 不是强制构建入口：它默认追加 `--release`，可调用本地 `env.sh` / `build.sh`，并把 `--no-r2r` / `--no-ros2` 转换成当前 manifest 未声明的 `no-r2r` feature。使用前必须核对脚本与实际文件，不得把这些旧开关当作有效启动方式；直接使用 manifest 中的 feature。

## 0.1 最高优先级限制：版本控制写操作

禁止执行会改变 Git 索引、历史、分支、标签或远端状态的操作，包括 `git add`、`commit`、`push`、`merge`、`rebase`、`tag`、`cherry-pick`、`revert`、`reset`，以及会覆盖工作区的 `restore` 或 `checkout`。只读的 `git status`、`git diff`、`git log` 和 `git show` 可以使用，但仅在存在有效 Git 元数据时执行。

Agent 只负责已授权的工作区修改和说明，不主动暂存、提交、推送、合并或发布；`gh pr merge`、`gh release create` 等远端写操作同样受此限制。

## 0.2 最高优先级限制：禁止 writingplans / 计划说明工具

禁止使用 `writingplans`、Superpower writing plan 或类似工作流生成独立计划、改造计划、测试计划或阶段说明文件。

1. 需求与边界明确后直接修改，不把额外计划说明作为阻塞步骤。
2. 允许简短执行摘要、必要的内部分析和最终检查结果。
3. 风险、边界和检查项写入事后改造记录，不以计划代替实际仓库检查。
4. 多 Agent 仅在用户明确要求时使用，不因本文件列出角色就自动启动。

## 0.3 最高优先级限制：仿真运行与外部系统安全

仿真内移动、云台控制和弹丸发射属于模拟器功能，不等于真实硬件操作。未经用户明确要求，不访问真实串口、相机或 LiDAR，不启动外部机器人硬件，不将仿真命令接入实机。ROS 2 动态检查需核对发现域、网络范围和现有订阅者，避免影响真实系统；仅改变域号不能证明已经隔离实机。

Talos 使用固定名称的映射文件；模拟器与 mock 程序都会创建并截断同一组文件。启动前确认没有其他生产者或正在使用这些文件的会话，不并行运行两个生产者，不擅自删除或覆盖他人的 IPC 文件。清理仅针对本次记录的 PID、进程组和确认属于本次的产物。

不得把编译、窗口启动、截图、话题出现或 IPC 文件存在表述为完整算法闭环、真实传感器或实机射击验收通过。

---

## 1. 项目背景

```text
Cargo.toml                       Rust workspace、依赖、features 和二进制入口
Cargo.lock                       已解析依赖版本
start.sh                        Linux x86_64 Conda 隔离安装、构建与图形启动入口
environment.yml、conda-linux-64.lock  原生工具链/依赖清单及完整 explicit 锁
.runtime/                       项目专用环境、Conda/Cargo 缓存和按模式隔离的产物
config.toml                      仿真、渲染、采集和控制参数
src/main.rs                      应用入口、插件装配及系统调度
src/config.rs                    TOML 加载、默认值与文件监听热重载
src/scene.rs                     异步场景加载顺序与碰撞体就绪等待
src/setup.rs                     摄像机、模型节点绑定、机器人及碰撞体初始化
src/components/                  摄像机、机器人、弹丸和碰撞层组件
src/systems/                     键盘/手柄、底盘、云台 PID、弹丸、视角及观测
src/robomaster/                  装甲板、能量机关、前哨站、科技核心及外观状态
src/capture.rs、src/capture/      离屏摄像机、GPU 回读、深度和纹理复制
src/ros2/                       可选 r2r 话题、TF、图像和深度点云
src/talos/                      可选图像/位姿/真值发布及云台命令接收
src/telemetry/                  通用遥测接口；未接入主入口，不是完整标注导出
src/handler.rs、src/statistic.rs  能量机关事件响应和发射/有效命中统计
src/util/                       层级查询、异步 World 操作及辅助逻辑
src/bin/talos_gimbal_mock_server.rs  FFmpeg 视频输入与 Talos 命令接收工具
crates/talos-ipc/                内存映射、共享布局、三缓冲和发布/订阅
crates/bevy_metalfx/             macOS MetalFX 渲染集成
crates/exact/                    定长迭代结果提取与所有权处理
rm_interfaces/                  可选 ROS 2 消息/服务定义，ament_cmake 包
third_party/r2r_msg_gen/         Cargo patch 使用的本地消息生成依赖
assets/                         GLB 场景/机器人/飞镖及 OGG 音效
.githooks/pre-commit             cargo fmt 检查；文件存在不代表钩子已安装
doc/                           本项目事后改造记录
```

### 1.1 技术栈与功能边界

- 主包名与默认 binary 为 `daedalus`，Rust edition 为 `2024`。根 manifest 声明 Bevy `0.19`、Avian3D `0.7`、bevy-inspector-egui `0.37`，启用 Bevy `dynamic_linking`；版本以 manifest 与 lockfile 为准。
- Bevy ECS 管理实体、层级和调度，Avian3D 提供刚体、重力、碰撞及固定步进；notify + serde + toml 实现配置加载与重载，crossbeam / futures 等参与异步通信与回读。
- 场景包含地面、标定板、红蓝前哨站、科技核心、大/小能量机关、己方步兵与步兵/英雄假人；支持装甲外观、机器人运动、云台 PID、弹丸与飞镖发射、可选气动阻力、命中事件、手柄反馈和视角切换。
- `talos` 是默认 feature，通过 `memmap2` 映射文件发布图像、内参、位姿、底盘观测、机器人/能量机关真值及运行状态；`ros2` 默认关闭，通过 `r2r` 接入 ROS 2；`ffmpeg` 只在视频 mock 等需要时开启。
- ROS 路径可从离屏深度重建 Livox 风格 `PointCloud2`；这不是实际 Livox 驱动或扫描时序模型。`P` 键生成的 UAV 当前是静态模型，不是完整飞行动力学。
- 外部算法不在本仓库实现。未接入的 `TelemetryPlugin`、空的通用标注数据和采集层的 `R32Uint` 能力不能当作已完成的数据集或实例分割输出；英雄模型也不能据此宣称具有独立的 42 mm 弹道。

### 1.2 当前入口、数据链与使用方式

```text
Cargo features + config.toml -> main -> 插件注册 / Startup / ScenePlugin
模型层级 + 输入 -> 底盘/云台 -> Transform 传播 -> 弹丸与底盘观测
CaptureSource -> 离屏摄像机 -> GPU 回读 -> ROS 图像或 Talos 同帧快照
外部云台命令 -> GimbalAimTracker -> 速率受限 PID -> 云台姿态
fire_advice -> 仿真 projectile_launch -> 碰撞事件 -> 能量机关状态/统计
```

当前键盘入口以 `src/systems/controller.rs` 为准：己方 `W` / `A` / `S` / `D` 移动、方向键控制云台、`Space` 发射、`Q` 切换底盘旋转、`ShiftLeft` 加速、`G` 发射飞镖；假人 `I` / `J` / `K` / `L` 移动、`U` 切换旋转、`C` / `B` 与 `F` / `V` 控制云台、方括号和分号/引号控制底盘倾斜。`Tab` 切换活动假人，`F3` 循环机器人/第三人称/自由视角，`F5` 切换自瞄接收，`F2` 截图。手柄映射和自由视角操作分别检查 controller 与 camera 实现。

`Shift+C` 同时被装甲外观、前哨站旋转和科技核心阶段调试使用，修改前必须检查全部消费者。README 中旧的 `Q` / `E`、`U` / `O` 和 `F4` 说明不能直接用作当前功能依据。

运行时从项目根目录读取 `config.toml` 并加载 `assets/`；使用与部署命令及前置条件见第 14.2 节。同时编译 `ros2` / `talos` 时，选择逻辑意在 ROS 采集资源已存在的情况下跳过 Talos；`DAEDALUS_FORCE_TALOS_CAPTURE=1` 可覆盖这个选择。该组合须单独构建与运行验证，不能据此认定双采集相机、共享资源和控制权无冲突。

---

## 2. 总原则

1. 先确认真实入口、调用链、参数来源和现有测试，再修改。
2. 用户未要求重构时，选择能修复根因的最小完整改动；不顺带清理、重命名或重构无关模块。
3. 不擅自改变 ECS 组件契约、模型节点名、topic、frame、QoS、IPC 布局、配置键、仿真规则或模块边界。
4. 不删除历史策略、兼容分支或注释方案，除非它们已证实有害且属于任务范围。
5. 不在高频系统或每帧采集中添加逐帧日志或无用统计；不把 README、历史报告或推断当作当前源码事实。
6. 不为局部修复引入大量变量、函数、类或新框架；保留原有职责边界和行为优先级。
7. 不擅自改变固定步进频率、物理子步、系统顺序、线程边界、插件组合或控制权。
8. 涉及已验证策略时优先保留其行为；每次非平凡修改按第 4 节留下记录。

```text
最小完整修改 > 局部结构调整 > 大范围重构
```

---

## 3. 用户确认时使用多 Agent 工作流

用户明确要求三阶段流程时使用：

```text
Explorer Agent → Modifier Agent → Auditor Agent
```

多 Agent 通过角色隔离降低误判风险，不并行修改共享状态，不以计划说明代替真实仓库检查。不启动子 Agent 时，由主 Agent 完成事实确认、修改和复查，不虚构独立审计。

### 3.1 Explorer Agent：探索与事实确认

Explorer 只读仓库，不修改文件；向主 Agent 返回可写入事后记录的探索结果。

1. 找到相关 Rust 源码、Cargo features、TOML、GLB 使用方、ROS 接口和现有测试。
2. 梳理插件注册、schedule / system set、实体层级、资源读写、跨线程快照及通信生产者/消费者。
3. 区分当前启用路径、feature 条件路径、未注册接口和历史说明。
4. 标记已有验证证据、隐式依赖与冲突，给 Modifier 明确修改边界。

必须检查实际入口、查询筛选条件、局部/全局变换、参数默认值与加载来源、线程/缓冲所有权、静态或 Local 状态，以及用户明确不能修改的内容。涉及 ROS / IPC 时检查类型、布局、频率、时间戳和外部约定；不能只看同名字段。

### 3.2 Modifier Agent：最小修改

Modifier 根据已确认事实与用户目标修改授权文件。

1. 保留原行为优先级和职责边界，不顺带清理、重命名、调参或修改其他模块。
2. 同步受影响的配置说明、接口使用方和必要文档；事实不足时先补充检查，不扩大范围。
3. 不擅自修改模型节点名、feature 默认值、topic / frame / QoS、共享布局或角度约定。
4. 修改后由主 Agent 汇总改造记录；代码 worker 说明实际修改文件。

### 3.3 Auditor Agent：审计与验收

Auditor 不相信 Modifier 的自述，独立检查 diff、关键符号和真实调用路径。

1. 检查是否越界，是否破坏系统顺序、碰撞规则、控制权、坐标约定及图像/位姿同步。
2. 执行授权范围内的静态检查；需要编译时先核对本任务的授权及 feature 范围。
3. 区分文档、静态、构建、仿真、IPC / ROS 联调和实机证据，给出 `PASS` 或 `NEEDS_FIX`。

发现问题后记录准确原因，由 Modifier 针对性修复，不进行大范围自行改造。

---

## 4. 改造记录要求

每次非平凡任务默认在项目根目录 `doc/` 新建或更新记录：

```text
doc/<YYYYMMDD>_<task_name>.md
```

日期使用用户当前本地日期；用户指定记录路径或明确要求不写记录时，以用户要求为准。记录是**事后审计材料**，不是 writingplans 或修改前计划；不得为生成计划中断已确认的修改。

已有专项报告时优先引用或更新原报告，不复制事实正文。无有效 Git 元数据时使用修改前备份进行 diff，不初始化仓库来完成审查。备份和检查临时文件放在临时目录，收尾清理不再需要的临时文件，保留交付物及必要恢复材料。

记录文件必须包含：

```md
# <任务名称> 改造记录

## User Intent
用户原始目标和关键约束。

## Scope
本次允许修改的范围。

## Out of Scope
本次明确不处理的内容。

## Explorer Findings
### Files inspected
### Active logic path
### Data flow
### Risk notes
### Recommended modification boundary

## Modifier Changes
### Files changed
### Key changes
### Behavior preserved
### Behavior intentionally adjusted
### Notes

## Auditor Review
### Checks performed
- [ ] 关键路径及 feature 注册检查
- [ ] diff 和修改范围检查
- [ ] 关键符号及接口读写方搜索
- [ ] 涉及的 Cargo / TOML / ROS 接口 / 资源路径检查
- [ ] 用户允许范围内的测试或静态检查
- [ ] 如需构建，已取得用户明确许可

### Issues found
### Final result
PASS / NEEDS_FIX
```

不适用或未运行的检查必须说明原因，不勾选成通过。最终交付包含修改摘要、文件列表、检查结果、记录路径和 `PASS` / `NEEDS_FIX`；未构建时使用第 15 节的固定说明。

---

## 5. 修改前必须建立任务边界

修改前在内部确认边界，事后写入记录，不额外生成 writingplans 文档。

### 5.1 本次修改属于哪个模块

明确属于场景/ECS、机器人控制、弹道/碰撞、RoboMaster 目标、图像/深度、渲染、ROS、Talos、配置、工具或文档。找到真实入口、插件注册、feature 条件和资源来源；未注册或未启用的实现不能冒充当前路径。

### 5.2 本次修改目标是什么

区分 bug 修复、仿真规则调整、性能优化、接口改造、参数暴露、工具接入或文档适配。修改共享契约前列出全部本地生产者/消费者及需核对的外部端；邻近问题只记录，不擅自扩展。

### 5.3 是否允许改变运行行为

区分原行为保持、指定故障修正和用户要求的新行为。明确应保持和有意调整的效果，分别说明静态、构建、图形仿真、ROS / Talos 联调和实机验证的覆盖范围。

### 5.4 是否涉及已验证仿真或算法联调逻辑

以记录、测试和可复现实验为证据；涉及已有验证逻辑时采用最小改动并注明依据。没有证据时标为未核实，不因 README 使用“完整”“高保真”“零拷贝”就推断规则符合赛事或接口已联调。

---

## 6. 场景加载 / ECS 调度修改规范

入口为 `src/main.rs`；`ScenePlugin` 在 `src/scene.rs` 中顺序加载环境、等待碰撞体就绪，再生成机器人。初始化职责位于 `src/setup.rs` 与各 RoboMaster construct 模块。

1. 保持环境碰撞体先于动态机器人就绪，检查异步任务、observer、延迟 Commands 和实体销毁的交互；不能把资源已加载等同于碰撞体已建好。
2. 修改 GLB 或层级查询前核对 `VEHICLE`、`BASE`、`GIMBAL`、`SHOT_DIRECTION`、`CAM_DIRECTION`、`DART_LAUNCH_DIRECTION` 等实际约定及全部查询者。
3. 保持 `Controlled`、`SlapperInfantry`、`ActiveSlapper` 在根和子实体上的绑定，以及 `Single` 查询唯一性；缺实体和重复实体均需检查。
4. 输入按 `Input → GameLogic → Camera → Cleanup` 组织；底盘观测和发射在 `PostUpdate` 的 Transform 传播后执行，气动力在 `FixedUpdate` 执行。改变 schedule / chain / before / after 前检查实际可建立的顺序，不把跨 schedule 的标签写成已保证顺序。

---

## 7. 机器人 / 输入 / 云台控制修改规范

输入源先汇入 `ControllerState`，再由 input、camera 和 gimbal_pid 系统消费；外部命令来自 ROS 或 Talos，不是本仓库内的识别解算器。

1. 修改键盘或手柄映射时同步检查帮助文本、边沿触发、持续输入、死区、加速与震动反馈；检查组合键的全部消费者。
2. 保持己方和活动假人的查询边界、`Tab` 切换及自由视角对己方移动的限制，不把两个主体输入混用。
3. 手动云台和自瞄通过 `SubscribeAutoAim` 切换；默认关闭。命令接收与 PID 执行均需检查开关和无目标路径，不额外声称已经实现命令过期超时。
4. `GimbalAimTarget::from_solver_degrees` 接收角度制并将 pitch 减去 90°；Talos 接收侧另对 pitch 取负。保留枪口挂载偏移、底盘旋转、局部误差、yaw 环绕、积分限制、速率限制及 pitch 限幅。
5. `distance == -1` / `distance_m == -1` 清除 tracker；检查首个目标、连续更新、无解、开关切换及无实体路径。改变退出或过期策略需用户目标支持，不能静默保留有效目标的假象。

---

## 8. 物理 / 弹道 / 碰撞修改规范

`src/systems/projectile.rs` 提供通用球形弹丸、飞镖、可选气动力与寿命清理；碰撞层定义位于 `src/components/physics.rs`。重力、fixed Hz 和子步来自入口及配置。

1. 核对长度、质量、速度、角速度和角度单位，以代码与 TOML 数值为准，不信任与数值冲突的注释。
2. 保留发射位置/方向的枪口变换、底盘速度继承、冷却、寿命及外部 `fire_advice` 触发；检查手动和外部发射共用路径，不能随意绕过限制。
3. 飞镖使用独立模型、方向修正及硬编码物理量，不直接套用通用弹丸参数；气动系统当前排除飞镖。英雄存在不等于独立大弹丸模型已实现。
4. 检查己方/对方弹丸、车体、装甲与环境的 collision layers；现有弹丸不与车体 collider 或其他弹丸碰撞，不用“更真实”为由改掉测试场景。
5. 能量机关通过 `CollisionEnd` 处理命中并去重；改变碰撞事件阶段、实体祖先查找或事件消费时检查重复命中、失效实体及统计语义。性能调优不得直接改变 fixed Hz / substeps 来掩盖问题。

---

## 9. RoboMaster 目标 / 状态机修改规范

生效插件由 `src/robomaster/prelude.rs` 注册，目标实现位于 armor、power_rune、outpost 和 tech_core 模块。

1. 装甲板改动核对 Team、ArmorLabel、大小、贴图选择、灯条、模型命名、碰撞体与 TF / marker 使用方；视觉标签与机器人配置保持一致。
2. 能量机关改动同步检查 state、rotation、visual、collision、construct 及 Talos 真值；覆盖大小模式、主/副目标、错误命中、超时、激活/失败/重置与旋转正负方向。
3. 保留现有随机策略和兼容模式，不将随机参数或仿真状态宣称为赛事规则的权威实现。复现问题时记录场景、模式及随机性影响。
4. 前哨站改动核对红蓝构造、装甲注册和 Forward / Stopped / Reverse 调试顺序；科技核心改动核对阶段 ID、灯组/段位、闪烁、流动效果及 JSON 状态输出。
5. `ProjectileStatistics` 的 accurate 当前来自有效 `RuneHit`，不是所有装甲命中的统一命中率，更不是完整裁判扣血、赛程或计分系统。

---

## 10. 图像 / 深度 / 传感器采集修改规范

共享采集层位于 `src/capture.rs` 和 `src/capture/`，ROS 与 Talos 分别注册 handler；当前是 GPU 离屏渲染与异步 CPU 回读，不是端到端零拷贝或已验证的软件渲染。

1. 核对 `CaptureSource`、采集/预览相机、render target、纹理格式、相机顺序及主 World / RenderApp 边界，避免双重渲染或同名资源相互覆盖。
2. 保留 GPU copy 行对齐、RGBA / BGRA 到紧密 RGB8 转换、buffer / frame pool 回收及异步快照生命周期；检查非对齐宽度、映射失败与格式不匹配。
3. Talos 图像、pose、序号和时间戳来自同一 Extract 快照；改变回读排队或发布顺序时不能拿新位姿配旧图像，也不能仅凭时间戳断言全部输出同步。
4. 内参按输出分辨率与垂直 FOV 推导，当前畸变为零。曝光、白平衡、噪声及真实标定效果不能在未实现时当作已支持。
5. 深度为 reverse-Z，ROS 点云按 near / depth 还原并做 near / far 过滤；输出为 `sensor_msgs::msg::PointCloud2`，字段为 x/y/z/intensity/tag/line、point_step 为 18。保留字节顺序、坐标方向、frame_id 和发布限频。
6. 点云只是视锥内深度采样，tag / intensity 与 line 来自模拟配置或像素分组；不能描述成全向 LiDAR、逐点真实时间、Livox CustomMsg 或已完成下游定位算法联调。

### 10.1 底盘观测 / 真值修改规范

`src/systems/chassis_observation.rs` 从己方根实体刚体状态计算观测，Talos 另发布机器人/能量机关真值。

1. 保持世界到车体系转换、轮序 `[FL, FR, RL, RR]`、轮半径及线速度/角速度单位；区分刚体根实体旋转与视觉 BASE 的旋转，不能混称同一测量。
2. 保留首次采样、dt 非正、缺失/重复实体的处理，检查差分加速度和上一帧状态重置。
3. gyro / accel 当前是运动学派生量，不是含重力、偏置或噪声的完整 IMU；真值中的占位字段、有限容量和未收集目标必须说明，不伪装成已测量数据。
4. 保留专用 chassis_observation 与旧 pose slot 4 的兼容含义，接口调整同步检查共享布局和外部消费者。

### 10.2 渲染 / 平台优化修改规范

1. Bevy/wgpu 为当前图形路径；Linux/WSL 有条件 adapter 设置，MetalFX 实现仅在 macOS 编译。不能从一个平台的结果推断其他平台可用。
2. MetalFX 改动核对颜色、深度、运动向量、jitter、目标尺寸及历史重置；frame generation 还受操作系统版本和 GPU 能力约束，不能仅凭配置开启宣称可用。
3. 明确 present mode、preview、FXAA、阴影、诊断和 inspector 对开销的影响；性能结论记录 feature、配置、场景、平台和测量，不无依据提高频率或关闭功能。

---

## 11. ROS 2 通信修改规范

ROS 通过 `ros2` feature 与 `src/ros2/plugin.rs` 启用，节点名为 `simulator`、namespace 为 `robomaster`，但 topic 定义使用绝对路径，不自动加该命名空间。

1. 发布接口以 `src/ros2/topic.rs` 为准：`/camera_info`、`/image_raw`、`/image_compressed`、`/livox/lidar`、`/tf`、`/simulator/marker`、各 pose 及 `/simulator/tech_core/state`。注册 publisher 不代表一定有数据；当前图像 context 的 publish_compressed 为 false。
2. 实际订阅为 `/rm_gimbal/cmd`，类型是 `r2r::rm_interfaces::msg::GimbalCmd`，QoS 为 sensor_data；不是 README 中的 `/armor_solver/cmd_gimbal`，也不是其他仓库的同名消息。
3. TF 包含 map、odom、gimbal_link、muzzle / muzzle_link、camera_link / camera_optical_frame 及目标帧。坐标转换检查 `M_ALIGN_MAT3`、四元数、父子关系及发布时间；pose 消息当前为对应 frame 下的单位 pose，不擅自改成世界 pose。
4. 图像时间用 SystemTime，不能假定已发布 `/clock` 或全部使用仿真时钟。变更 image / CameraInfo / TF 时检查同帧对应、FOV、分辨率、外参及订阅者。
5. 保留命令最新值语义、异步发布通道、spin 线程和 AppExit 清理；线程、锁或队列改动验证空闲、无消息、背压、退出和残留，不把仅 spin 线程 join 当作所有线程已退出。
6. ROS 自动发射另有 10 Hz limiter；科技核心状态按 20 Hz limiter 发布。变更频率、QoS、接口包或本地 r2r patch 时检查生成绑定与实际 overlay，不修改无关消息。

---

## 12. 参数 / 配置修改规范

配置源为根目录 `config.toml` 与 `src/config.rs`。启动时配置加载失败会警告并回退内置默认值；修改事件触发重载，解析失败保留旧配置。不得把现有 fallback 描述成严格缺参报错。

1. 修改键名同步核对 Deserialize、serde default / alias、源码默认值、TOML 值和全部消费者；删除参数时同步处理兼容键与文档。
2. 区分启动时固定的窗口、插件、采集目标、相机/渲染资源与每帧读取的配置；当前热重载显式更新 SubstepCount、Time<Fixed> 和配置资源，不代表所有字段自动重建对象。
3. Talos 图像尺寸来自固定常量 `1440×1080`，不直接受 capture.color 配置驱动；ROS 采集在插件构造时读取尺寸。改变分辨率需同步内参、纹理、缓冲及 IPC 协议。
4. 改变速度、pitch limit、PID、质量、气动力、时间窗口或默认 feature 必须说明影响和验证限制；不把所有常量顺手参数化，不复制配置掩盖加载失败。

---

## 13. Talos IPC / 外部协议修改规范

布局以 `crates/talos-ipc/src/layout.rs` 为准，当前 magic 为 `0x54414C05`、version 为 2。`shm.rs` 使用 `/tmp` 下的 talos_ipc_meta 与 talos_ipc_image_pool 文件，不是 `/dev/shm` 上的 POSIX shm。

1. 修改共享结构前列出 publisher、subscriber、模拟器、视频 mock 与外部 Talos 端；保持 repr(C)、对齐、padding、字段偏移、容量、大小断言和版本检查。
2. 保留三缓冲索引、Atomic 顺序、读写槽所有权及 synchronized image 发布边界；存在 mmap 不等于 GPU 到算法全链路无拷贝。
3. quaternion 在 pose 发布侧使用 `[w,x,y,z]`；命令字段为 yaw_deg / pitch_deg / distance_m / fire_advice。调整角度正负、单位或无解值时同步核对第 7 节的两条接收路径。
4. 机器人/能量机关真值、runtime_state、heartbeat 与图像/pose 的更新节奏不同；不要把共享文件存在、heartbeat 更新或单条数据读到当作完整同步验收。
5. mock binary 需要 `talos` 与 `ffmpeg`，把文件或网络视频缩放到固定 RGB24 尺寸，并接收命令；它发布 mock 位姿，不是三维物理闭环，也不是网络 TCP 云台服务。

---

## 14. 静态检查、构建与测试限制

文档或配置任务只运行与改动相关的非构建检查；Rust 源码变更按授权范围复用已有内嵌测试，不创建无关测试框架。构建限制见第 0 节。

### 14.1 定向搜索与静态解析

从仓库根目录按任务选择只读搜索：

```bash
rg -n 'add_plugins|add_systems|GameplaySystems|TransformSystems' src/main.rs src/scene.rs
rg -n 'Controlled|ActiveSlapper|SubscribeAutoAim|GimbalAimTracker' src/systems src/ros2 src/talos
rg -n 'CollisionEnd|GameLayer|RuneHit|MechanismState' src/components src/robomaster src/systems
rg -n 'CaptureFrameId|SnapshotSync|map_async|frame_seq|timestamp_ns' src/capture src/talos
rg -n 'TOPIC|QOS|GimbalCmd|PointCloud2|M_ALIGN_MAT3' src/ros2
rg -n 'repr\(|SHM_VERSION|offset_of|Atomic|PoseIndex' crates/talos-ipc/src
```

Rust 格式检查可使用 `cargo fmt --all -- --check`，它不验证编译或行为；文档-only 任务无需无关全仓格式检查。TOML 使用可用解析器、ROS package XML 使用 XML 解析器；检查失败返回非零状态，不为静态检查导入/启动模拟器，也不擅自安装工具。只读 Cargo metadata 检查可使用 `cargo metadata --no-deps --offline --format-version 1`，失败需区分 manifest、环境与依赖前置缺口。

### 14.2 环境、使用与部署验收

Linux x86_64 的项目内隔离入口是 `start.sh`，由 `conda-linux-64.lock` 固定 Rust 1.95.0 与原生依赖；`environment.yml` 说明直接依赖。环境位于 `.runtime/conda`，Conda/Cargo 缓存也位于 `.runtime`，开发配置产物位于 `.runtime/target/talos` 或 `local`。脚本清除继承环境后激活专用 prefix，GPU/桌面/系统内核和固定 `/tmp` IPC 仍属于宿主机边界。不得修改 base 或其他项目环境来修复本项目；依赖变更时同步更新清单、完整锁和实际 prefix，具体步骤见 README 第 3 节。

`./start.sh` 与 `--build-only` 会编译，仍须明确构建授权；`--check` 只检查已安装环境，`--run-only` 只执行已有产物，不安装、不构建。默认 Talos，`--local` 关闭默认 features；此环境不覆盖 ROS / FFmpeg，不能用同时启用所有 features 来扩展范围。启动器拒绝覆盖已存在的 Talos IPC 文件，并用项目文件锁防重复会话。

以下为**需构建授权后执行的独立部署命令**，不意味着已经验证通过。先核对工具链、图形驱动、窗口系统和平台依赖；仓库没有容器配方。不要绕过脚本把其他 Conda/ROS 环境的编译器与库混入隔离部署。

```bash
# 默认 Talos 模拟器
cargo build -p daedalus --bin daedalus --release
cargo run -p daedalus --bin daedalus --release

# 不接 ROS / Talos 的本地图形仿真
cargo run -p daedalus --bin daedalus --release --no-default-features

# ROS 模式：先准备并 source ROS 与自定义接口 overlay
colcon --log-base log build --base-paths rm_interfaces --packages-select rm_interfaces --build-base build --install-base install
source install/setup.bash
cargo run -p daedalus --bin daedalus --release --no-default-features --features ros2

# 视频 mock：--input 为用户指定视频文件或流地址
cargo run -p daedalus --bin talos_gimbal_mock_server --release --features ffmpeg -- --input <video_path_or_url>
```

- 单机部署以所选 feature 的可执行文件、运行时动态库、`assets/` 和 `config.toml` 为交付单元，从包含配置与资产的项目目录运行；Bevy dynamic_linking 及 ROS / FFmpeg 原生依赖意味着不能承诺只复制一个 binary 就可运行。
- Linux ROS 环境需已有 ROS 2、colcon / ament、消息依赖及 bindgen 所需环境；编辑器配置指向 Humble，但不是整个 Rust 项目的唯一平台基线。先 source 实际安装的 ROS，再构建/source 本仓接口包；不套用其他机器人工作区的 Conda 或 overlay。
- FFmpeg 功能需匹配 ffmpeg-next 的原生库及开发环境；macOS MetalFX 的系统/GPU约束检查实现，不以 Linux 检查替代 macOS 验证。依赖安装、外部环境修改和远端部署另按用户授权执行。
- 授权后可定向使用 `cargo test -p exact`、`cargo test -p daedalus --no-default-features` 或默认 Talos 路径测试；选测试名过滤相关内嵌用例。ROS 与 FFmpeg 需独立 feature 验证，默认路径通过不覆盖这些可选路径。

记录实际命令、feature、平台、退出码、产物目录、关键失败日志及与本次修改的关系；编译成功不等于运行、视觉效果、图像/pose 同步或外部联调通过。

### 14.3 图形运行 / 通信 / 退出回归条件

1. 涉及场景与运动时检查环境就绪、机器人不穿地、控制切换、碰撞和状态边界；涉及采集时检查真实收到的帧尺寸、编码、内参、时间戳及序号，不只看截图。
2. ROS 检查实际节点、消息类型、topic / TF、采集与命令接收；Talos 检查协议版本、帧/pose 对应、无解命令、生产者/消费者退出及属于本次的映射文件清理。
3. 线程或退出机制变更覆盖有消息和无消息状态，记录退出对象、退出耗时、退出码及残留 PID；panic、死锁、超时或强杀不能记作优雅退出通过，不临时放宽标准。
4. 跨平台渲染、长时间稳定性、外部算法效果及实机结果需对应环境的独立证据；未运行的场景明确列出，不虚构验收。

---

## 15. 最终输出格式

完成后向用户输出结果摘要，不输出 writingplans 式计划：

```md
## 修改摘要
## 修改文件
## 行为保持说明
## 有意改变的行为
## 检查结果
## 改造记录
## 未解决问题
## Final Result
PASS / NEEDS_FIX
```

`PASS` 仅表示当前任务要求且实际执行的检查已满足；未运行的构建、图形仿真、通信联调、平台或实机检查必须单独列出。若任务要求的验证仍缺失，不能据此宣称功能修复已验收。

未执行构建时必须明确写：

```text
未执行构建：AGENTS.md 禁止在未获用户明确许可前运行构建命令。
```

---

## 16. 禁止事项汇总

除非用户明确要求，否则禁止：

1. 大规模重构。
2. 删除历史策略、注释分支或兼容逻辑。
3. 改动多个无关模块。
4. 修改已有证据支持的仿真或算法联调策略。
5. 添加复杂新框架。
6. 添加逐帧日志或无用统计。
7. 改变模型节点名、topic、frame、QoS 或 IPC 布局。
8. 修改参数或 feature 默认值。
9. 修改插件组合、schedule 或系统执行顺序。
10. 把未验证推断写成确定事实。
11. 未获许可执行构建。
12. 以“清理”为名删除仍可能复用的仿真逻辑。
13. 将单模块任务扩展为全仓重构或治理。
14. 在未记录的情况下修改控制权或行为优先级。
15. 使用 writingplans 或类似计划说明工具。
16. 执行任何暂存、提交、推送、合并、标签或发布等版本控制写操作。

第 0、0.1、0.2、0.3 节的构建、版本控制、计划工具及外部系统限制保持最高优先级，不得用“清理”“测试”或“部署”为名绕过。

---

## 17. 可选的内部阶段化工作方式

复杂任务可以在内部按阶段拆分，但不得使用 writingplans 输出独立计划说明：

```text
Step 1：职责边界和实际入口
Step 2：实体层级、数据链与采集快照
Step 3：接口、features 与配置接入
Step 4：仿真行为与控制权
Step 5：异常、线程与退出处理
Step 6：审计、记录和临时文件清理
```

阶段拆分仅用于控制风险。事实与目标确认后直接修改，完成后补充事后记录，不以计划代替实现。

---

## 18. 当前项目已知偏好

1. 最小完整改动、少引入变量和抽象、不整体重构、不增加无用日志。
2. 源码、manifest、配置和真实资源是项目事实依据；README 与旧报告只提供线索。
3. 保持仿真调度、模型层级、控制权、坐标转换、碰撞与采集同步边界；不按理论改写目标规则。
4. Explorer → Modifier → Auditor 仅在用户明确要求时启用，构建遵循已有授权，工作完成后不主动提交。
5. 沿用双标题、编号章节与事后记录格式。新增、删除或改变功能、入口、技术栈、features、接口、配置键、使用/部署方式时，同步核对并更新本文件受影响的背景、模块规范及参考资料，移除失效项目事实，不机械追加重复规则；若当前授权只允许改特定文件，则指出规则更新缺口，不越界修改。

### 18.1 当前工程参考资料

- 项目概述与操作线索：`README.md`，首次了解项目或核对使用说明时阅读；必须与真实入口、控制和通信源码交叉核验。
- 依赖、features 和运行目标：`Cargo.toml`、`Cargo.lock`，修改依赖或构建/部署时必读。
- 隔离启动与环境维护：`start.sh`、`environment.yml`、`conda-linux-64.lock`、README 第 3 节，修改一键启动、原生依赖、缓存或产物目录时必读；不得手工编辑 `.runtime` 中的包与构建产物。
- 配置加载与生效范围：`config.toml`、`src/config.rs`，调参或改变热重载时必读。
- ROS 接口与资源：`src/ros2/topic.rs`、`rm_interfaces/CMakeLists.txt`、`rm_interfaces/package.xml`，修改 ROS 类型、绑定或环境时必读。
- IPC 契约：`crates/talos-ipc/src/layout.rs`、`crates/talos-ipc/src/shm.rs`，修改外部 Talos 接口或多进程运行时必读。
- 构建包装器与第三方生成器：`cargo-wrapper.sh`、`third_party/r2r_msg_gen/build.rs`，仅在相关构建/绑定问题时阅读，不把本地缺失脚本当作可用入口。
- 历史任务依据：`doc/`，修改已有验证行为时查阅对应记录；记录中的旧状态不代替当前源码。

必须独立验证且不能由静态检查推断的内容包括：目标机器的图形/MetalFX 可用性、场景视觉正确性、长时间稳定性、实际外部算法闭环、ROS / Talos 同步与兼容、真实传感器或底盘/云台/射击效果。人工确认项不得冒称已由 Agent 完成。
  
