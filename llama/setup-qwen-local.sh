#!/usr/bin/env bash
# =============================================================================
# setup-qwen-local.sh
#
# Automated setup + launcher for Qwen3.8-27B (GGUF) on Fedora + AMD Radeon
# (tested target: RX 7900 XTX / gfx1100) using llama.cpp.
#
# Usage:
#   ./setup-qwen-local.sh [command]
#
# Commands:
#   all        (default) doctor -> deps -> build -> download -> run (foreground)
#   doctor     only run system / GPU preflight checks
#   deps       install missing dnf packages
#   build      clone/update + build llama.cpp
#   download   download the GGUF model
#   run        start llama-server in the foreground
#   service    install + start a systemd --user service
#   status     show service / API health
#   help       this text
#
# Configuration (environment variables, all optional):
#   BACKEND        auto|vulkan|rocm      (default: auto -> vulkan)
#   INSTALL_DIR    where llama.cpp / venv live      (default: ~/.local/share/qwen-local)
#   MODEL_DIR      where GGUF files are stored      (default: ~/models/qwen3.8-27b)
#   MODEL_REPO     HF repo with GGUF files          (default: auto-discover trusted repo)
#   QUANT          quant pattern                    (default: Q4_K_M)
#   CTX            context size in tokens           (default: chosen from VRAM)
#   HOST / PORT    bind address / port              (default: 127.0.0.1 / 8080)
#   LLAMA_REF      git branch/tag/commit            (default: master; pin a commit for reproducibility)
#   LLAMA_API_KEY  strong key (at least 32 characters) for API authentication
#   EXTRA_ARGS     whitespace-separated extra llama-server arguments
#   BUILD_JOBS     parallel build jobs (default: at most 4)
#   FORCE_REBUILD  1 = rebuild even if up to date
#   ASSUME_YES     1 = accept confirmation prompts (including non-interactive)
#   HF_TOKEN       Hugging Face token (picked up automatically if needed)
#   Security: use a strong API key for non-loopback HOST values. The key is
#   kept out of systemd unit files, but llama-server needs it as a CLI argument
#   and it may be visible to other local users with process-inspection access.
# =============================================================================

set -Eeuo pipefail

# ----------------------------- configuration ---------------------------------
BACKEND="${BACKEND:-auto}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/share/qwen-local}"
MODEL_DIR="${MODEL_DIR:-$HOME/models/qwen3.8-27b}"
MODEL_REPO="${MODEL_REPO:-}"
QUANT="${QUANT:-Q4_K_M}"
CTX="${CTX:-}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
LLAMA_REF="${LLAMA_REF:-master}"
LLAMA_API_KEY="${LLAMA_API_KEY:-}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
BUILD_JOBS="${BUILD_JOBS:-}"

LLAMA_REPO_URL="https://github.com/ggml-org/llama.cpp"
SRC_DIR="$INSTALL_DIR/llama.cpp"
VENV_DIR="$INSTALL_DIR/venv"
BUILD_DIR=""            # set after backend resolution
SERVER_BIN=""
SERVICE_NAME="llama-qwen"
MIN_DISK_GB=40          # model (~16GB) + build + headroom
MIN_BUILD_DISK_GB=15    # source checkout and compiled artifacts
MIN_VRAM_MIB=20000      # 27B Q4 needs ~16GB + KV cache

# ------------------------------- logging -------------------------------------
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YLW=$'\033[33m'; C_BLU=$'\033[34m'; C_RST=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YLW=""; C_BLU=""; C_RST=""
fi
info() { printf '%s[INFO]%s %s\n' "$C_BLU" "$C_RST" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YLW" "$C_RST" "$*" >&2; }
die()  { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RST" "$*" >&2; exit 1; }

trap 'die "Unexpected error at line $LINENO (command details suppressed)."' ERR
trap 'printf "\n"; warn "Interrupted."; exit 130' INT TERM

# ------------------------------- helpers -------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

need_cmd() { have "$1" || die "Required command not found: $1"; }

format_host() {
  if [[ "$1" == *:* ]]; then
    printf '[%s]' "$1"
  else
    printf '%s' "$1"
  fi
}

confirm() {
  [[ "$ASSUME_YES" == "1" ]] && return 0
  if [[ ! -t 0 ]]; then
    warn "Cannot confirm in non-interactive mode; set ASSUME_YES=1 to explicitly proceed."
    return 1
  fi
  local reply
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

validate_config() {
  local port_num ctx_num cpu_count arg

  case "$BACKEND" in
    auto|vulkan|rocm) ;;
    *) die "Invalid BACKEND='$BACKEND' (use auto|vulkan|rocm)." ;;
  esac
  if [[ "$BACKEND" == "rocm" ]]; then
    local targets="${AMDGPU_TARGETS:-gfx1100}"
    [[ "$targets" =~ ^gfx[0-9a-f]+(\;gfx[0-9a-f]+)*$ ]] \
      || die "AMDGPU_TARGETS must be a semicolon-separated list of gfx targets (for example gfx1100)."
  fi

  [[ "$PORT" =~ ^[0-9]{1,5}$ ]] || die "PORT must be an integer from 1 to 65535."
  port_num=$((10#$PORT))
  ((port_num >= 1 && port_num <= 65535)) || die "PORT must be an integer from 1 to 65535."
  PORT="$port_num"

  if [[ -n "$CTX" ]]; then
    [[ "$CTX" =~ ^[0-9]{1,9}$ ]] || die "CTX must be a positive integer (maximum 9 digits)."
    ctx_num=$((10#$CTX))
    ((ctx_num > 0)) || die "CTX must be greater than zero."
    CTX="$ctx_num"
  fi

  [[ "$HOST" =~ ^[A-Za-z0-9._:-]+$ ]] || die "HOST contains unsupported characters."
  [[ "$QUANT" =~ ^[A-Za-z0-9_-]+$ ]] || die "QUANT may contain only letters, digits, '_' and '-'."
  [[ "$LLAMA_REF" =~ ^[A-Za-z0-9._/-]+$ && "$LLAMA_REF" != -* ]] \
    || die "LLAMA_REF contains unsupported characters."
  [[ "$MODEL_REPO" == "" || "$MODEL_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
    || die "MODEL_REPO must have the form organization/repository."

  if [[ -n "$LLAMA_API_KEY" ]]; then
    [[ "$LLAMA_API_KEY" =~ ^[A-Za-z0-9._~-]{32,256}$ ]] \
      || die "LLAMA_API_KEY must be 32-256 characters using only letters, digits, '.', '_', '~' or '-'."
  fi
  if [[ "$HOST" != "127.0.0.1" && "$HOST" != "localhost" && "$HOST" != "::1" \
        && -z "$LLAMA_API_KEY" ]]; then
    die "Refusing non-loopback HOST='$HOST' without LLAMA_API_KEY."
  fi

  if [[ -n "$BUILD_JOBS" ]]; then
    [[ "$BUILD_JOBS" =~ ^[0-9]{1,3}$ ]] || die "BUILD_JOBS must be an integer from 1 to 256."
    ((10#$BUILD_JOBS >= 1 && 10#$BUILD_JOBS <= 256)) \
      || die "BUILD_JOBS must be an integer from 1 to 256."
    BUILD_JOBS=$((10#$BUILD_JOBS))
  else
    cpu_count="$(nproc)"
    ((cpu_count > 0)) || die "Could not determine the number of available CPUs."
    if ((cpu_count > 4)); then BUILD_JOBS=4; else BUILD_JOBS="$cpu_count"; fi
  fi

  [[ "$EXTRA_ARGS" != *$'\n'* && "$EXTRA_ARGS" != *$'\r'* ]] \
    || die "EXTRA_ARGS must be a single line."
  [[ "$ASSUME_YES" == "0" || "$ASSUME_YES" == "1" ]] \
    || die "ASSUME_YES must be 0 or 1."
  [[ "$FORCE_REBUILD" == "0" || "$FORCE_REBUILD" == "1" ]] \
    || die "FORCE_REBUILD must be 0 or 1."
  local -a extra_args=()
  if [[ -n "$EXTRA_ARGS" ]]; then
    read -r -a extra_args <<<"$EXTRA_ARGS"
  fi
  for arg in "${extra_args[@]}"; do
    case "$arg" in
      -m|--model|--model=*|--host|--host=*|--port|--port=*|\
      --api-key|--api-key=*|--api-key-file|--api-key-file=*)
        die "EXTRA_ARGS may not override model, bind, port, or API-key settings ($arg)."
        ;;
    esac
  done
}

ensure_sudo() {
  [[ $EUID -eq 0 ]] && return 0
  need_cmd sudo
  sudo -v || die "sudo authentication failed"
}

run_privileged() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

pkg_installed() { rpm -q --whatprovides "$1" >/dev/null 2>&1; }

install_pkgs() {   # required packages: failure is fatal
  local missing=() p
  for p in "$@"; do
    pkg_installed "$p" || missing+=("$p")
  done
  if ((${#missing[@]} == 0)); then
    ok "Packages already installed: $*"
    return 0
  fi
  info "Installing: ${missing[*]}"
  ensure_sudo
  run_privileged dnf install -y --setopt=install_weak_deps=False "${missing[@]}" \
    || die "dnf failed to install: ${missing[*]}"
}

try_install_pkgs() {   # optional packages: failure is a warning
  local p
  for p in "$@"; do
    if pkg_installed "$p"; then continue; fi
    ensure_sudo
    if run_privileged dnf install -y --setopt=install_weak_deps=False "$p" >/dev/null 2>&1; then
      ok "Installed optional package: $p"
    else
      warn "Optional package not available: $p (continuing)"
    fi
  done
}

disk_free_gb() {   # $1 = path (may not exist yet; walks up)
  local p="$1"
  while [[ ! -d "$p" && "$p" != "/" ]]; do p="$(dirname "$p")"; done
  df -Pk "$p" | awk 'NR==2 {printf "%d", $4/1024/1024}'
}

# ------------------------------ preflight ------------------------------------
VRAM_MIB=0
detect_vram() {
  local f v max=0
  for f in /sys/class/drm/card*/device/mem_info_vram_total; do
    [[ -r "$f" ]] || continue
    v=$(<"$f")
    v=$((v / 1024 / 1024))
    if ((v > max)); then max=$v; fi
  done
  VRAM_MIB=$max
}

preflight() {
  info "Running preflight checks..."

  [[ "$(uname -s)" == "Linux" ]] || die "Linux only."
  [[ "$(uname -m)" == "x86_64" ]] || die "x86_64 only (found $(uname -m))."

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "fedora" && "${ID_LIKE:-}" != *fedora* ]]; then
      warn "Not Fedora (ID=${ID:-?}); package names may differ."
      confirm "Continue anyway?" || die "Aborted."
    else
      ok "OS: ${PRETTY_NAME:-Fedora}"
    fi
  fi
  need_cmd dnf
  need_cmd rpm

  # Network
  if ! have curl; then
    warn "curl missing (it will be installed in the deps step)."
  elif ! curl -fsS --max-time 8 -o /dev/null https://huggingface.co 2>/dev/null; then
    warn "Cannot reach huggingface.co right now - download step may fail."
  else
    ok "Network: huggingface.co reachable"
  fi

  # Resources
  local free_gb build_free_gb ram_gb
  free_gb="$(disk_free_gb "$MODEL_DIR")"
  if ((free_gb < MIN_DISK_GB)); then
    die "Only ${free_gb} GB free near $MODEL_DIR; need >= ${MIN_DISK_GB} GB."
  fi
  ok "Disk: ${free_gb} GB free"
  build_free_gb="$(disk_free_gb "$INSTALL_DIR")"
  if ((build_free_gb < MIN_BUILD_DISK_GB)); then
    die "Only ${build_free_gb} GB free near $INSTALL_DIR; need >= ${MIN_BUILD_DISK_GB} GB for the build."
  fi
  ok "Build disk: ${build_free_gb} GB free"

  ram_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  if ((ram_gb >= 16)); then
    ok "RAM: ${ram_gb} GB"
  else
    warn "RAM: ${ram_gb} GB (build may be slow / swap)"
  fi

  # GPU
  if have lspci; then
    if lspci -nn | grep -Ei 'vga|display|3d' | grep -Eiq 'amd|ati|advanced micro'; then
      ok "AMD GPU: $(lspci | grep -Ei 'vga|display|3d' | grep -Ei 'amd|ati' | head -1 | cut -d: -f3- | sed 's/^ //')"
    else
      warn "No AMD GPU detected via lspci."
      confirm "Continue anyway?" || die "Aborted."
    fi
  else
    warn "lspci not installed yet (pciutils) - skipping GPU model check."
  fi

  detect_vram
  if ((VRAM_MIB > 0)); then
    if ((VRAM_MIB < MIN_VRAM_MIB)); then
      warn "VRAM: ${VRAM_MIB} MiB - below ${MIN_VRAM_MIB} MiB; model will be tight or need smaller quant/context."
    else
      ok "VRAM: ${VRAM_MIB} MiB"
    fi
  else
    warn "Could not read VRAM from sysfs (driver not loaded?)."
  fi

  # Check effective device access, not group names (container group names can
  # differ from the numeric supplemental GIDs passed by the container runtime).
  local dev found_render=0 accessible_render=0
  for dev in /dev/dri/renderD*; do
    [[ -e "$dev" ]] || continue
    found_render=1
    if [[ -r "$dev" && -w "$dev" ]]; then
      accessible_render=1
      break
    fi
  done
  if ((accessible_render)); then
    ok "GPU render device is readable and writable."
  elif ((found_render)); then
    warn "Render device exists but is not readable and writable by this process."
    if [[ -e /.dockerenv || -e /run/.containerenv || -n "${container:-}" ]]; then
      warn "Container: pass the render device and its numeric group ID to the runtime."
    else
      local current_user
      current_user="$(id -un 2>/dev/null || printf 'UID %s' "$(id -u)")"
      warn "Host: add '$current_user' to the device's owning group, then log out and back in."
    fi
  else
    warn "No /dev/dri/renderD* device found; GPU acceleration may not work."
  fi
}

# ------------------------------ backend --------------------------------------
resolve_backend() {
  case "$BACKEND" in
    auto)   BACKEND="vulkan" ;;
    vulkan|rocm) ;;
    *) die "Invalid BACKEND='$BACKEND' (use auto|vulkan|rocm)." ;;
  esac
  BUILD_DIR="$INSTALL_DIR/build-$BACKEND"
  SERVER_BIN="$BUILD_DIR/bin/llama-server"
  info "Backend: $BACKEND"
}

# -------------------------------- deps ---------------------------------------
install_deps() {
  resolve_backend
  info "Installing dependencies..."
  install_pkgs git cmake gcc-c++ make curl libcurl-devel python3 python3-pip pciutils

  case "$BACKEND" in
    vulkan)
      install_pkgs vulkan-headers vulkan-loader-devel glslc mesa-vulkan-drivers vulkan-tools
      try_install_pkgs spirv-headers-devel ccache
      ;;
    rocm)
      install_pkgs rocm-hip-devel hipblas-devel rocblas-devel
      try_install_pkgs rocm-smi rocm-comgr-devel rocm-runtime-devel ccache
      have hipconfig || die "hipconfig not found after installing ROCm packages (check 'dnf search rocm')."
      ;;
  esac

  verify_gpu_runtime
}

verify_gpu_runtime() {
  case "$BACKEND" in
    vulkan)
      have vulkaninfo || die "vulkaninfo missing."
      local devs
      devs="$(vulkaninfo --summary 2>/dev/null | grep -E 'deviceName' || true)"
      if [[ -z "$devs" ]]; then
        die "Vulkan reports no devices. Check drivers and render/video group membership."
      fi
      if grep -qiv 'llvmpipe' <<<"$devs"; then
        ok "Vulkan devices:"$'\n'"$devs"
      else
        die "Only software renderer (llvmpipe) found - GPU is not being used. Check Mesa/driver and group access."
      fi
      ;;
    rocm)
      if have rocminfo; then
        local gfx
        gfx="$(rocminfo 2>/dev/null | grep -o 'gfx[0-9a-f]*' | sort -u || true)"
        if [[ -n "$gfx" ]]; then
          ok "ROCm sees: $(tr '\n' ' ' <<<"$gfx")"
        else
          warn "rocminfo found no gfx agents."
        fi
      else
        warn "rocminfo not installed; cannot verify ROCm runtime."
      fi
      if have rocminfo && rocminfo 2>/dev/null | grep -q 'gfx1100'; then
        :
      else
        warn "gfx1100 (7900 XTX) not detected; if your GPU differs, set HSA_OVERRIDE_GFX_VERSION or build target accordingly."
      fi
      ;;
  esac
}

# -------------------------------- build --------------------------------------
build_llama() {
  resolve_backend
  mkdir -p "$INSTALL_DIR"
  local build_free_gb
  build_free_gb="$(disk_free_gb "$INSTALL_DIR")"
  ((build_free_gb >= MIN_BUILD_DISK_GB)) \
    || die "Only ${build_free_gb} GB free near $INSTALL_DIR; need >= ${MIN_BUILD_DISK_GB} GB for the build."

  if [[ -d "$SRC_DIR/.git" ]]; then
    local remote_url
    remote_url="$(git -C "$SRC_DIR" remote get-url origin)" \
      || die "Existing llama.cpp checkout has no usable 'origin' remote."
    case "$remote_url" in
      https://github.com/ggml-org/llama.cpp|https://github.com/ggml-org/llama.cpp.git) ;;
      *) die "Refusing an unexpected llama.cpp origin URL." ;;
    esac
    [[ -z "$(git -C "$SRC_DIR" status --porcelain --untracked-files=normal -- . ':(exclude)build-*')" ]] \
      || die "llama.cpp checkout has local changes; commit or remove them before updating/building."
    info "Updating llama.cpp ($LLAMA_REF)..."
    git -C "$SRC_DIR" fetch --tags --prune origin >/dev/null 2>&1 \
      || warn "git fetch failed (offline?) - building from existing checkout."
  else
    [[ ! -e "$SRC_DIR" ]] || die "$SRC_DIR exists but is not a llama.cpp Git checkout."
    info "Cloning llama.cpp..."
    git clone "$LLAMA_REPO_URL" "$SRC_DIR"
  fi

  git -C "$SRC_DIR" check-ref-format --allow-onelevel "$LLAMA_REF" \
    || die "LLAMA_REF is not a valid Git ref."
  if ! git -C "$SRC_DIR" rev-parse --verify --quiet "$LLAMA_REF^{commit}" >/dev/null \
      && ! git -C "$SRC_DIR" show-ref --verify --quiet "refs/remotes/origin/$LLAMA_REF"; then
    die "LLAMA_REF does not resolve to a commit in the checkout or its origin."
  fi
  git -C "$SRC_DIR" checkout -q "$LLAMA_REF" || die "Cannot checkout '$LLAMA_REF'."
  if git -C "$SRC_DIR" show-ref --verify --quiet "refs/remotes/origin/$LLAMA_REF"; then
    git -C "$SRC_DIR" merge --ff-only -q "origin/$LLAMA_REF" \
      || warn "Could not fast-forward '$LLAMA_REF'."
  fi

  local commit stamp_file stamp stamp_tmp build_target=""
  commit="$(git -C "$SRC_DIR" rev-parse HEAD)"
  stamp_file="$BUILD_DIR/.build-stamp"
  if [[ "$BACKEND" == "rocm" ]]; then
    build_target="${AMDGPU_TARGETS:-gfx1100}"
  fi
  stamp="$commit $BACKEND $build_target"

  if [[ "$FORCE_REBUILD" != "1" && -x "$SERVER_BIN" && -f "$stamp_file" \
        && "$(<"$stamp_file")" == "$stamp" ]]; then
    ok "llama-server already up to date (${commit:0:9}, $BACKEND)."
    return 0
  fi

  local cmake_args=(-S "$SRC_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
                    -DLLAMA_CURL=ON -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF)
  if have ccache; then
    cmake_args+=(-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache)
  fi

  info "Configuring (${commit:0:9}, $BACKEND)..."
  case "$BACKEND" in
    vulkan)
      cmake "${cmake_args[@]}" -DGGML_VULKAN=ON
      ;;
    rocm)
      have hipconfig || die "hipconfig not found."
      HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
        cmake "${cmake_args[@]}" -DGGML_HIP=ON -DAMDGPU_TARGETS="${AMDGPU_TARGETS:-gfx1100}"
      ;;
  esac

  info "Building with $BUILD_JOBS jobs (this takes a few minutes)..."
  cmake --build "$BUILD_DIR" --config Release -j"$BUILD_JOBS" --target llama-server llama-cli
  [[ -x "$SERVER_BIN" ]] || die "Build finished but $SERVER_BIN is missing."
  stamp_tmp="$(mktemp "$BUILD_DIR/.build-stamp.XXXXXX")"
  printf '%s' "$stamp" >"$stamp_tmp"
  mv -f -- "$stamp_tmp" "$stamp_file"
  ok "Built: $SERVER_BIN"
}

# ------------------------------- download ------------------------------------
ensure_venv() {
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    info "Creating Python venv..."
    python3 -m venv "$VENV_DIR" || die "venv creation failed (install python3-virtualenv?)."
  fi
  if ! "$VENV_DIR/bin/python" -c 'import huggingface_hub' >/dev/null 2>&1; then
    info "Installing huggingface_hub..."
    "$VENV_DIR/bin/pip" install -q huggingface_hub \
      || die "pip install huggingface_hub failed."
  fi
}

discover_repo() {
  python3 - <<'PY'
import json, sys, urllib.parse, urllib.request

TRUSTED = ["unsloth", "bartowski", "lmstudio-community", "Qwen", "ggml-org", "mradermacher"]
BAD = ("abliterated", "uncensored", "distill", "heretic", "reap", "mlx", "awq", "gptq")

q = urllib.parse.urlencode({
    "search": "Qwen3.8-27B", "filter": "gguf",
    "sort": "downloads", "direction": "-1", "limit": "50",
})
try:
    with urllib.request.urlopen(f"https://huggingface.co/api/models?{q}", timeout=20) as r:
        models = json.load(r)
except Exception as e:
    print(f"query failed: {e}", file=sys.stderr)
    sys.exit(2)

cands = []
for m in models:
    mid = m.get("id", "")
    low = mid.lower()
    if "qwen3.8-27b" not in low or "gguf" not in low:
        continue
    if any(b in low for b in BAD):
        continue
    org = mid.split("/")[0]
    if org in TRUSTED:
        cands.append((TRUSTED.index(org), -int(m.get("downloads", 0)), mid))
if not cands:
    sys.exit(3)
cands.sort()
print(cands[0][2])
PY
}

find_model_file() {
  [[ -d "$MODEL_DIR" ]] || return 0
  find "$MODEL_DIR" -type f -iname "*${QUANT}*.gguf" ! -iname '*mmproj*' 2>/dev/null \
    | sort | head -n1
}

validate_model_file() {
  local model="$1" size
  [[ -f "$model" && -r "$model" ]] || die "Model file is not a readable regular file: $model"
  size="$(stat -c %s -- "$model")"
  ((size >= 1073741824)) || die "Model file is too small to be valid (under 1 GiB): $model"
  [[ "$(head -c 4 -- "$model")" == "GGUF" ]] || die "Model file does not have GGUF magic bytes: $model"
}

download_model() {
  mkdir -p "$MODEL_DIR"
  local existing
  existing="$(find_model_file)"
  if [[ -n "$existing" ]]; then
    validate_model_file "$existing"
    ok "Model already present: $existing"
    return 0
  fi

  local free_gb
  free_gb="$(disk_free_gb "$MODEL_DIR")"
  ((free_gb >= 25)) || die "Only ${free_gb} GB free; need >= 25 GB for the download."

  ensure_venv

  if [[ -z "$MODEL_REPO" ]]; then
    info "Discovering GGUF repo for Qwen3.8-27B on Hugging Face..."
    if ! MODEL_REPO="$(discover_repo)"; then
      die "Could not auto-discover a trusted GGUF repo. Set it manually:  MODEL_REPO=<org>/<repo> $0 download"
    fi
  fi
  info "Repo: $MODEL_REPO   Quant: $QUANT"

  "$VENV_DIR/bin/python" - "$MODEL_REPO" "$QUANT" "$MODEL_DIR" <<'PY' \
    || die "Download failed (check repo name, quant pattern, HF_TOKEN, connectivity)."
import sys
from huggingface_hub import snapshot_download
repo, quant, dest = sys.argv[1:4]
path = snapshot_download(
    repo_id=repo,
    allow_patterns=[f"*{quant}*.gguf", f"*/*{quant}*.gguf", f"*{quant}*/*.gguf"],
    local_dir=dest,
)
print(path)
PY

  existing="$(find_model_file)"
  [[ -n "$existing" ]] || die "No *${QUANT}*.gguf found after download. Try a different QUANT (e.g. Q4_K_M, Q5_K_M, UD-Q4_K_XL)."

  validate_model_file "$existing"
  ok "Model ready: $existing"
}

# --------------------------------- run ---------------------------------------
SERVER_ARGS=()

choose_ctx() {
  if [[ -n "$CTX" ]]; then
    [[ "$CTX" =~ ^[0-9]+$ ]] || die "CTX must be an integer."
    return 0
  fi
  detect_vram
  if   ((VRAM_MIB >= 22000)); then CTX=65536
  elif ((VRAM_MIB >= 20000)); then CTX=32768
  elif ((VRAM_MIB >=     1)); then CTX=16384; warn "Low VRAM ($VRAM_MIB MiB): CTX=$CTX"
  else CTX=32768
  fi
  info "Context size: $CTX tokens (override with CTX=...)"
}

build_server_args() {
  local check_port="${1:-yes}"
  resolve_backend
  [[ -x "$SERVER_BIN" ]] || die "llama-server not built yet. Run: $0 build"

  local model
  model="$(find_model_file)"
  [[ -n "$model" ]] || die "No model found in $MODEL_DIR. Run: $0 download"
  validate_model_file "$model"

  choose_ctx

  # Port must be free
  if [[ "$check_port" == "yes" ]] && have ss \
      && ss -H -ltn "sport = :$PORT" | grep -q .; then
    die "Port $PORT is already in use. Set PORT=... or stop the other process."
  fi

  # Flash-attn flag syntax differs between llama.cpp versions
  local fa=(-fa)
  if "$SERVER_BIN" --help 2>&1 | grep -q 'on|off|auto'; then fa=(-fa on); fi

  SERVER_ARGS=(
    "$SERVER_BIN"
    -m "$model"
    -ngl 99
    -c "$CTX"
    --parallel 1
    "${fa[@]}"
    --cache-type-k q8_0 --cache-type-v q8_0
    --jinja
    --host "$HOST" --port "$PORT"
  )
  if [[ -n "$EXTRA_ARGS" ]]; then
    local -a extra_args=()
    read -r -a extra_args <<<"$EXTRA_ARGS"
    SERVER_ARGS+=("${extra_args[@]}")
  fi

}

wait_healthy() {
  local timeout="${1:-300}" i=0
  local endpoint
  endpoint="http://$(format_host "$HOST"):$PORT/health"
  local auth=()
  [[ -n "$LLAMA_API_KEY" ]] && auth=(-H "Authorization: Bearer $LLAMA_API_KEY")
  # Feed credentials through curl's stdin config, not its process arguments.
  info "Waiting for server health (up to ${timeout}s)..."
  while ((i < timeout)); do
    if [[ -n "$LLAMA_API_KEY" ]]; then
      if printf 'header = "%s"\n' "${auth[1]}" \
          | curl --config - --noproxy '*' -fsS --max-time 3 "$endpoint" >/dev/null 2>&1; then
        ok "Server is healthy."
        return 0
      fi
    elif curl --noproxy '*' -fsS --max-time 3 "$endpoint" >/dev/null 2>&1; then
      ok "Server is healthy."
      return 0
    fi
    sleep 2; i=$((i + 2))
  done
  return 1
}

print_client_hint() {
  local base_url
  base_url="http://$(format_host "$HOST"):$PORT"
  cat <<EOF

------------------------------------------------------------------
 Server:   ${base_url}/v1
 Model ID: run  curl -s ${base_url}/v1/models | jq -r '.data[0].id'
 API key:  $([[ -n "$LLAMA_API_KEY" ]] && printf 'configured (use your configured key)' || printf 'not required')

 VS Code (Cline / Roo Code):
   Provider     -> OpenAI Compatible
   Base URL     -> ${base_url}/v1
   Context size -> ${CTX}
------------------------------------------------------------------
EOF
}

run_server() {
  build_server_args
  print_client_hint
  info "Starting llama-server (Ctrl+C to stop)..."
  [[ -n "$LLAMA_API_KEY" ]] && SERVER_ARGS+=(--api-key "$LLAMA_API_KEY")
  exec "${SERVER_ARGS[@]}"
}

# ------------------------------- systemd -------------------------------------
systemd_quote_arg() {
  local value="$1"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] \
    || die "A server argument contains a newline and cannot be written to a systemd unit."
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//%/%%}"
  value="${value//\$/\$\$}"
  printf '"%s"' "$value"
}

install_service() {
  have systemctl || die "systemctl not available."
  build_server_args no

  local unit_dir="$HOME/.config/systemd/user"
  local unit="$unit_dir/$SERVICE_NAME.service"
  local env_file="$unit_dir/$SERVICE_NAME.env"
  local unit_tmp env_tmp exec_line="" a was_active=0
  local -a service_args=("${SERVER_ARGS[@]}")
  mkdir -p "$unit_dir"

  for a in "${service_args[@]}"; do
    exec_line+="$(systemd_quote_arg "$a") "
  done
  if [[ -n "$LLAMA_API_KEY" ]]; then
    exec_line+="\"--api-key\" \${LLAMA_API_KEY}"
    env_tmp="$(mktemp "$unit_dir/$SERVICE_NAME.env.XXXXXX")"
    printf 'LLAMA_API_KEY=%s\n' "$LLAMA_API_KEY" >"$env_tmp"
    chmod 600 "$env_tmp"
    mv -f -- "$env_tmp" "$env_file"
  else
    rm -f -- "$env_file"
  fi

  unit_tmp="$(mktemp "$unit_dir/$SERVICE_NAME.service.XXXXXX")"
  {
    cat <<EOF
[Unit]
Description=llama.cpp server (Qwen3.8-27B)
After=network-online.target

[Service]
Type=simple
ExecStart=${exec_line}
EOF
    if [[ -n "$LLAMA_API_KEY" ]]; then
      printf 'EnvironmentFile=%s\n' "%h/.config/systemd/user/$SERVICE_NAME.env"
    fi
    cat <<EOF
Restart=on-failure
RestartSec=5
TimeoutStartSec=600

[Install]
WantedBy=default.target
EOF
  } >"$unit_tmp"
  chmod 600 "$unit_tmp"
  mv -f -- "$unit_tmp" "$unit"
  ok "Wrote $unit"

  if systemctl --user is-active --quiet "$SERVICE_NAME.service"; then
    was_active=1
  fi
  systemctl --user daemon-reload
  systemctl --user enable --now "$SERVICE_NAME.service"
  if ((was_active)); then
    systemctl --user restart "$SERVICE_NAME.service"
  fi

  if confirm "Enable linger so the service starts at boot without login?"; then
    ensure_sudo
    local current_user
    current_user="$(id -un 2>/dev/null || printf 'UID %s' "$(id -u)")"
    run_privileged loginctl enable-linger "$current_user" && ok "Linger enabled."
  fi

  if wait_healthy 300; then
    print_client_hint
  else
    warn "Service did not become healthy. Logs:  journalctl --user -u $SERVICE_NAME -n 80 --no-pager"
    exit 1
  fi
}

show_status() {
  if have systemctl && systemctl --user list-unit-files "$SERVICE_NAME.service" 2>/dev/null | grep -q "$SERVICE_NAME"; then
    systemctl --user --no-pager status "$SERVICE_NAME.service" || true
  else
    info "systemd service not installed."
  fi
  if wait_healthy 2; then
    ok "API healthy at http://$(format_host "$HOST"):$PORT"
  else
    warn "API not responding on port $PORT."
  fi
  if have rocm-smi; then rocm-smi --showmeminfo vram 2>/dev/null || true; fi
}

# --------------------------------- main --------------------------------------
usage() { sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; }

main() {
  local cmd="${1:-all}"

  case "$cmd" in
    all|doctor|deps|build|download|run|service|status) ;;
    help|-h|--help) usage; return 0 ;;
    *) usage; die "Unknown command: $cmd" ;;
  esac

  validate_config

  # single-instance lock for mutating commands
  case "$cmd" in
    all|deps|build|download|service)
      mkdir -p "$INSTALL_DIR"
      need_cmd flock
      exec 9>"$INSTALL_DIR/.lock"
      flock -n 9 || die "Another instance of this script is running."
      ;;
  esac

  case "$cmd" in
    all)      preflight; install_deps; build_llama; download_model; run_server ;;
    doctor)   preflight ;;
    deps)     preflight; install_deps ;;
    build)    install_deps; build_llama ;;
    download) download_model ;;
    run)      run_server ;;
    service)  install_service ;;
    status)   show_status ;;
    help|-h|--help) usage ;;
  esac
}

main "$@"
