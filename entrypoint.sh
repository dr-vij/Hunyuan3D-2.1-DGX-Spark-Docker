#!/bin/bash
set -e

echo "=== Hunyuan3D-2.1-DGX Entrypoint ==="

# Check if project files exist
if [ ! -f "/workspace/Hunyuan3D-2.1-DGX/gradio_app.py" ]; then
    echo "ERROR: Project files not found in /workspace/Hunyuan3D-2.1-DGX"
    echo "Please ensure you have cloned the repository to ./Hunyuan3D-2.1-DGX on the host"
    exit 1
fi

cd /workspace/Hunyuan3D-2.1-DGX

# Check and install requirements if needed
if [ -f "requirements.txt" ]; then
    echo "Checking Python dependencies..."
    pip install -r requirements.txt --no-cache-dir || true
fi

# Build custom_rasterizer if not already built
if [ -d "hy3dpaint/custom_rasterizer" ]; then
    if [ ! -f "hy3dpaint/custom_rasterizer/.built" ]; then
        echo "Building custom_rasterizer..."
        cd hy3dpaint/custom_rasterizer
        pip install -e . --no-build-isolation
        touch .built
        cd /workspace/Hunyuan3D-2.1-DGX
    else
        echo "custom_rasterizer already built, skipping..."
    fi
fi

# Compile DifferentiableRenderer if not already compiled
if [ -d "hy3dpaint/DifferentiableRenderer" ]; then
    if [ ! -f "hy3dpaint/DifferentiableRenderer/.built" ]; then
        echo "Compiling DifferentiableRenderer..."
        cd hy3dpaint/DifferentiableRenderer
        bash compile_mesh_painter.sh
        touch .built
        cd /workspace/Hunyuan3D-2.1-DGX
    else
        echo "DifferentiableRenderer already compiled, skipping..."
    fi
fi

# Download ESRGAN weights if not present
if [ ! -f "hy3dpaint/ckpt/RealESRGAN_x4plus.pth" ]; then
    echo "Downloading ESRGAN weights..."
    mkdir -p hy3dpaint/ckpt
    wget https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth -P hy3dpaint/ckpt
else
    echo "ESRGAN weights already present, skipping..."
fi

echo "=== Starting Gradio application ==="
exec python gradio_app.py --host 0.0.0.0 --port 7860
