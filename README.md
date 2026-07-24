# FF7 Rebirth on AMD BC-250 (CachyOS)

A guide for getting **Final Fantasy VII Rebirth** fully functional on the **AMD BC-250** APU running **CachyOS** using a custom patched Mesa/RADV Vulkan driver.

> **Credits:** Special thanks to **Vogar345** for the original fix and tweaks!

---

## ⚠️ Important
**Make sure to set the Steam Launch Options** at the bottom of this guide after completing the build steps, or the game will not use the modified driver.

---

## 🛠️ Step-by-Step Setup

### 1. Clone the Repository
Clone the toolkit repository (or navigate to it if you already downloaded it):

```bash
git clone [https://github.com/lonewolf0622/FF7BC250.git](https://github.com/lonewolf0622/FF7BC250.git) ~/bc250-toolkit
cd ~/bc250-toolkit
```
> **Note:** If you already downloaded this to a different location (e.g., `~/Downloads/Bc250-radeon-patch-main`), adjust your directory path accordingly.

---

### 2. Install Build Dependencies
Install the required dependencies via Arch/CachyOS package manager:

```bash
sudo pacman -S ninja python-mako python-yaml
```

---

### 3. Run the Mesa Builder Script
Start the build script to clone Mesa:

```bash
bash build-bc250-mesa.sh
```

Let the script clone Mesa (tag `mesa-26.1.4`) until it reaches the patch step. If it fails to apply the patch automatically (`patch does not apply`), proceed to apply it manually in the next step.

---

### 4. Apply the Patch Manually
Apply the patch manually using fuzzy matching:

```bash
cd ~/bc250-mesa-build/mesa
patch -p1 --fuzz 5 -i ~/Downloads/bc250_mesa_fix.patch
```

**Expected output:**
```text
patching file src/amd/common/ac_gpu_info.c
patching file src/amd/vulkan/radv_physical_device.c
patching file src/amd/vulkan/radv_query.c
```
*(Verify there are no `.rej` / rejected hunk errors before continuing.)*

---

### 5. Build the Driver
Clean up any old build files and compile `libvulkan_radeon.so`:

```bash
cd ~/bc250-mesa-build/mesa
rm -rf build

VENV="$HOME/bc250-mesa-build/venv"
PYTHONPATH="$VENV/lib/python3./site-packages" "$VENV/bin/meson" setup build \
  -Dvulkan-drivers=amd -Dgallium-drivers=zink \
  -Dglx=disabled -Degl=disabled -Dgles2=disabled \
  -Dshared-llvm=disabled -Dllvm=disabled \
  -Dxmlconfig=disabled -Dlmsensors=disabled -Dvalgrind=disabled

PYTHONPATH="$VENV/lib/python3./site-packages" ninja -C build src/amd/vulkan/libvulkan_radeon.so
```

---

### 6. Install the Modded Driver
Copy the built library to your system's library folder:

```bash
sudo cp build/src/amd/vulkan/libvulkan_radeon.so /usr/lib/libvulkan_radeon_modded.so
```

---

### 7. Create the Vulkan ICD File
Create a custom ICD manifest pointing to your modded Vulkan library:

```bash
cat > ~/radeon_modded_icd.x86_64.json << 'EOF'
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "/usr/lib/libvulkan_radeon_modded.so",
        "api_version": "1.4.309"
    }
}
EOF
```

---

### 8. Sanity Check
Verify that Vulkan info can read the newly generated ICD file:

```bash
VK_ICD_FILENAMES=~/radeon_modded_icd.x86_64.json vulkaninfo | head -30
```

---

## 🎮 Steam Launch Options

Right-click **Final Fantasy VII Rebirth** in Steam → **Properties** → **General** → **Launch Options**, and paste:

```bash
VK_ICD_FILENAMES=/home/YOUR_USERNAME/radeon_modded_icd.x86_64.json %command%
```

> ⚠️ Replace `YOUR_USERNAME` in the path above with your actual system username (e.g., `/home/deck/...` if using a Steam Deck profile).
