    Get the patch and repo


git clone https://github.com/vogar345/Bc250-radeon-patch.git ~/bc250-toolkit
cd ~/bc250-toolkit

(Adjust if you already have this cloned elsewhere—e.g., ~/Downloads/Bc250-radeon-patch-main).


    Install build dependencies


sudo pacman -S ninja python-mako python-yaml


    Run the builder script up through the Mesa clone


bash build-bc250-mesa.sh

Let it clone Mesa (tag mesa-26.1.4) and reach the patch step. If it fails to apply the patch with git apply errors ("patch does not apply"), apply it manually in the next step.


    Apply the patch manually with fuzzy matching


cd ~/bc250-mesa-build/mesa
patch -p1 --fuzz 5 -i ~/Downloads/bc250_mesa_fix.patch

You should see:

    patching file src/amd/common/ac_gpu_info.c
    patching file src/amd/vulkan/radv_physical_device.c
    patching file src/amd/vulkan/radv_query.c


with no rejected hunk errors.


    Build


cd ~/bc250-mesa-build/mesa
rm -rf build
VENV="$HOME/bc250-mesa-build/venv"
PYTHONPATH="$VENV/lib/python3./site-packages" "$VENV/bin/meson" setup build \
  -Dvulkan-drivers=amd -Dgallium-drivers=zink \
  -Dglx=disabled -Degl=disabled -Dgles2=disabled \
  -Dshared-llvm=disabled -Dllvm=disabled \
  -Dxmlconfig=disabled -Dlmsensors=disabled -Dvalgrind=disabled

PYTHONPATH="$VENV/lib/python3./site-packages" ninja -C build src/amd/vulkan/libvulkan_radeon.so


    Install the driver


sudo cp build/src/amd/vulkan/libvulkan_radeon.so /usr/lib/libvulkan_radeon_modded.so


    Create the Vulkan ICD file


cat > ~/radeon_modded_icd.x86_64.json << 'EOF'
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "/usr/lib/libvulkan_radeon_modded.so",
        "api_version": "1.4.309"
    }
}
EOF


    Sanity check


VK_ICD_FILENAMES=~/radeon_modded_icd.x86_64.json vulkaninfo | head -30


    Steam launch options


RADV_DEBUG=nocompute VK_ICD_FILENAMES=/home/deck/radeon_modded_icd.x86_64.json %command%
