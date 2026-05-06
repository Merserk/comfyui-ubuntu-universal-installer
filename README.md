# ⚡ ComfyUI - Universal Linux & WSL2 One-Click Installer

[![Ubuntu](https://img.shields.io/badge/Platform-Ubuntu-E95420?style=flat-square&logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![WSL2](https://img.shields.io/badge/WSL2-Supported-0078D4?style=flat-square&logo=windows&logoColor=white)](https://learn.microsoft.com/windows/wsl/)
[![NVIDIA CUDA](https://img.shields.io/badge/NVIDIA-CUDA-76B900?style=flat-square&logo=nvidia&logoColor=white)](https://developer.nvidia.com/cuda-toolkit)
[![AMD ROCm](https://img.shields.io/badge/AMD-ROCm-ED1C24?style=flat-square&logo=amd&logoColor=white)](https://rocm.docs.amd.com/)
[![PyTorch](https://img.shields.io/badge/PyTorch-Latest-EE4C2C?style=flat-square&logo=pytorch&logoColor=white)](https://pytorch.org/)
[![ComfyUI](https://img.shields.io/badge/ComfyUI-Latest-blueviolet?style=flat-square)](https://github.com/comfy-org/ComfyUI)
[![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](https://opensource.org/licenses/MIT)

A smart, GPU-aware, **one-click Bash installer** for [ComfyUI](https://github.com/comfy-org/ComfyUI) on **native Ubuntu** and **Ubuntu running inside WSL2**.

<img width="1920" height="1080" alt="linux_comfyui installer preview" src="assets/linux_comfyui_preview.png" />

This script automatically detects your platform, GPU vendor, Ubuntu version, and the correct PyTorch GPU wheel channel. It then installs or updates ComfyUI, creates a clean Python virtual environment, installs the matching CUDA or ROCm PyTorch build, and generates reusable launchers.

> **Goal:** one installer for every common Ubuntu ComfyUI setup: native NVIDIA, native AMD, WSL2 NVIDIA, and experimental WSL2 AMD.

---

## ✨ Features

*   **🌍 Universal Linux + WSL2 Installer:** One script supports native Ubuntu and Ubuntu on WSL2.
*   **🧠 Smart GPU Detection:** Automatically detects **NVIDIA/CUDA** or **AMD/ROCm**.
*   **🪟 WSL2-Aware Logic:** Detects WSL and changes GPU installation behavior to avoid breaking Windows-provided GPU passthrough.
*   **🟩 NVIDIA CUDA Support:** Installs the CUDA repository/toolkit and uses the newest usable PyTorch CUDA wheel index.
*   **🟥 AMD ROCm Support:** Installs ROCm packages for native Ubuntu and supports an experimental ROCm-on-WSL path.
*   **🔥 Latest ComfyUI:** Clones or updates the official ComfyUI repository.
*   **⚡ Latest PyTorch:** Dynamically checks available PyTorch wheel indexes and installs the latest matching GPU build.
*   **🧪 GPU Verification:** Runs a PyTorch GPU test after installation and prints CUDA/HIP availability.
*   **🚀 Launch Script Creator:** Creates `~/ComfyUI/run_comfyui.sh`, a `comfyui` terminal command, and a desktop entry.
*   **🔁 Re-Run Safe:** Running the installer again updates an existing ComfyUI Git checkout and refreshes Python packages.
*   **🧩 Override Friendly:** Advanced users can force platform/backend, skip OS GPU packages, change install path, change port, or use nightly PyTorch.

---

## ✅ Support Matrix

| Platform | GPU | Status | Notes |
|---|---:|---:|---|
| **Native Ubuntu** | **NVIDIA** | ✅ Fully supported | Installs CUDA repo/toolkit and Ubuntu-recommended NVIDIA driver if needed. |
| **Native Ubuntu** | **AMD** | ✅ Supported | Installs AMD ROCm packages and adds the user to `render,video`. |
| **WSL2 Ubuntu** | **NVIDIA** | ✅ Fully supported | Uses Windows NVIDIA driver passthrough. Does **not** install Linux NVIDIA display drivers inside WSL. |
| **WSL2 Ubuntu** | **AMD** | ⚠️ Experimental | Requires Windows-side AMD WSL driver support, Windows SDK, WSL2 GPU passthrough, ROCm userspace, and ROCDXG/librocdxg. |

### Automated GPU stack support

The script automates CUDA/ROCm system package setup for:

```text
Ubuntu 22.04 LTS
Ubuntu 24.04 LTS
x86_64 / amd64
```

For other Ubuntu versions, you can still use the script when your GPU stack is already installed:

```bash
INSTALL_SYSTEM_GPU=0 ./install_comfyui_ubuntu_wsl.sh
```

---

## 📦 What Gets Installed

The installer creates a standard ComfyUI layout under your Linux home directory:

```text
~/ComfyUI/
├── .venv/                  # Python virtual environment
├── main.py                 # ComfyUI entry point
├── requirements.txt        # ComfyUI Python requirements
├── run_comfyui.sh          # Generated launcher
├── models/
│   ├── checkpoints/        # Put SD/SDXL/Flux checkpoints here
│   ├── vae/                # VAE models
│   ├── loras/              # LoRA files
│   ├── controlnet/         # ControlNet models
│   └── upscale_models/     # Upscalers
└── custom_nodes/           # Optional ComfyUI custom nodes
```

It also creates:

```text
~/.local/bin/comfyui                         # Terminal shortcut
~/.local/share/applications/comfyui.desktop  # Linux desktop entry
```

---

## 🛠️ Installation Guide - Native Ubuntu

1.  Download the installer:

    [![Download Installer](https://img.shields.io/badge/⬇️%20Download%20Installer---?style=flat-square&logo=linux&logoColor=white)](./install_comfyui_ubuntu_wsl.sh)

2.  Open a terminal in the folder where you downloaded the script.

3.  Make it executable:

    ```bash
    chmod +x install_comfyui_ubuntu_wsl.sh
    ```

4.  Run it as your normal user:

    ```bash
    ./install_comfyui_ubuntu_wsl.sh
    ```

5.  Wait for the installer to finish.

6.  Launch ComfyUI:

    ```bash
    comfyui
    ```

7.  Open the browser:

    ```text
    http://127.0.0.1:8188
    ```

> **Important:** Do not run the installer with `sudo`. The script asks for `sudo` only when it needs to install system packages.

---

## 🪟 Installation Guide - Ubuntu on WSL2

### 1. Open Ubuntu, not PowerShell

Open your installed Ubuntu distribution from the Start Menu, Windows Terminal, or this command:

```powershell
wsl -d Ubuntu
```

### 2. Copy the script into your Linux home folder

If the script is in your Windows Downloads folder, use the WSL path format:

```bash
cp /mnt/c/Users/<YourWindowsUser>/Downloads/install_comfyui_ubuntu_wsl.sh ~/
```

Example:

```bash
cp /mnt/c/Users/mihai/Downloads/install_comfyui_ubuntu_wsl.sh ~/
```

### 3. Run the installer from Linux

```bash
cd ~
sed -i 's/\r$//' install_comfyui_ubuntu_wsl.sh
chmod +x install_comfyui_ubuntu_wsl.sh
./install_comfyui_ubuntu_wsl.sh
```

### 4. Launch ComfyUI

```bash
comfyui
```

Then open this in your Windows browser:

```text
http://127.0.0.1:8188
```

> **Do not run Windows paths directly inside WSL.** This will fail:
>
> ```bash
> C:\Users\mihai\Downloads\install_comfyui_ubuntu_wsl.sh
> ```
>
> Use this instead:
>
> ```bash
> bash /mnt/c/Users/mihai/Downloads/install_comfyui_ubuntu_wsl.sh
> ```

---

## 🎮 How to Use

After installation, start ComfyUI with either launcher:

```bash
~/ComfyUI/run_comfyui.sh
```

or:

```bash
comfyui
```

Default URL:

```text
http://127.0.0.1:8188
```

### Listen on LAN

To access ComfyUI from another device on your network:

```bash
COMFYUI_HOST=0.0.0.0 comfyui
```

Then open:

```text
http://<your-linux-ip>:8188
```

### Change the port

```bash
COMFYUI_PORT=8190 comfyui
```

### Pass extra ComfyUI arguments

Any extra argument is forwarded to `python main.py`:

```bash
comfyui --lowvram
comfyui --cpu
comfyui --disable-auto-launch
```

---

## 🧠 Automatic Detection Flow

The installer follows this decision tree:

```text
Start
├── Confirm Ubuntu
├── Detect platform
│   ├── Native Ubuntu
│   └── WSL2 Ubuntu
├── Detect GPU backend
│   ├── NVIDIA → CUDA
│   └── AMD    → ROCm
├── Install base packages
├── Install system GPU packages unless INSTALL_SYSTEM_GPU=0
│   ├── Native NVIDIA → CUDA repo + toolkit + optional Ubuntu driver
│   ├── WSL2 NVIDIA   → CUDA WSL repo + toolkit only
│   ├── Native AMD    → AMDGPU repo + amdgpu-dkms + ROCm
│   └── WSL2 AMD      → ROCm userspace + ROCDXG/librocdxg
├── Clone or update ComfyUI
├── Create Python venv
├── Install latest matching PyTorch
├── Install ComfyUI requirements
├── Create launchers
└── Verify torch GPU access
```

---

## 🧩 Advanced Options

Use environment variables before the script name to override behavior.

### Force GPU backend

```bash
COMFYUI_BACKEND=cuda ./install_comfyui_ubuntu_wsl.sh
COMFYUI_BACKEND=rocm ./install_comfyui_ubuntu_wsl.sh
```

Supported values:

```text
auto
cuda
rocm
nvidia  # alias for cuda
amd     # alias for rocm
```

### Skip system GPU package installation

Use this if CUDA/ROCm is already installed or you only want the ComfyUI/PyTorch environment:

```bash
INSTALL_SYSTEM_GPU=0 ./install_comfyui_ubuntu_wsl.sh
```

### Install into a custom folder

```bash
COMFYUI_DIR=$HOME/AI/ComfyUI ./install_comfyui_ubuntu_wsl.sh
```

### Use a custom virtual environment path

```bash
COMFYUI_VENV=$HOME/AI/venvs/comfyui ./install_comfyui_ubuntu_wsl.sh
```

### Use nightly PyTorch

```bash
PYTORCH_CHANNEL=nightly ./install_comfyui_ubuntu_wsl.sh
```

### Change default host and port

```bash
COMFYUI_HOST=0.0.0.0 COMFYUI_PORT=8188 ./install_comfyui_ubuntu_wsl.sh
```

### Skip WSL host GPU checks

```bash
WSL_SKIP_HOST_GPU_CHECK=1 ./install_comfyui_ubuntu_wsl.sh
```

### Skip ROCDXG auto-build on AMD WSL2

```bash
ROCDXG_AUTO_BUILD=0 COMFYUI_BACKEND=rocm ./install_comfyui_ubuntu_wsl.sh
```

### Set the Windows SDK path manually for AMD WSL2

```bash
WIN_SDK_INCLUDE="/mnt/c/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0" COMFYUI_BACKEND=rocm ./install_comfyui_ubuntu_wsl.sh
```

---

## 🟩 NVIDIA Notes

### Native Ubuntu NVIDIA

The script will:

* add the NVIDIA CUDA repository;
* install the newest available CUDA toolkit package;
* check `nvidia-smi`;
* use `ubuntu-drivers install` if no working NVIDIA driver is detected;
* install PyTorch from the newest working CUDA wheel index.

After a new NVIDIA driver install, reboot if PyTorch cannot see the GPU:

```bash
sudo reboot
```

### WSL2 NVIDIA

The script will:

* detect WSL2;
* use the CUDA WSL repository path;
* install CUDA toolkit packages only;
* avoid Linux NVIDIA display driver installation;
* use the Windows NVIDIA driver exposed into WSL.

If CUDA is not visible inside WSL:

```powershell
wsl --update
wsl --shutdown
```

Then reopen Ubuntu and test:

```bash
nvidia-smi
comfyui
```

---

## 🟥 AMD Notes

### Native Ubuntu AMD

The script will:

* detect AMD/Radeon hardware;
* add the AMD ROCm repository;
* install `amdgpu-dkms` and `rocm`;
* add your user to the `render` and `video` groups;
* install PyTorch from the newest working ROCm wheel index.

After install, log out and back in, or reboot:

```bash
sudo reboot
```

### WSL2 AMD - Experimental

AMD ROCm on WSL2 is more sensitive than NVIDIA CUDA on WSL2. Before running the installer, make sure Windows has:

* a supported Radeon GPU;
* AMD Adrenalin driver with WSL2 support;
* WSL2 enabled and updated;
* Ubuntu 22.04 or 24.04 under WSL2;
* Windows SDK installed.

The script will:

* install ROCm user-space packages;
* avoid `amdgpu-dkms` inside WSL;
* try to build and install `librocdxg`;
* export `HSA_ENABLE_DXG_DETECTION=1` for ComfyUI launch.

Check WSL GPU passthrough:

```bash
ls -l /dev/dxg
```

If `/dev/dxg` is missing, update WSL and restart it from Windows:

```powershell
wsl --update
wsl --shutdown
```

---

## 🧪 Verify the Install

The installer runs a PyTorch verification step automatically. You can run it manually:

```bash
~/ComfyUI/.venv/bin/python - <<'PY'
import torch
print("torch:", torch.__version__)
print("cuda:", torch.version.cuda)
print("hip:", torch.version.hip)
print("gpu available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("device:", torch.cuda.get_device_name(0))
PY
```

Expected result for GPU acceleration:

```text
gpu available: True
```

---

## 📁 Model Locations

Put your models here:

| Model Type | Folder |
|---|---|
| Checkpoints | `~/ComfyUI/models/checkpoints/` |
| VAE | `~/ComfyUI/models/vae/` |
| LoRA | `~/ComfyUI/models/loras/` |
| ControlNet | `~/ComfyUI/models/controlnet/` |
| Upscalers | `~/ComfyUI/models/upscale_models/` |
| CLIP | `~/ComfyUI/models/clip/` |
| CLIP Vision | `~/ComfyUI/models/clip_vision/` |
| Diffusion models | `~/ComfyUI/models/diffusion_models/` |
| Text encoders | `~/ComfyUI/models/text_encoders/` |
| UNet | `~/ComfyUI/models/unet/` |

Example:

```bash
mkdir -p ~/ComfyUI/models/checkpoints
cp /path/to/model.safetensors ~/ComfyUI/models/checkpoints/
```

---

## 🔄 Updating ComfyUI

Run the installer again:

```bash
./install_comfyui_ubuntu_wsl.sh
```

If `~/ComfyUI` is already a Git checkout, the script will run:

```text
git pull --ff-only
pip install --upgrade torch torchvision torchaudio
pip install --upgrade -r requirements.txt
```

You can also update manually:

```bash
cd ~/ComfyUI
git pull --ff-only
source .venv/bin/activate
python -m pip install --upgrade -r requirements.txt
```

---

## 🧹 Uninstall

Remove ComfyUI and the terminal shortcut:

```bash
rm -rf ~/ComfyUI
rm -f ~/.local/bin/comfyui
rm -f ~/.local/share/applications/comfyui.desktop
```

This does **not** remove system-level CUDA, ROCm, NVIDIA driver, or AMD driver packages.

---

## 🛟 Troubleshooting

### `C:Users... command not found`

You are trying to run a Windows path inside WSL. Use `/mnt/c/...` instead.

Wrong:

```bash
C:\Users\mihai\Downloads\install_comfyui_ubuntu_wsl.sh
```

Correct:

```bash
bash /mnt/c/Users/mihai/Downloads/install_comfyui_ubuntu_wsl.sh
```

Recommended:

```bash
cp /mnt/c/Users/mihai/Downloads/install_comfyui_ubuntu_wsl.sh ~/
cd ~
chmod +x install_comfyui_ubuntu_wsl.sh
./install_comfyui_ubuntu_wsl.sh
```

### `$'\r': command not found`

The script has Windows line endings. Fix them:

```bash
sed -i 's/\r$//' install_comfyui_ubuntu_wsl.sh
```

### `Run this script as your normal user, not with sudo`

Run it without `sudo`:

```bash
./install_comfyui_ubuntu_wsl.sh
```

The script will request sudo only for APT/system packages.

### `No NVIDIA or AMD GPU detected`

Force the backend:

```bash
COMFYUI_BACKEND=cuda ./install_comfyui_ubuntu_wsl.sh
```

or:

```bash
COMFYUI_BACKEND=rocm ./install_comfyui_ubuntu_wsl.sh
```

### `PyTorch installed, but GPU is not available`

Common fixes:

* **Native NVIDIA:** reboot after driver installation.
* **Native AMD:** log out/in or reboot after group membership changes.
* **WSL2 NVIDIA:** update Windows NVIDIA driver, run `wsl --update`, then `wsl --shutdown`.
* **WSL2 AMD:** confirm `/dev/dxg`, Windows SDK, AMD WSL driver support, and `librocdxg` installation.

### Ubuntu version not supported for GPU stack setup

Automated CUDA/ROCm system package setup targets Ubuntu 22.04 and 24.04. If you already installed CUDA or ROCm manually:

```bash
INSTALL_SYSTEM_GPU=0 ./install_comfyui_ubuntu_wsl.sh
```

---

## 📖 Project Lineage & History

Understanding the pieces can be confusing. This installer connects several projects into one setup flow:

* 🟢 **[ComfyUI]**<br>
  A powerful, node-based interface for Stable Diffusion, Flux, SDXL, video workflows, upscaling, ControlNet, LoRA, and custom pipelines.

* 🟩 **[NVIDIA CUDA]**<br>
  The GPU compute stack used for NVIDIA acceleration on native Ubuntu and WSL2.

* 🟥 **[AMD ROCm]**<br>
  The GPU compute stack used for AMD acceleration on native Ubuntu and, experimentally, WSL2.

* 🟠 **[PyTorch]**<br>
  The machine learning framework used by ComfyUI. This installer selects a CUDA or ROCm wheel index automatically.

* 🔵 **[linux_comfyui]**<br>
  This one-click installer that brings the OS GPU runtime, PyTorch environment, ComfyUI checkout, and launch scripts together.

---

## 🤝 Credits

*   **ComfyUI:** Official project by the [ComfyUI team](https://github.com/comfy-org/ComfyUI).
*   **PyTorch:** GPU-enabled Python packages by the [PyTorch team](https://pytorch.org/).
*   **NVIDIA CUDA:** CUDA toolkit and WSL support by [NVIDIA](https://developer.nvidia.com/cuda-toolkit).
*   **AMD ROCm:** ROCm Linux and WSL support by [AMD](https://rocm.docs.amd.com/).
*   **Ubuntu:** Linux distribution by [Canonical](https://ubuntu.com/).
*   **WSL2:** Windows Subsystem for Linux by [Microsoft](https://learn.microsoft.com/windows/wsl/).
*   **Bash:** Shell environment used to automate the installer.

---

## ⚠️ Disclaimer

This installer modifies system packages when `INSTALL_SYSTEM_GPU=1`. Review the script before running it, especially on production machines. GPU drivers, CUDA, ROCm, WSL, and PyTorch change frequently, so re-running the installer may pull newer packages than a previous install.

---

*If this saves you time, give the repository a star! ⭐*
