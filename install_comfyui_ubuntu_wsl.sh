#!/usr/bin/env bash
# Install or update ComfyUI on native Ubuntu or Ubuntu running under WSL2.
#
# Features:
#   - Detects platform: native Ubuntu vs WSL2 Ubuntu
#   - Detects GPU backend: NVIDIA/CUDA or AMD/ROCm
#   - Uses the latest supported CUDA/ROCm package source for the detected Ubuntu mode
#   - Installs latest ComfyUI from https://github.com/comfy-org/ComfyUI
#   - Installs latest matching PyTorch wheels from the newest usable PyTorch wheel index
#   - Creates launchers: ~/ComfyUI/run_comfyui.sh and ~/.local/bin/comfyui
#
# Usage:
#   chmod +x install_comfyui_ubuntu_wsl.sh
#   ./install_comfyui_ubuntu_wsl.sh
#
# Common overrides:
#   COMFYUI_BACKEND=auto|cuda|rocm      # default: auto
#   COMFYUI_DIR=$HOME/ComfyUI           # install/update directory
#   COMFYUI_VENV=$COMFYUI_DIR/.venv     # virtualenv directory
#   INSTALL_SYSTEM_GPU=1                # 1 = install CUDA/ROCm OS packages, 0 = skip OS GPU packages
#   PYTORCH_CHANNEL=stable|nightly      # default: stable
#   COMFYUI_HOST=127.0.0.1              # launch listen host; use 0.0.0.0 for LAN
#   COMFYUI_PORT=8188                   # launch port
#   SKIP_GPU_VERIFY=0                   # 1 = do not treat torch GPU check failure as fatal
#   PYTHON_BIN=python3                  # Python interpreter used to create venv
#
# WSL-specific overrides:
#   WSL_SKIP_HOST_GPU_CHECK=0           # 1 = skip checks for Windows-side GPU exposure
#   ROCDXG_AUTO_BUILD=1                 # 1 = build/install AMD ROCDXG on WSL ROCm
#   WIN_SDK_INCLUDE=/mnt/c/.../Include/10.0.x.y
#                                      # optional Windows SDK Include path for ROCDXG build
#
# Important WSL notes:
#   - NVIDIA WSL2: install/update the NVIDIA Windows driver on Windows. This script does NOT install a Linux NVIDIA display driver in WSL.
#   - AMD WSL2: install AMD Adrenalin for WSL2 and the Windows SDK on Windows before running this script. This script builds librocdxg when possible.

set -Eeuo pipefail
IFS=$'\n\t'
export DEBIAN_FRONTEND=noninteractive

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

if [[ "${EUID}" -eq 0 ]]; then
  die "Run this script as your normal user, not with sudo. It will ask for sudo only when needed."
fi
command -v sudo >/dev/null 2>&1 || die "sudo is required. Install/configure sudo, then run again."
SUDO="sudo"

COMFYUI_BACKEND="${COMFYUI_BACKEND:-auto}"
INSTALL_SYSTEM_GPU="${INSTALL_SYSTEM_GPU:-1}"
PYTORCH_CHANNEL="${PYTORCH_CHANNEL:-stable}"
COMFYUI_DIR="${COMFYUI_DIR:-$HOME/ComfyUI}"
VENV_DIR="${COMFYUI_VENV:-$COMFYUI_DIR/.venv}"
COMFYUI_HOST="${COMFYUI_HOST:-127.0.0.1}"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"
SKIP_GPU_VERIFY="${SKIP_GPU_VERIFY:-0}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
WSL_SKIP_HOST_GPU_CHECK="${WSL_SKIP_HOST_GPU_CHECK:-0}"
ROCDXG_AUTO_BUILD="${ROCDXG_AUTO_BUILD:-1}"
WIN_SDK_INCLUDE="${WIN_SDK_INCLUDE:-}"

APT_UPDATED=0
UBUNTU_VERSION_ID=""
UBUNTU_CODENAME=""
PLATFORM="native"
BACKEND=""

apt_update_once() {
  if [[ "$APT_UPDATED" -eq 0 ]]; then
    log "Updating APT package lists"
    $SUDO apt-get update
    APT_UPDATED=1
  fi
}

apt_install() {
  apt_update_once
  $SUDO apt-get install -y --no-install-recommends "$@"
}

is_wsl() {
  grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null || \
  grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null
}

is_wsl2_gpu_node_present() {
  [[ -e /dev/dxg || -e /usr/lib/wsl/lib/libcuda.so || -e /usr/lib/wsl/lib/libcuda.so.1 ]]
}

require_ubuntu() {
  [[ -r /etc/os-release ]] || die "/etc/os-release not found; this installer supports Ubuntu only."
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "Detected '${PRETTY_NAME:-unknown}'. This script supports Ubuntu only."
  UBUNTU_VERSION_ID="${VERSION_ID:-}"
  UBUNTU_CODENAME="${VERSION_CODENAME:-}"
  [[ -n "$UBUNTU_VERSION_ID" && -n "$UBUNTU_CODENAME" ]] || die "Could not detect Ubuntu version/codename."

  if is_wsl; then
    PLATFORM="wsl"
    log "Detected Ubuntu ${UBUNTU_VERSION_ID} (${UBUNTU_CODENAME}) on WSL"
  else
    PLATFORM="native"
    log "Detected native Ubuntu ${UBUNTU_VERSION_ID} (${UBUNTU_CODENAME})"
  fi
}

require_supported_gpu_os_version() {
  local component="$1"
  case "$UBUNTU_VERSION_ID" in
    22.04|24.04) return 0 ;;
    *)
      die "${component} setup is currently automated only for Ubuntu 22.04 and 24.04. Detected Ubuntu ${UBUNTU_VERSION_ID}. Set INSTALL_SYSTEM_GPU=0 if you already have the GPU stack installed, or use Ubuntu 22.04/24.04."
      ;;
  esac
}

require_amd64() {
  local arch
  arch="$(dpkg --print-architecture)"
  [[ "$arch" == "amd64" ]] || die "Detected architecture '$arch'. This installer targets x86_64/amd64 GPU PyTorch wheels and WSL GPU stacks."
}

ubuntu_to_cuda_distro() {
  if [[ "$PLATFORM" == "wsl" ]]; then
    printf 'wsl-ubuntu\n'
    return
  fi
  case "$UBUNTU_VERSION_ID" in
    24.04) printf 'ubuntu2404\n' ;;
    22.04) printf 'ubuntu2204\n' ;;
    *) die "CUDA repository mapping for Ubuntu ${UBUNTU_VERSION_ID} is not supported. Use Ubuntu 22.04/24.04 or set INSTALL_SYSTEM_GPU=0." ;;
  esac
}

ubuntu_to_rocm_codename() {
  case "$UBUNTU_VERSION_ID" in
    24.04) printf 'noble\n' ;;
    22.04) printf 'jammy\n' ;;
    *) die "ROCm repository mapping for Ubuntu ${UBUNTU_VERSION_ID} is not supported. Use Ubuntu 22.04/24.04 or set INSTALL_SYSTEM_GPU=0." ;;
  esac
}

windows_gpu_names() {
  command -v powershell.exe >/dev/null 2>&1 || return 0
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
    "Get-CimInstance Win32_VideoController | ForEach-Object { \$_.Name }" 2>/dev/null | tr -d '\r' || true
}

nvidia_wsl_visible() {
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x /usr/lib/wsl/lib/nvidia-smi ]] && /usr/lib/wsl/lib/nvidia-smi >/dev/null 2>&1; then
    return 0
  fi
  [[ -e /usr/lib/wsl/lib/libcuda.so || -e /usr/lib/wsl/lib/libcuda.so.1 ]]
}

native_gpu_lines() {
  lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' || true
}

detect_backend() {
  case "$COMFYUI_BACKEND" in
    cuda|nvidia) printf 'cuda\n'; return ;;
    rocm|amd)    printf 'rocm\n'; return ;;
    auto) ;;
    *) die "COMFYUI_BACKEND must be auto, cuda, or rocm." ;;
  esac

  local gpu_lines win_gpus
  if [[ "$PLATFORM" == "wsl" ]]; then
    if nvidia_wsl_visible; then
      printf 'cuda\n'
      return
    fi

    win_gpus="$(windows_gpu_names)"
    if grep -Eiq 'NVIDIA' <<<"$win_gpus"; then
      printf 'cuda\n'
      return
    fi
    if grep -Eiq 'Advanced Micro Devices|AMD|Radeon|ATI' <<<"$win_gpus"; then
      printf 'rocm\n'
      return
    fi

    gpu_lines="$(native_gpu_lines)"
    if grep -Eiq 'NVIDIA' <<<"$gpu_lines"; then
      printf 'cuda\n'
    elif grep -Eiq 'Advanced Micro Devices|AMD|Radeon|ATI' <<<"$gpu_lines"; then
      printf 'rocm\n'
    else
      die "Could not auto-detect NVIDIA or AMD GPU in WSL. Set COMFYUI_BACKEND=cuda or COMFYUI_BACKEND=rocm. Windows GPU names seen: ${win_gpus:-none}. lspci GPU lines: ${gpu_lines:-none}."
    fi
  else
    gpu_lines="$(native_gpu_lines)"
    [[ -n "$gpu_lines" ]] || die "No GPU found in lspci output. Install pciutils or set COMFYUI_BACKEND=cuda/rocm manually."
    if grep -Eiq 'NVIDIA' <<<"$gpu_lines"; then
      printf 'cuda\n'
    elif grep -Eiq 'Advanced Micro Devices|AMD|Radeon|ATI' <<<"$gpu_lines"; then
      printf 'rocm\n'
    else
      die "No NVIDIA or AMD GPU detected. GPU lines: $gpu_lines"
    fi
  fi
}

install_base_packages() {
  log "Installing base packages"
  apt_install \
    ca-certificates curl wget gnupg lsb-release pciutils git \
    python3 python3-venv python3-pip python3-dev \
    build-essential pkg-config ffmpeg libgl1 libglib2.0-0 \
    software-properties-common cmake

  if [[ "$PLATFORM" == "native" ]]; then
    apt_install ubuntu-drivers-common
  fi
}

install_cuda_repo() {
  local distro arch keyring_url tmpdeb
  require_supported_gpu_os_version "CUDA"
  require_amd64
  distro="$(ubuntu_to_cuda_distro)"
  arch="x86_64"
  keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/${distro}/${arch}/cuda-keyring_1.1-1_all.deb"
  tmpdeb="/tmp/cuda-keyring_1.1-1_all.deb"

  log "Configuring NVIDIA CUDA repository: ${distro}/${arch}"
  curl -fsSL "$keyring_url" -o "$tmpdeb" || die "Could not download CUDA keyring from $keyring_url"
  $SUDO dpkg -i "$tmpdeb"
  APT_UPDATED=0
  apt_update_once
}

latest_cuda_toolkit_package() {
  local pkg
  pkg="$(apt-cache pkgnames cuda-toolkit 2>/dev/null | grep -E '^cuda-toolkit-[0-9]+-[0-9]+$' | sort -V | tail -n1 || true)"
  if [[ -n "$pkg" ]]; then
    printf '%s\n' "$pkg"
  else
    printf 'cuda-toolkit\n'
  fi
}

install_nvidia_cuda_stack_native() {
  install_cuda_repo

  if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi >/dev/null 2>&1; then
    warn "nvidia-smi is not working yet. Installing the Ubuntu-recommended NVIDIA display driver. A reboot may be required."
    $SUDO ubuntu-drivers install || warn "ubuntu-drivers install failed or found no driver. Continuing with CUDA toolkit/PyTorch install."
    APT_UPDATED=0
    apt_update_once
  fi

  local toolkit_pkg
  toolkit_pkg="$(latest_cuda_toolkit_package)"
  log "Installing latest CUDA toolkit package available: ${toolkit_pkg}"
  $SUDO apt-get install -y --no-install-recommends "$toolkit_pkg"
}

install_nvidia_cuda_stack_wsl() {
  install_cuda_repo

  if [[ "$WSL_SKIP_HOST_GPU_CHECK" != "1" ]]; then
    if ! nvidia_wsl_visible; then
      warn "NVIDIA GPU is not visible inside WSL yet. Install/update the NVIDIA Windows driver, run 'wsl.exe --update' from Windows, then restart WSL. Continuing because PyTorch CUDA wheels can still be installed."
    fi
  fi

  local toolkit_pkg
  toolkit_pkg="$(latest_cuda_toolkit_package)"
  log "Installing CUDA toolkit for WSL only: ${toolkit_pkg}"
  warn "WSL mode: not installing Linux NVIDIA display drivers or cuda-drivers. The Windows NVIDIA driver provides libcuda to WSL."
  $SUDO apt-get install -y --no-install-recommends "$toolkit_pkg"
}

latest_amdgpu_install_version() {
  local html version
  html="$(curl -fsSL https://repo.radeon.com/amdgpu-install/ || true)"
  version="$(grep -oE 'href="[0-9]+\.[0-9]+(\.[0-9]+)?/' <<<"$html" | sed -E 's/href="//; s#/##' | sort -V | tail -n1 || true)"
  [[ -n "$version" ]] || version="7.2.3"
  printf '%s\n' "$version"
}

install_amd_rocm_repo() {
  local codename version base html deb_name tmpdeb
  require_supported_gpu_os_version "ROCm"
  require_amd64
  codename="$(ubuntu_to_rocm_codename)"
  version="$(latest_amdgpu_install_version)"
  base="https://repo.radeon.com/amdgpu-install/${version}/ubuntu/${codename}"

  log "Configuring AMD ROCm repository using latest detected amdgpu-install ${version} for Ubuntu ${codename}"
  html="$(curl -fsSL "${base}/" || true)"
  deb_name="$(grep -oE 'amdgpu-install_[^" ]+_all\.deb' <<<"$html" | head -n1 || true)"
  if [[ -z "$deb_name" ]]; then
    if [[ "$version" == "7.2.3" ]]; then
      deb_name="amdgpu-install_7.2.3.70203-1_all.deb"
      base="https://repo.radeon.com/amdgpu-install/7.2.3/ubuntu/${codename}"
    else
      die "Could not find amdgpu-install .deb at ${base}/"
    fi
  fi

  tmpdeb="/tmp/${deb_name}"
  curl -fsSL "${base}/${deb_name}" -o "$tmpdeb" || die "Could not download ${base}/${deb_name}"
  $SUDO apt-get install -y "$tmpdeb"
  APT_UPDATED=0
  apt_update_once
}

install_amd_rocm_stack_native() {
  install_amd_rocm_repo

  log "Installing AMD ROCm packages for native Ubuntu"
  $SUDO apt-get install -y "linux-headers-$(uname -r)" "linux-modules-extra-$(uname -r)" || \
    warn "Could not install linux headers/modules for this kernel. Continuing; amdgpu-dkms may still work if already available."
  $SUDO apt-get install -y --no-install-recommends amdgpu-dkms
  $SUDO apt-get install -y --no-install-recommends python3-setuptools python3-wheel rocm
  $SUDO usermod -aG render,video "$USER"

  write_rocm_profile native
}

find_windows_sdk_include() {
  if [[ -n "$WIN_SDK_INCLUDE" ]]; then
    [[ -d "$WIN_SDK_INCLUDE/shared" ]] || die "WIN_SDK_INCLUDE was set to '$WIN_SDK_INCLUDE', but '$WIN_SDK_INCLUDE/shared' does not exist."
    printf '%s\n' "$WIN_SDK_INCLUDE"
    return
  fi

  local root sdk
  root="/mnt/c/Program Files (x86)/Windows Kits/10/Include"
  if [[ ! -d "$root" ]]; then
    return 1
  fi
  sdk="$(find "$root" -mindepth 1 -maxdepth 1 -type d -name '10.*' 2>/dev/null | sort -V | tail -n1 || true)"
  [[ -n "$sdk" && -d "$sdk/shared" ]] || return 1
  printf '%s\n' "$sdk"
}

build_librocdxg() {
  local src sdk jobs
  [[ "$ROCDXG_AUTO_BUILD" == "1" ]] || { warn "Skipping ROCDXG build because ROCDXG_AUTO_BUILD=0"; return; }

  if [[ ! -e /dev/dxg ]]; then
    warn "/dev/dxg is not present. AMD/NVIDIA GPU passthrough is not visible in this WSL instance. ROCDXG build can continue, but ROCm validation may fail until WSL GPU support is fixed."
  fi

  sdk="$(find_windows_sdk_include)" || die "Windows SDK Include path was not found under /mnt/c/Program Files (x86)/Windows Kits/10/Include. Install the Windows SDK on Windows, or rerun with WIN_SDK_INCLUDE=/mnt/c/.../Include/<version>."
  src="$HOME/librocdxg"
  jobs="$(nproc 2>/dev/null || printf '2')"

  log "Building AMD ROCDXG from source using Windows SDK: ${sdk}"
  if [[ -d "$src/.git" ]]; then
    git -C "$src" fetch --depth 1 origin develop || git -C "$src" fetch --depth 1 origin main || true
    git -C "$src" pull --ff-only || warn "Could not fast-forward existing ${src}. Continuing with current checkout."
  else
    rm -rf "$src"
    git clone --depth 1 https://github.com/ROCm/librocdxg.git "$src"
  fi

  cmake -S "$src" -B "$src/build" \
    -DWIN_SDK="${sdk}/shared" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/rocm
  cmake --build "$src/build" --parallel "$jobs"
  $SUDO cmake --install "$src/build"
}

install_amd_rocm_stack_wsl() {
  install_amd_rocm_repo

  log "Installing ROCm user-space packages for WSL"
  warn "WSL mode: not installing amdgpu-dkms or Linux Radeon display drivers. The Windows AMD driver plus ROCDXG provides the WSL compute path."
  $SUDO apt-get install -y --no-install-recommends python3-setuptools python3-wheel rocm cmake gcc g++ make

  build_librocdxg
  write_rocm_profile wsl
}

write_rocm_profile() {
  local mode="$1"
  local profile="/etc/profile.d/comfyui-rocm.sh"

  if [[ "$mode" == "wsl" ]]; then
    cat <<'PROFILE' | $SUDO tee "$profile" >/dev/null
export PATH=/opt/rocm/bin:$PATH
export LD_LIBRARY_PATH=/opt/rocm/lib:/usr/lib/wsl/lib:${LD_LIBRARY_PATH:-}
export HSA_ENABLE_DXG_DETECTION=1
PROFILE
  else
    cat <<'PROFILE' | $SUDO tee "$profile" >/dev/null
export PATH=/opt/rocm/bin:$PATH
export LD_LIBRARY_PATH=/opt/rocm/lib:${LD_LIBRARY_PATH:-}
PROFILE
  fi
}

make_venv() {
  log "Creating/updating Python virtual environment at ${VENV_DIR}"
  command -v "$PYTHON_BIN" >/dev/null 2>&1 || die "${PYTHON_BIN} not found. Set PYTHON_BIN=/path/to/python3 if needed."
  mkdir -p "$COMFYUI_DIR"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
  "$VENV_DIR/bin/python" -m pip install --upgrade pip setuptools wheel
}

fetch_pytorch_candidates() {
  local backend html
  backend="$1"
  html="$(curl -fsSL https://download.pytorch.org/whl/ || true)"
  if [[ -n "$html" ]]; then
    if [[ "$backend" == "cuda" ]]; then
      grep -oE 'href="cu[0-9]+/' <<<"$html" | sed -E 's/href="//; s#/##' | sort -Vr
    else
      grep -oE 'href="rocm[0-9]+(\.[0-9]+)?/' <<<"$html" | sed -E 's/href="//; s#/##' | sort -Vr
    fi
  fi

  # Known-good fallbacks. The dynamic discovery above is preferred.
  if [[ "$backend" == "cuda" ]]; then
    printf '%s\n' cu130 cu128 cu126 cu121 cu118
  else
    printf '%s\n' rocm7.2 rocm7.1 rocm7.0 rocm6.4 rocm6.3 rocm6.2.4 rocm6.2 rocm6.1 rocm6.0
  fi
}

select_pytorch_index() {
  local backend tag url checked
  backend="$1"
  checked=""

  if [[ "$PYTORCH_CHANNEL" == "nightly" ]]; then
    for tag in $(fetch_pytorch_candidates "$backend" | awk '!seen[$0]++'); do
      url="https://download.pytorch.org/whl/nightly/${tag}"
      checked+=" ${url}"
      if "$VENV_DIR/bin/python" -m pip index versions torch --pre --index-url "$url" >/dev/null 2>&1; then
        printf '%s\n' "$url"
        return
      fi
    done
  elif [[ "$PYTORCH_CHANNEL" == "stable" ]]; then
    for tag in $(fetch_pytorch_candidates "$backend" | awk '!seen[$0]++'); do
      url="https://download.pytorch.org/whl/${tag}"
      checked+=" ${url}"
      if "$VENV_DIR/bin/python" -m pip index versions torch --index-url "$url" >/dev/null 2>&1; then
        printf '%s\n' "$url"
        return
      fi
    done
  else
    die "PYTORCH_CHANNEL must be stable or nightly."
  fi

  die "Could not find a usable PyTorch ${backend} wheel index. Checked:${checked}"
}

install_pytorch() {
  local backend index pre_args=()
  backend="$1"
  index="$(select_pytorch_index "$backend")"
  log "Installing latest PyTorch (${PYTORCH_CHANNEL}) for ${backend} from ${index}"
  if [[ "$PYTORCH_CHANNEL" == "nightly" ]]; then
    pre_args=(--pre)
  fi
  "$VENV_DIR/bin/python" -m pip install --upgrade "${pre_args[@]}" torch torchvision torchaudio --index-url "$index"
}

clone_or_update_comfyui() {
  if [[ -d "$COMFYUI_DIR/.git" ]]; then
    log "Updating existing ComfyUI checkout in ${COMFYUI_DIR}"
    git -C "$COMFYUI_DIR" pull --ff-only
  elif [[ -e "$COMFYUI_DIR" && -n "$(find "$COMFYUI_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    die "${COMFYUI_DIR} exists but is not an empty Git checkout. Set COMFYUI_DIR to a new path or move the directory."
  else
    log "Cloning latest ComfyUI into ${COMFYUI_DIR}"
    rm -rf "$COMFYUI_DIR"
    git clone --depth 1 https://github.com/comfy-org/ComfyUI.git "$COMFYUI_DIR"
  fi
}

install_comfyui_requirements() {
  log "Installing ComfyUI Python requirements"
  "$VENV_DIR/bin/python" -m pip install --upgrade -r "$COMFYUI_DIR/requirements.txt"
}

create_launchers() {
  local launch_script bin_dir bin_link desktop_file rocm_exports cuda_exports platform_note
  launch_script="$COMFYUI_DIR/run_comfyui.sh"
  bin_dir="$HOME/.local/bin"
  bin_link="$bin_dir/comfyui"
  desktop_file="$HOME/.local/share/applications/comfyui.desktop"

  if [[ "$PLATFORM" == "wsl" ]]; then
    cuda_exports='export PATH="/usr/lib/wsl/lib:$PATH"'
  else
    cuda_exports=''
  fi
  if [[ "$BACKEND" == "rocm" && "$PLATFORM" == "wsl" ]]; then
    rocm_exports=$'export PATH="/opt/rocm/bin:$PATH"\nexport LD_LIBRARY_PATH="/opt/rocm/lib:/usr/lib/wsl/lib:${LD_LIBRARY_PATH:-}"\nexport HSA_ENABLE_DXG_DETECTION=1'
  elif [[ "$BACKEND" == "rocm" ]]; then
    rocm_exports=$'export PATH="/opt/rocm/bin:$PATH"\nexport LD_LIBRARY_PATH="/opt/rocm/lib:${LD_LIBRARY_PATH:-}"'
  else
    rocm_exports=''
  fi
  platform_note="${PLATFORM}/${BACKEND}"

  log "Creating launch script: ${launch_script}"
  cat > "$launch_script" <<EOF_LAUNCH
#!/usr/bin/env bash
set -Eeuo pipefail
cd "$COMFYUI_DIR"
source "$VENV_DIR/bin/activate"
export PYTHONUNBUFFERED=1
${cuda_exports}
${rocm_exports}
HOST="\${COMFYUI_HOST:-$COMFYUI_HOST}"
PORT="\${COMFYUI_PORT:-$COMFYUI_PORT}"
echo "Launching ComfyUI (${platform_note}) at http://\${HOST}:\${PORT}"
exec python main.py --listen "\$HOST" --port "\$PORT" "\$@"
EOF_LAUNCH
  chmod +x "$launch_script"

  mkdir -p "$bin_dir"
  ln -sfn "$launch_script" "$bin_link"
  chmod +x "$bin_link"

  mkdir -p "$(dirname "$desktop_file")"
  cat > "$desktop_file" <<EOF_DESKTOP
[Desktop Entry]
Type=Application
Name=ComfyUI
Comment=Launch ComfyUI
Exec=$launch_script
Terminal=true
Categories=Graphics;Development;
EOF_DESKTOP

  log "Launchers created:"
  printf '  %s\n' "$launch_script" "$bin_link" "$desktop_file"
}

verify_torch() {
  local backend="$1"
  log "Verifying PyTorch GPU backend"

  if [[ "$backend" == "rocm" ]]; then
    export PATH="/opt/rocm/bin:$PATH"
    if [[ "$PLATFORM" == "wsl" ]]; then
      export LD_LIBRARY_PATH="/opt/rocm/lib:/usr/lib/wsl/lib:${LD_LIBRARY_PATH:-}"
      export HSA_ENABLE_DXG_DETECTION=1
    else
      export LD_LIBRARY_PATH="/opt/rocm/lib:${LD_LIBRARY_PATH:-}"
    fi
  elif [[ "$PLATFORM" == "wsl" ]]; then
    export PATH="/usr/lib/wsl/lib:$PATH"
  fi

  if "$VENV_DIR/bin/python" - <<'PY'
import sys
import torch
print(f"torch: {torch.__version__}")
print(f"torch.version.cuda: {torch.version.cuda}")
print(f"torch.version.hip: {torch.version.hip}")
print(f"torch.cuda.is_available(): {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"device count: {torch.cuda.device_count()}")
    print(f"device 0: {torch.cuda.get_device_name(0)}")
    sys.exit(0)
sys.exit(2)
PY
  then
    log "PyTorch GPU verification succeeded"
  else
    if [[ "$SKIP_GPU_VERIFY" == "1" ]]; then
      warn "PyTorch GPU verification failed, but SKIP_GPU_VERIFY=1 is set."
    else
      warn "PyTorch installed, but the GPU is not available to torch yet. See the notes below, then rerun: $COMFYUI_DIR/run_comfyui.sh"
    fi
  fi
}

print_done_notes() {
  local url_host="$COMFYUI_HOST"
  if [[ "$COMFYUI_HOST" == "0.0.0.0" ]]; then
    url_host="127.0.0.1"
  fi

  cat <<EOF_DONE

Done.

Detected mode:
  Platform: $PLATFORM
  Backend:  $BACKEND

Start ComfyUI with:
  $COMFYUI_DIR/run_comfyui.sh
or:
  comfyui

Default URL after launch:
  http://${url_host}:${COMFYUI_PORT}

Models:
  Put checkpoints in: $COMFYUI_DIR/models/checkpoints

Notes:
EOF_DONE

  if [[ "$PLATFORM" == "wsl" && "$BACKEND" == "cuda" ]]; then
    cat <<'EOF_CUDA_WSL'
  - WSL NVIDIA mode uses the Windows NVIDIA driver. Do not install Linux NVIDIA display drivers inside WSL.
  - If torch cannot see CUDA, update the NVIDIA Windows driver, run 'wsl.exe --update' from Windows, then restart WSL with 'wsl.exe --shutdown'.
EOF_CUDA_WSL
  elif [[ "$PLATFORM" == "wsl" && "$BACKEND" == "rocm" ]]; then
    cat <<'EOF_ROCM_WSL'
  - WSL AMD mode requires AMD Adrenalin for WSL2 on Windows, WSL2, the Windows SDK, ROCm user-space packages, and ROCDXG/librocdxg.
  - If torch cannot see ROCm, confirm /dev/dxg exists, HSA_ENABLE_DXG_DETECTION=1 is set, and librocdxg.so is installed under /opt/rocm/lib.
EOF_ROCM_WSL
  elif [[ "$PLATFORM" == "native" && "$BACKEND" == "cuda" ]]; then
    cat <<'EOF_CUDA_NATIVE'
  - If NVIDIA driver packages were just installed, reboot before launching if GPU verification failed.
EOF_CUDA_NATIVE
  elif [[ "$PLATFORM" == "native" && "$BACKEND" == "rocm" ]]; then
    cat <<'EOF_ROCM_NATIVE'
  - AMD users may need to log out and back in, or reboot, for render/video group membership to apply.
EOF_ROCM_NATIVE
  fi
}

main() {
  require_ubuntu
  install_base_packages

  BACKEND="$(detect_backend)"
  log "Selected backend: ${BACKEND}"

  if [[ "$PLATFORM" == "wsl" && ! is_wsl2_gpu_node_present && "$WSL_SKIP_HOST_GPU_CHECK" != "1" ]]; then
    warn "No /dev/dxg or WSL CUDA library was found. GPU acceleration in WSL requires WSL2 GPU passthrough. Continuing, but verification may fail."
  fi

  if [[ "$INSTALL_SYSTEM_GPU" == "1" ]]; then
    if [[ "$BACKEND" == "cuda" && "$PLATFORM" == "native" ]]; then
      install_nvidia_cuda_stack_native
    elif [[ "$BACKEND" == "cuda" && "$PLATFORM" == "wsl" ]]; then
      install_nvidia_cuda_stack_wsl
    elif [[ "$BACKEND" == "rocm" && "$PLATFORM" == "native" ]]; then
      install_amd_rocm_stack_native
    elif [[ "$BACKEND" == "rocm" && "$PLATFORM" == "wsl" ]]; then
      install_amd_rocm_stack_wsl
    else
      die "Unsupported platform/backend combination: ${PLATFORM}/${BACKEND}"
    fi
  else
    warn "Skipping OS-level GPU packages because INSTALL_SYSTEM_GPU=0"
  fi

  clone_or_update_comfyui
  make_venv
  install_pytorch "$BACKEND"
  install_comfyui_requirements
  create_launchers
  verify_torch "$BACKEND"
  print_done_notes
}

main "$@"
