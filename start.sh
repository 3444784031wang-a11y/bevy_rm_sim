#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ENV_PREFIX="$PROJECT_ROOT/.runtime/conda"
LOCK_FILE="$PROJECT_ROOT/conda-linux-64.lock"
MODE=talos
ACTION=start

fail() {
    printf '启动失败：%s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
用法：./start.sh [--local] [--setup-only | --build-only | --run-only | --check]

默认：准备项目内 Conda 环境，增量编译默认 Talos 模式，然后打开模拟器。
--local       仅本地仿真，不启用 ROS / Talos。
--setup-only  只安装锁定的环境依赖，不编译模拟器。
--build-only  准备环境并编译，不打开窗口。
--run-only    运行已有产物，不安装、不编译。
--check       检查已有环境和项目文件，不安装、不编译。
--help        显示此帮助。

首次安装和编译需要联网。仅支持 Linux x86_64 图形桌面。
可用 CONDA_EXE=/绝对路径/bin/conda 指定 Conda；不修改其他 Conda 环境。
构建使用开发配置、关闭调试符号、单任务编译，以控制磁盘和内存占用。
USAGE
}

for argument in "$@"; do
    case "$argument" in
        --local) MODE=local ;;
        --setup-only|--build-only|--run-only|--check)
            [[ "$ACTION" == start ]] || fail '操作选项不能同时使用'
            ACTION="${argument#--}"
            ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; fail "未知选项：$argument" ;;
    esac
done

[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || fail '此环境锁只适用于 Linux x86_64'
HOST_GLIBC="$(getconf GNU_LIBC_VERSION 2>/dev/null)" || fail '此环境需要 glibc >= 2.34'
HOST_GLIBC="${HOST_GLIBC#glibc }"
[[ "$(printf '%s\n' 2.34 "$HOST_GLIBC" | sort -V | head -n 1)" == 2.34 ]] || fail '此环境需要 glibc >= 2.34（推荐 Ubuntu 22.04 或更新版本）'

if [[ "${DAEDALUS_CLEAN_ENV:-}" != "$PROJECT_ROOT" ]]; then
    CONDA_COMMAND="${CONDA_EXE:-}"
    if [[ -z "$CONDA_COMMAND" ]]; then
        for candidate in "$HOME/miniforge3/bin/conda" "$HOME/miniconda3/bin/conda" "$HOME/anaconda3/bin/conda"; do
            if [[ -x "$candidate" ]]; then
                CONDA_COMMAND="$candidate"
                break
            fi
        done
    fi
    if [[ -z "$CONDA_COMMAND" ]]; then
        CONDA_COMMAND="$(command -v conda || true)"
    fi
    [[ "$CONDA_COMMAND" == /* && -x "$CONDA_COMMAND" ]] || fail '未找到 Conda；安装 Miniforge 或设置 CONDA_EXE 为绝对路径'
    CLEAN_ENV=("HOME=$HOME" "USER=${USER:-$(id -un)}" "PATH=/usr/bin:/bin" "LANG=C.UTF-8"
        "CONDA_EXE=$CONDA_COMMAND" "DAEDALUS_CLEAN_ENV=$PROJECT_ROOT")
    for variable in DISPLAY WAYLAND_DISPLAY XAUTHORITY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS PULSE_SERVER TERM HTTPS_PROXY HTTP_PROXY ALL_PROXY NO_PROXY https_proxy http_proxy all_proxy no_proxy RUST_LOG; do
        if [[ -v "$variable" ]]; then
            CLEAN_ENV+=("$variable=${!variable}")
        fi
    done
    exec /usr/bin/env -i "${CLEAN_ENV[@]}" /bin/bash "$PROJECT_ROOT/start.sh" "$@"
fi

cd "$PROJECT_ROOT"
for required in Cargo.toml Cargo.lock config.toml assets "$LOCK_FILE"; do
    [[ -e "$required" ]] || fail "缺少项目文件：$required"
done

export CONDA_PKGS_DIRS="$PROJECT_ROOT/.runtime/conda-pkgs"
export CONDA_ENVS_PATH="$PROJECT_ROOT/.runtime"
export CONDA_CHANNEL_PRIORITY=strict
export CARGO_HOME="$PROJECT_ROOT/.runtime/cargo"
export CARGO_TARGET_DIR="$PROJECT_ROOT/.runtime/target/$MODE"
export CARGO_BUILD_JOBS=1
export CARGO_PROFILE_DEV_DEBUG=0
export CARGO_PROFILE_DEV_INCREMENTAL=false
export BEVY_ASSET_ROOT="$PROJECT_ROOT"

if [[ "$ACTION" != check ]]; then
    mkdir -p "$PROJECT_ROOT/.runtime"
    exec 9> "$PROJECT_ROOT/.runtime/session.lock"
    flock -n 9 || fail '本项目已有安装、构建或运行会话；请先退出该会话'
fi

SPEC_HASH="$(sha256sum "$LOCK_FILE" | cut -d ' ' -f 1)"
if [[ ! -f "$ENV_PREFIX/conda-meta/history" ]]; then
    [[ "$ACTION" != run-only && "$ACTION" != check ]] || fail '环境尚未安装，请先执行 ./start.sh --setup-only'
    [[ ! -e "$ENV_PREFIX" ]] || fail "发现未完成的环境目录 $ENV_PREFIX；请检查并移走后重试，不会覆盖它"
    printf '安装隔离环境：%s\n' "$ENV_PREFIX"
    "$CONDA_EXE" create --yes --no-default-packages --prefix "$ENV_PREFIX" --file "$LOCK_FILE"
    printf '%s\n' "$SPEC_HASH" > "$PROJECT_ROOT/.runtime/conda-spec.sha256"
fi
[[ -f "$PROJECT_ROOT/.runtime/conda-spec.sha256" ]] || fail '环境缺少依赖锁校验标记，不能确认是本脚本安装的环境'
[[ "$(cat "$PROJECT_ROOT/.runtime/conda-spec.sha256")" == "$SPEC_HASH" ]] || fail '环境锁已改变；请备份并移走 .runtime/conda 和旧校验标记，再重新安装'
EXPECTED_PACKAGES="$(sed '/^@EXPLICIT$/d; /^#/d; /^$/d' "$LOCK_FILE" | sort)"
INSTALLED_PACKAGES="$("$CONDA_EXE" list --prefix "$ENV_PREFIX" --explicit --md5 | sed '/^@EXPLICIT$/d; /^#/d; /^$/d' | sort)"
[[ "$INSTALLED_PACKAGES" == "$EXPECTED_PACKAGES" ]] || fail '已安装环境与依赖锁不一致，请恢复环境，不会使用已被更改的依赖'

CONDA_BASE="$("$CONDA_EXE" info --base)"
source "$CONDA_BASE/etc/profile.d/conda.sh"
conda activate "$ENV_PREFIX"
[[ "$(command -v cargo)" == "$ENV_PREFIX/bin/cargo" ]] || fail 'cargo 未来自项目隔离环境'
[[ "$(command -v rustc)" == "$ENV_PREFIX/bin/rustc" ]] || fail 'rustc 未来自项目隔离环境'
[[ "$(rustc --version | cut -d ' ' -f 2)" == 1.95.0 ]] || fail 'Rust 版本与锁定版本 1.95.0 不一致'
export PKG_CONFIG_LIBDIR="$ENV_PREFIX/lib/pkgconfig:$ENV_PREFIX/share/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="${CC:?Conda 编译器未激活}"
export RUSTFLAGS="-C link-arg=-Wl,-rpath,$ENV_PREFIX/lib"
RUST_LIBRARY_DIR="$(rustc --print target-libdir)"
export LD_LIBRARY_PATH="$CARGO_TARGET_DIR/debug/deps:$ENV_PREFIX/lib:$RUST_LIBRARY_DIR"

printf '环境：%s\n模式：%s\n产物：%s\n' "$CONDA_PREFIX" "$MODE" "$CARGO_TARGET_DIR"
rustc --version
cargo --version
pkg-config --modversion alsa libudev x11
if [[ "$ACTION" == setup-only || "$ACTION" == check ]]; then
    printf '环境检查通过；尚未运行模拟器。\n'
    exit 0
fi

if [[ "$ACTION" == start || "$ACTION" == build-only ]]; then
    BUILD_ARGS=(build --locked --package daedalus --bin daedalus)
    if [[ "$MODE" == local ]]; then
        BUILD_ARGS+=(--no-default-features)
    fi
    cargo "${BUILD_ARGS[@]}" 2>&1 | tee "$PROJECT_ROOT/.runtime/build-$MODE.log"
fi
[[ "$ACTION" != build-only ]] || exit 0

[[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || fail '未检测到图形桌面；请在桌面终端运行，--build-only 可用于仅构建'
BINARY="$CARGO_TARGET_DIR/debug/daedalus"
[[ -x "$BINARY" ]] || fail '不存在可执行产物；请先执行 ./start.sh --build-only（本地模式加 --local）'
if [[ "$MODE" == talos ]]; then
    for ipc_file in /tmp/talos_ipc_meta /tmp/talos_ipc_image_pool; do
        [[ ! -e "$ipc_file" && ! -L "$ipc_file" ]] || fail "IPC 文件已存在：$ipc_file；确认原会话退出及文件所有权后再处理，脚本不会截断它"
    done
fi
printf '启动模拟器；关闭窗口即可退出。\n'
exec "$BINARY"
