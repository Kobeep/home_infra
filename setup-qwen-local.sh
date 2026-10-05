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
#   LLAMA_REF      git branch/tag/commit            (default: master)
#   LLAMA_API_KEY  if set, server requires this key
#   EXTRA_ARGS     extra llama-server arguments (e.g. sampling flags)
#   FORCE_REBUILD  1 = rebuild even if up to date
#   ASSUME_YES     1 = skip confirmation prompts
#   HF_TOKEN       Hugging Face token (picked up automatically if needed)
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

LLAMA_REPO_URL="https://github.com/ggml-org/llama.cpp"
SRC_DIR="$INSTALL_DIR/llama.cpp"
VENV_DIR="$INSTALL_DIR/venv"
BUILD_DIR=""            # set after backend resolution
SERVER_BIN=""
SERVICE_NAME="llama-qwen"
MIN_DISK_GB=40          # model (~16GB) + build + headroom
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

trap 'die "Unexpected error at line $LINENO: $BASH_COMMAND"' ERR
trap 'printf "\n"; warn "Interrupted."; exit 130' INT TERM

# ------------------------------- helpers -------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

need_cmd() { have "$1" || die "Required command not found: $1"; }

confirm() {
  [[ "$ASSUME_YES" == "1" ]] && return 0
  [[ -t 0 ]] || return 0   # non-interactive: proceed
  local reply
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

SUDO=""
ensure_sudo() {
  if [[ $EUID -eq 0 ]]; then SUDO=""; return 0; fi
  need_cmd sudo
  SUDO="sudo"
  sudo -v || die "sudo authentication failed"
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
  $SUDO dnf install -y --setopt=install_weak_deps=False "${missing[@]}" \
    || die "dnf failed to install: ${missing[*]}"
}

try_install_pkgs() {   # optional packages: failure is a warning
  local p
  for p in "$@"; do
    if pkg_installed "$p"; then continue; fi
    ensure_sudo
    if $SUDO dnf install -y --setopt=install_weak_deps=False "$p" >/dev/null 2>&1; then
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
  if ! curl -fsS --max-time 8 -o /dev/null https://huggingface.co 2>/dev/null \
     && ! have curl; then
    warn "curl missing or huggingface.co unreachable (curl will be installed in deps step)."
  elif ! curl -fsS --max-time 8 -o /dev/null https://huggingface.co 2>/dev/null; then
    warn "Cannot reach huggingface.co right now - download step may fail."
  else
    ok "Network: huggingface.co reachable"
  fi

  # Resources
  local free_gb ram_gb
  free_gb="$(disk_free_gb "$MODEL_DIR")"
  if ((free_gb < MIN_DISK_GB)); then
    die "Only ${free_gb} GB free near $MODEL_DIR; need >= ${MIN_DISK_GB} GB."
  fi
  ok "Disk: ${free_gb} GB free"

  ram_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  ((ram_gb >= 16)) && ok "RAM: ${ram_gb} GB" || warn "RAM: ${ram_gb} GB (build may be slow / swap)"

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

  # Device access
  local g missing_groups=()
  for g in video render; do
    id -nG | tr ' ' '\n' | grep -qx "$g" || missing_groups+=("$g")
  done
  if ((${#missing_groups[@]})); then
    warn "User '$USER' not in group(s): ${missing_groups[*]} -> GPU access may fail."
    warn "Fix: sudo usermod -aG video,render $USER  (then log out/in)"
  else
    ok "Groups: video, render"
  fi
  if [[ -e /dev/dri/renderD128 && ! -r /dev/dri/renderD128 ]]; then
    warn "/dev/dri/renderD128 not readable by current user."
  fi
}

# ------------------------------ backend --------------------------------------
resolve_backend() {
  case "$BACKEND" in
    auto)   BACKEND="vulkan" ;;
    vulkan|rocm) ;;
    *) die "Invalid BACKEND='$BACKEND' (use auto|vulkan|rocm)." ;;
  esac
  BUILD_DIR="$SRC_DIR/build-$BACKEND"
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
        rocminfo 2>/dev/null | grep -q 'gfx' \
          && ok "ROCm sees: $(rocminfo | grep -o 'gfx[0-9a-f]*' | sort -u | tr '\n' ' ')" \
          || warn "rocminfo found no gfx agents."
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

  if [[ -d "$SRC_DIR/.git" ]]; then
    info "Updating llama.cpp ($LLAMA_REF)..."
    git -C "$SRC_DIR" fetch --tags --prune origin >/dev/null 2>&1 \
      || warn "git fetch failed (offline?) - building from existing checkout."
  else
    info "Cloning llama.cpp..."
    git clone "$LLAMA_REPO_URL" "$SRC_DIR"
  fi

  git -C "$SRC_DIR" checkout -q "$LLAMA_REF" || die "Cannot checkout '$LLAMA_REF'."
  if git -C "$SRC_DIR" show-ref --verify --quiet "refs/remotes/origin/$LLAMA_REF"; then
    git -C "$SRC_DIR" merge --ff-only -q "origin/$LLAMA_REF" \
      || warn "Could not fast-forward '$LLAMA_REF'."
  fi

  local commit stamp_file stamp
  commit="$(git -C "$SRC_DIR" rev-parse HEAD)"
  stamp_file="$BUILD_DIR/.build-stamp"
  stamp="$commit $BACKEND"

  if [[ "$FORCE_REBUILD" != "1" && -x "$SERVER_BIN" && -f "$stamp_file" \
        && "$(<"$stamp_file")" == "$stamp" ]]; then
    ok "llama-server already up to date (${commit:0:9}, $BACKEND)."
    return 0
  fi

  local cmake_args=(-S "$SRC_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
                    -DLLAMA_CURL=ON -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF)
  have ccache && cmake_args+=(-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache)

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

  info "Building with $(nproc) jobs (this takes a few minutes)..."
  cmake --build "$BUILD_DIR" --config Release -j"$(nproc)" --target llama-server llama-cli
  [[ -x "$SERVER_BIN" ]] || die "Build finished but $SERVER_BIN is missing."
  printf '%s' "$stamp" >"$stamp_file"
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
    "$VENV_DIR/bin/pip" install -q -U pip huggingface_hub \
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

download_model() {
  mkdir -p "$MODEL_DIR"
  local existing
  existing="$(find_model_file)"
  if [[ -n "$existing" ]]; then
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

  local size_gb
  size_gb=$(( $(stat -c %s "$existing") / 1024 / 1024 / 1024 ))
  ((size_gb >= 1)) || die "Downloaded file looks too small ($existing)."
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
  resolve_backend
  [[ -x "$SERVER_BIN" ]] || die "llama-server not built yet. Run: $0 build"

  local model
  model="$(find_model_file)"
  [[ -n "$model" ]] || die "No model found in $MODEL_DIR. Run: $0 download"

  choose_ctx

  # Port must be free
  if have ss && ss -H -ltn "sport = :$PORT" | grep -q .; then
    die "Port $PORT is already in use. Set PORT=... or stop the other process (or: systemctl --user stop $SERVICE_NAME)."
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
  [[ -n "$LLAMA_API_KEY" ]] && SERVER_ARGS+=(--api-key "$LLAMA_API_KEY")
  if [[ -n "$EXTRA_ARGS" ]]; then
    # shellcheck disable=SC2206
    SERVER_ARGS+=($EXTRA_ARGS)
  fi

  if [[ "$HOST" != "127.0.0.1" && "$HOST" != "localhost" && -z "$LLAMA_API_KEY" ]]; then
    warn "Server bound to $HOST without LLAMA_API_KEY - anyone on the network can use it."
  fi
}

wait_healthy() {
  local timeout="${1:-300}" i=0
  local auth=()
  [[ -n "$LLAMA_API_KEY" ]] && auth=(-H "Authorization: Bearer $LLAMA_API_KEY")
  info "Waiting for server health (up to ${timeout}s)..."
  while ((i < timeout)); do
    if curl -fsS "${auth[@]}" "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
      ok "Server is healthy."
      return 0
    fi
    sleep 2; i=$((i + 2))
  done
  return 1
}

print_client_hint() {
  cat <<EOF

------------------------------------------------------------------
 Server:   http://${HOST}:${PORT}/v1
 Model ID: run  curl -s http://127.0.0.1:${PORT}/v1/models | jq -r '.data[0].id'
 API key:  ${LLAMA_API_KEY:-<anything, e.g. "local">}

 VS Code (Cline / Roo Code):
   Provider     -> OpenAI Compatible
   Base URL     -> http://127.0.0.1:${PORT}/v1
   Context size -> ${CTX}
------------------------------------------------------------------
EOF
}

run_server() {
  build_server_args
  print_client_hint
  info "Starting llama-server (Ctrl+C to stop)..."
  exec "${SERVER_ARGS[@]}"
}

# ------------------------------- systemd -------------------------------------
install_service() {
  have systemctl || die "systemctl not available."
  build_server_args

  local unit_dir="$HOME/.config/systemd/user"
  local unit="$unit_dir/$SERVICE_NAME.service"
  mkdir -p "$unit_dir"

  local exec_line="" a
  for a in "${SERVER_ARGS[@]}"; do
    a="${a//\\/\\\\}"; a="${a//\"/\\\"}"
    exec_line+="\"$a\" "
  done

  cat >"$unit" <<EOF
[Unit]
Description=llama.cpp server (Qwen3.8-27B)
After=network-online.target

[Service]
Type=simple
ExecStart=${exec_line}
Restart=on-failure
RestartSec=5
TimeoutStartSec=600

[Install]
WantedBy=default.target
EOF
  ok "Wrote $unit"

  systemctl --user daemon-reload
  systemctl --user enable --now "$SERVICE_NAME.service"

  if confirm "Enable linger so the service starts at boot without login?"; then
    ensure_sudo
    $SUDO loginctl enable-linger "$USER" && ok "Linger enabled."
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
  if curl -fsS --max-time 3 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    ok "API healthy at http://127.0.0.1:$PORT"
  else
    warn "API not responding on port $PORT."
  fi
  if have rocm-smi; then rocm-smi --showmeminfo vram 2>/dev/null || true; fi
}

# --------------------------------- main --------------------------------------
usage() { sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; }

main() {
  local cmd="${1:-all}"

  # single-instance lock for mutating commands
  case "$cmd" in
    all|deps|build|download|service)
      mkdir -p "$INSTALL_DIR"
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
    *) usage; die "Unknown command: $cmd" ;;
  esac
}

main "$@"
