FROM nvcr.io/nvidia/cuda:13.0.1-devel-ubuntu24.04
ARG DEBIAN_FRONTEND=noninteractive

# 1. Install dependencies to build Python 3.10.19 from source and helper utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates curl wget build-essential \
    libssl-dev zlib1g-dev libbz2-dev libsqlite3-dev libffi-dev liblzma-dev \
    && rm -rf /var/lib/apt/lists/* 

# The base image must be arm64 (aarch64). For Ubuntu/Debian, package names are the same on ARM.
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

# 2. Build and install Python 3.10.19 from source (altinstall -> /usr/local/bin/python3.10)
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

RUN /usr/local/bin/python3.10 -m pip install --no-cache-dir numpy

# 3. Create a venv based on the built Python and upgrade pip/setuptools/wheel
RUN /usr/local/bin/python3.10 -m venv /opt/py310 \
    && /opt/py310/bin/python -m ensurepip --upgrade \
    && /opt/py310/bin/python -m pip install --upgrade pip setuptools wheel

# 4. Use venv (/opt/py310) by default
ENV PATH="/opt/py310/bin:${PATH}"

# 5. Clone repo
RUN git clone -b DGX-Spark https://github.com/dr-vij/Hunyuan3D-2.1-DGX /workspace/Hunyuan3D-2.1
WORKDIR /workspace/Hunyuan3D-2.1

# 6. Install Python dependencies (PyTorch CUDA 13.0 build first, then project requirements)
RUN pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu130

# BLENDER BUILD
## 1) Packages for building Blender and its dependencies
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

## 2) NumPy in the current venv (NumPy headers are required to build bpy)
RUN pip install --no-cache-dir numpy

## 3) Clone Blender 4.0.2 and initialize submodules and external libs (svn)
RUN mkdir -p /workspace/blender_dev \
    && cd /workspace/blender_dev \
    && git clone https://projects.blender.org/blender/blender.git \
    && cd blender \
    && git fetch --all --tags \
    && git checkout v4.0.2 \
    && git submodule update --init --recursive

## 4) Build bpy (headless) using Python 3.10 from the venv
#   Debug tweak: force verbose single-threaded build to reveal the first real error.
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

RUN pip install -r requirements.txt

# IMPORTANT: before building the inpainter, a local python3-config symlink is needed inside our venv,
# otherwise building custom_rasterizer/DifferentiableRenderer fails.
# Create/update the symlink /opt/py310/bin/python3-config -> /usr/local/bin/python3.10-config
RUN ln -sf /usr/local/bin/python3.10-config /opt/py310/bin/python3-config

ENV CUDA_HOME=/usr/local/cuda-13.0
ENV PATH="$CUDA_HOME/bin:${PATH}"
ENV LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH}"
ENV TORCH_CUDA_ARCH_LIST="12.1+PTX"

# 6. Build and install hy3dpaint custom rasterizer and compile differentiable renderer
RUN bash -lc "cd hy3dpaint/custom_rasterizer && pip install -e . --no-build-isolation"
RUN bash -lc "cd hy3dpaint/DifferentiableRenderer && bash compile_mesh_painter.sh"

# 7. Download ESRGAN weights
RUN mkdir -p hy3dpaint/ckpt \
    && wget https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth -P hy3dpaint/ckpt

# Expose port for Gradio UI
EXPOSE 7860

# Start the Gradio application on container startup
# Assumes gradio_app.py is located at /workspace/Hunyuan3D-2.1
# LD_PRELOAD added for correct dependency loading on aarch64
CMD bash -lc "cd /workspace/Hunyuan3D-2.1 && \
  LD_PRELOAD=\"/usr/lib/aarch64-linux-gnu/libgobject-2.0.so.0:/usr/lib/aarch64-linux-gnu/libcurl.so.4:/usr/lib/aarch64-linux-gnu/libnghttp2.so.14\" \
  python gradio_app.py --host 0.0.0.0 --port 7860"

LABEL authors="dr-vij"