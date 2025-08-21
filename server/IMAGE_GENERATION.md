# Image Generation Setup

This document explains how to set up real AI image generation models in the Local LLM App server.

## Current Implementation

By default, the server uses **placeholder images** when AI models are not available. This ensures the feature works out of the box without requiring large model downloads or GPU resources.

## Adding Real AI Image Generation

### Option 1: Stable Diffusion (Recommended)

1. Install additional dependencies:
```bash
pip install torch transformers diffusers accelerate
```

2. For better performance on NVIDIA GPUs:
```bash
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
```

3. Set environment variables (optional):
```bash
export IMAGE_MODEL=runwayml/stable-diffusion-v1-5
# Or use other models like:
# export IMAGE_MODEL=stabilityai/stable-diffusion-2-1
# export IMAGE_MODEL=CompVis/stable-diffusion-v1-4
```

### Option 2: Qwen-VL Integration

To use Qwen-VL models as mentioned in the original request:

1. Install transformers with vision support:
```bash
pip install transformers[vision] torch torchvision
```

2. Modify the `_get_image_pipeline()` function in `app.py` to use Qwen models:
```python
# Replace the StableDiffusionPipeline import with:
from transformers import AutoProcessor, AutoModel

# And update the pipeline initialization:
model_id = "Qwen/Qwen-VL-Chat"  # or another Qwen model
processor = AutoProcessor.from_pretrained(model_id)
model = AutoModel.from_pretrained(model_id)
```

### Hardware Requirements

- **CPU Only**: Works but very slow (30+ seconds per image)
- **GPU with 4GB+ VRAM**: Recommended for reasonable performance
- **GPU with 8GB+ VRAM**: Best performance with larger models

### Memory Optimization

For systems with limited memory, add these optimizations to `app.py`:

```python
# In _get_image_pipeline()
if hasattr(_image_pipeline, "enable_attention_slicing"):
    _image_pipeline.enable_attention_slicing()
    
if hasattr(_image_pipeline, "enable_sequential_cpu_offload"):
    _image_pipeline.enable_sequential_cpu_offload()
```

## Testing Image Generation

1. Start the server:
```bash
python app.py
```

2. Test with curl:
```bash
curl -X POST http://localhost:8000/generate_image \
  -H "Content-Type: application/json" \
  -d '{"prompt": "A beautiful mountain landscape", "width": 512, "height": 512}'
```

3. Check the response includes a base64-encoded image.

## Troubleshooting

**Error: "No module named 'diffusers'"**
- Install the required packages: `pip install diffusers torch transformers`

**Error: "CUDA out of memory"**
- Reduce image dimensions: use 256x256 instead of 512x512
- Enable memory optimizations (see above)
- Use CPU instead of GPU (slower but works)

**Images take too long to generate**
- Reduce `num_inference_steps` (default: 20, try 10-15)
- Use a smaller/faster model
- Ensure you're using GPU acceleration

**Poor image quality**
- Increase `num_inference_steps` 
- Improve your text prompts
- Try different models (e.g., Stable Diffusion 2.1)

## Model Recommendations

| Model | Size | Quality | Speed | Memory |
|-------|------|---------|-------|--------|
| runwayml/stable-diffusion-v1-5 | ~4GB | Good | Medium | 4GB+ |
| stabilityai/stable-diffusion-2-1 | ~5GB | Better | Slower | 6GB+ |
| CompVis/stable-diffusion-v1-4 | ~4GB | Good | Medium | 4GB+ |

Choose based on your hardware capabilities and quality requirements.