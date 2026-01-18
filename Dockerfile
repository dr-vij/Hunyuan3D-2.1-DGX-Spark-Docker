FROM nvcr.io/nvidia/cuda:13.0.2-devel-ubuntu24.04
ARG DEBIAN_FRONTEND=noninteractive

# PYTHON SETUP
## 1) Install build dependencies for Python 3.10.19 and helper utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates curl wget build-essential \
    libssl-dev zlib1g-dev libbz2-dev libsqlite3-dev libffi-dev liblzma-dev \
    && rm -rf /var/lib/apt/lists/* 

## 2) OpenGL/X11 libraries required for pymesh3d (PLY) and headless rendering
# Note: For arm64 (aarch64) Ubuntu/Debian, package names are the same.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libopengl0 \
    libgl1 \
    libglx0 \
    libglu1-mesa \
    libx11-6 \
    libxext6 \
    libxrender1 \
    libxi6 \
    libxxf86vm1 \
    libxfixes3 \
    libxkbcommon0 \
    libxcb1 \
    && rm -rf /var/lib/apt/lists/*
ENV QT_QPA_PLATFORM=offscreen

## 3) Build and install Python 3.10.19 from source (altinstall -> /usr/local/bin/python3.10)
# Reason: Blender build and Hunyuan3D 2.1 target Python 3.10.
RUN set -eux; \
    cd /opt; \
    wget https://www.python.org/ftp/python/3.10.19/Python-3.10.19.tgz; \
    tar -xvf Python-3.10.19.tgz; \
    cd Python-3.10.19; \
    ./configure --enable-optimizations; \
    make -j"$(nproc)"; \
    make altinstall; \
    /usr/local/bin/python3.10 --version; \
    cd /; \
    rm -rf /opt/Python-3.10.19 /opt/Python-3.10.19.tgz 

## 4) Install NumPy (required to build Blender/bpy)
RUN /usr/local/bin/python3.10 -m pip install --no-cache-dir numpy

## 5) Create a virtual environment and upgrade pip/setuptools/wheel
RUN /usr/local/bin/python3.10 -m venv /opt/py310 \
    && /opt/py310/bin/python -m ensurepip --upgrade \
    && /opt/py310/bin/python -m pip install --upgrade pip setuptools wheel

## 6) Use the virtual environment (/opt/py310) by default
ENV PATH="/opt/py310/bin:${PATH}"

# BLENDER BUILD
## 1) Install packages for building Blender and its dependencies
RUN rm -rf /var/lib/apt/lists/* \
 && apt-get update -o Acquire::Retries=5 -o Acquire::http::No-Cache=true \
 && apt-get -y upgrade \
 && apt-get install -y --no-install-recommends \
    cmake autoconf automake bison libtool yasm tcl ninja-build meson patchelf \
    libopenal-dev libsndfile1-dev libjack-dev libpulse-dev \
    libjpeg-dev libpng-dev libtiff-dev libopenexr-dev \
    libepoxy-dev libfreetype6-dev \
    libopenimageio-dev libboost-all-dev \
    pkg-config libpugixml-dev libfftw3-dev \
    libembree-dev libvulkan-dev libshaderc-dev \
    libglib2.0-dev libcurl4-openssl-dev \
    subversion \
 && rm -rf /var/lib/apt/lists/*

## 2) Install NumPy in the current venv (headers required to build bpy)
RUN pip install --no-cache-dir numpy

## 3) Clone Blender 4.0.2 and initialize submodules
RUN mkdir -p /workspace/blender_dev \
    && cd /workspace/blender_dev \
    && git clone https://projects.blender.org/blender/blender.git \
    && cd blender \
    && git fetch --all --tags \
    && git checkout v4.0.2 \
    && git submodule update --init --recursive

## 4) Build bpy (headless) using Python 3.10 from the venv
## Debug tip: verbose output is enabled; for troubleshooting, rebuild with make -j1 to surface the first real error.
RUN mkdir -p /workspace/blender_dev/build_bpy \
    && cd /workspace/blender_dev/build_bpy \
    && cmake ../blender \
      -DWITH_PYTHON_MODULE=ON \
      -DWITH_PYTHON_INSTALL=OFF \
      -DWITH_HEADLESS=ON \
      -DWITH_OPENAL=OFF \
      -DWITH_LIBS_PRECOMPILED=OFF \
      -DWITH_SYSTEM_GLIB=ON \
      -DWITH_SYSTEM_CURL=ON \
      -DPYTHON_EXECUTABLE=/opt/py310/bin/python \
      -DCMAKE_VERBOSE_MAKEFILE=ON \
      -DCMAKE_BUILD_TYPE=Release \
    && make -j"$(nproc)"

## 5) Make bpy available in all container sessions
ENV BLENDER_SYSTEM_SCRIPTS="/workspace/blender_dev/blender/scripts"
ENV BLENDER_SYSTEM_DATAFILES="/workspace/blender_dev/blender/release/datafiles"
ENV PYTHONPATH="${PYTHONPATH}:/workspace/blender_dev/build_bpy/bin"

# END OF BLENDER BUILD

# PROJECT SETUP AND BUILD

## 1) Install Python dependencies (PyTorch CUDA 13.0 build first)
RUN pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu130

## 2) Speed up model downloads (Hugging Face with xet)
RUN pip install --no-cache-dir -U "huggingface_hub[hf_xet]"

## 3) Ensure python3-config symlink in the venv (required for custom_rasterizer/DifferentiableRenderer)
# Create/update: /opt/py310/bin/python3-config -> /usr/local/bin/python3.10-config
RUN ln -sf /usr/local/bin/python3.10-config /opt/py310/bin/python3-config

# requirements from hunyuan.
RUN pip install --no-cache-dir \
    --extra-index-url https://mirrors.cloud.tencent.com/pypi/simple/ \
    --extra-index-url https://mirrors.aliyun.com/pypi/simple \
    ninja==1.11.1.1 \
    pybind11==2.13.4 \
    transformers==4.46.0 \
    diffusers==0.30.0 \
    accelerate==1.1.1 \
    pytorch-lightning==1.9.5 \
    huggingface-hub==0.30.2 \
    safetensors==0.4.4 \
    numpy==1.24.4 \
    scipy==1.14.1 \
    einops==0.8.0 \
    pandas==2.2.2 \
    opencv-python==4.10.0.84 \
    imageio==2.36.0 \
    scikit-image==0.24.0 \
    rembg==2.0.65 \
    realesrgan==0.3.0 \
    tb_nightly==2.18.0a20240726 \
    basicsr==1.4.2 \
    trimesh==4.4.7 \
    pymeshlab \
    pygltflib==1.16.3 \
    xatlas \
    open3d==0.18.0 \
    omegaconf==2.3.0 \
    pyyaml==6.0.2 \
    configargparse==1.7 \
    gradio==5.33.0 \
    fastapi==0.115.12 \
    uvicorn==0.34.3 \
    tqdm==4.66.5 \
    psutil==6.0.0 \
    cupy-cuda12x==13.4.1 \
    onnxruntime==1.16.3 \
    torchmetrics==1.6.0 \
    pydantic==2.10.6 \
    timm \
    pythreejs \
    torchdiffeq \
    deepspeed
# end of requirements.

## 4) Set CUDA environment (adjust CUDA version and arch as needed)
# DGX Spark uses CUDA 13.0 and arch "12.1+PTX".
ENV CUDA_HOME=/usr/local/cuda-13.0
ENV PATH="$CUDA_HOME/bin:${PATH}"
ENV LD_LIBRARY_PATH="$CUDA_HOME/lib64:$CUDA_HOME/targets/sbsa-linux/lib:/usr/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH}"
ENV TORCH_CUDA_ARCH_LIST="12.1+PTX"

ARG ENTRYPOINT_REV=2

## 5) Set working directory (project will be mounted as volume)
WORKDIR /workspace/Hunyuan3D-2.1-DGX

## 7) Copy and set up entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

## 2) Use entrypoint script to initialize and start the application
ENTRYPOINT ["/entrypoint.sh"]

# I spent 8+ hours setting this up, with help from Google Search and JetBrains Junie
LABEL authors="dr-vij (Viktor Grigorev)"