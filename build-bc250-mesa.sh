#!/bin/bash
set -e

MESA_VER="mesa-26.1.4"
BUILD_DIR="$HOME/bc250-mesa-build"
DRIVER_NAME="libvulkan_radeon_modded.so"
ICD_JSON="$HOME/radeon_modded_icd.x86_64.json"

echo "=== BC250 Mesa Driver Builder ==="
echo ""

# --- check for basic tools ---
for cmd in git curl python3; do
    command -v $cmd >/dev/null 2>&1 || { echo "ERROR: $cmd is required. Install it first."; exit 1; }
done

mkdir -p "$BUILD_DIR"

# --- setup venv with meson+mako+pyyaml ---
VENV="$BUILD_DIR/venv"
if [ ! -f "$VENV/bin/meson" ]; then
    echo "[1/6] Setting up build tools..."
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q meson mako pyyaml
fi

# --- install ninja if missing ---
if ! command -v ninja >/dev/null 2>&1; then
    echo "   Installing ninja..."
    curl -sSL -o "$BUILD_DIR/ninja.zip" https://github.com/ninja-build/ninja/releases/download/v1.12.1/ninja-linux.zip
    unzip -oq "$BUILD_DIR/ninja.zip" -d "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/ninja"
    export PATH="$HOME/.local/bin:$PATH"
fi

# --- clone mesa ---
if [ ! -d "$BUILD_DIR/mesa" ]; then
    echo "[2/6] Cloning Mesa $MESA_VER..."
    git clone --depth 1 --branch "$MESA_VER" https://gitlab.freedesktop.org/mesa/mesa.git "$BUILD_DIR/mesa"
else
    echo "[2/6] Mesa already cloned, skipping."
fi

# --- apply patch ---
echo "[3/6] Applying BC250 patch..."
cd "$BUILD_DIR/mesa"
git checkout -- . 2>/dev/null || true

# Inline patch (same as bc250_mesa_fix.patch)
cat > /tmp/bc250_mesa_fix.patch << 'PATCH_EOF'
diff --git a/src/amd/common/ac_gpu_info.c b/src/amd/common/ac_gpu_info.c
index 68b63a7..7f850b7 100644
--- a/src/amd/common/ac_gpu_info.c
+++ b/src/amd/common/ac_gpu_info.c
@@ -447,10 +447,6 @@ ac_fill_hw_ip_info(struct radeon_info *info, const struct drm_amdgpu_info_device
         */
        info->ip[ip_type].num_queues = 1;
     } else if (ip_info->available_rings) {
-      /* GFX1013 is known to have broken compute queue */
-      if (ip_type == AMD_IP_COMPUTE && device_info->family == FAMILY_NV &&
-          ASICREV_IS(device_info->external_rev, GFX1013))
-         return false;
 
        info->ip[ip_type].num_queues = util_bitcount(ip_info->available_rings);
     } else {
@@ -730,6 +726,9 @@ ac_identify_chip(struct radeon_info *info, const struct drm_amdgpu_info_device *
        return false;
     }
 
+   if (info->family == CHIP_GFX1013)
+      info->gfx_level = GFX10_3;
+
 
 #define VCN_IP_VERSION(mj, mn, rv) (((mj) << 16) | ((mn) << 8) | (rv))
 
diff --git a/src/amd/vulkan/radv_physical_device.c b/src/amd/vulkan/radv_physical_device.c
index cdab81e..4972f68 100644
--- a/src/amd/vulkan/radv_physical_device.c
+++ b/src/amd/vulkan/radv_physical_device.c
@@ -70,7 +70,9 @@ radv_taskmesh_enabled(const struct radv_physical_device *pdev)
     if (instance->debug_flags & RADV_DEBUG_NO_MESH_SHADER)
        return false;
 
-   return pdev->use_ngg && !pdev->use_llvm && pdev->info.gfx_level >= GFX10_3 && radv_compute_queue_enabled(pdev);
+   return pdev->use_ngg && !pdev->use_llvm &&
+          (pdev->info.gfx_level >= GFX10_3 || pdev->info.family == CHIP_GFX1013) &&
+          (radv_compute_queue_enabled(pdev) || pdev->info.family == CHIP_GFX1013);
 }
 
 bool
@@ -2554,7 +2556,7 @@ radv_physical_device_try_create(struct radv_instance *instance, drmDevicePtr drm
 
     pdev->emulate_ngg_gs_query_pipeline_stat = pdev->use_ngg && pdev->info.gfx_level < GFX11;
 
-   pdev->emulate_mesh_shader_queries = pdev->info.gfx_level == GFX10_3;
+   pdev->emulate_mesh_shader_queries = pdev->info.gfx_level == GFX10_3 || pdev->info.family == CHIP_GFX1013;
 
     /* Determine the number of threads per wave for all stages. */
     pdev->cs_wave_size = 64;
diff --git a/src/amd/vulkan/radv_query.c b/src/amd/vulkan/radv_query.c
index 5308ba8..05bc587 100644
--- a/src/amd/vulkan/radv_query.c
+++ b/src/amd/vulkan/radv_query.c
@@ -410,7 +410,7 @@ radv_get_pipelinestat_query_size(struct radv_device *device)
      * invocations, it's easier to use the same size as GFX11.
      */
     const struct radv_physical_device *pdev = radv_device_physical(device);
-   unsigned num_results = pdev->info.gfx_level >= GFX10_3 ? 14 : 11;
+   unsigned num_results = pdev->info.gfx_level >= GFX10_3 || pdev->info.family == CHIP_GFX1013 ? 14 : 11;
     return num_results * 8;
 }
 
PATCH_EOF

git apply /tmp/bc250_mesa_fix.patch
echo "   Patch applied."

# --- configure ---
echo "[4/6] Configuring build..."
rm -rf "$BUILD_DIR/mesa/build"
PYTHONPATH="$VENV/lib/python3"*/site-packages "$VENV/bin/meson" setup "$BUILD_DIR/mesa/build" \
    -Dvulkan-drivers=amd \
    -Dgallium-drivers=zink \
    -Dglx=disabled -Degl=disabled -Dgles2=disabled \
    -Dshared-llvm=disabled -Dllvm=disabled \
    -Dxmlconfig=disabled -Dlmsensors=disabled -Dvalgrind=disabled

# --- build ---
echo "[5/6] Building driver (this takes a while)..."
PYTHONPATH="$VENV/lib/python3"*/site-packages ninja -C "$BUILD_DIR/mesa/build" src/amd/vulkan/libvulkan_radeon.so

# --- install ---
echo "[6/6] Installing..."
sudo cp "$BUILD_DIR/mesa/build/src/amd/vulkan/libvulkan_radeon.so" "/usr/lib/$DRIVER_NAME"

cat > "$ICD_JSON" << EOF
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "/usr/lib/$DRIVER_NAME",
        "api_version": "1.4.309"
    }
}
EOF

echo ""
echo "=== Done! ==="
echo "Driver installed: /usr/lib/$DRIVER_NAME"
echo "ICD JSON: $ICD_JSON"
echo ""
echo "Steam launch option:"
echo "  VK_ICD_FILENAMES=$ICD_JSON %command%"
