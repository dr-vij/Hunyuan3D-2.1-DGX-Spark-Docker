# Hunyuan3D-DGX — Gradio UI on DGX Spark

Minimal steps to run the Gradio UI on a DGX Spark node with local development support.

## Setup

### 1. Initialize the submodule
Clone and initialize the Hunyuan3D-2.1-DGX submodule:
```bash
git submodule update --init --recursive
```

This will checkout the [Hunyuan3D-2.1-DGX](https://github.com/dr-vij/Hunyuan3D-2.1-DGX) repository (branch `DGX-Spark`) into `./Hunyuan3D-2.1-DGX`.

**Important**: You can edit the code in `./Hunyuan3D-2.1-DGX` on your host machine, and all changes will be reflected inside the Docker container.

## Run (Docker Compose)
1. Build and start the container:
   ```bash
   docker compose up --build
   ```

   **Note**: The first run will take extra time as it builds custom CUDA components (custom_rasterizer, DifferentiableRenderer) and downloads model weights (~200MB). Subsequent runs will be faster as these components are cached in the mounted volume.

2. Open the UI in your browser:
   - `http://spark-XXNN.local:7860/` (replace `XXNN` with your Spark ID)

## Development
- Edit code in `./Hunyuan3D-2.1-DGX` on your host machine
- Restart the container to apply changes: `docker compose restart`
- To rebuild CUDA components, delete the `.built` marker files in the project directory
