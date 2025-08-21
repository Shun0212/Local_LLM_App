#!/usr/bin/env python3
"""
Test script for image generation functionality.
Usage: python test_image_generation.py
"""

import requests
import json
import base64
import sys
from io import BytesIO
from PIL import Image

def test_image_generation(server_url="http://localhost:8000"):
    """Test the image generation endpoint"""
    
    # Test data
    test_prompts = [
        {"prompt": "A beautiful sunset over mountains", "width": 256, "height": 256},
        {"prompt": "A cute cat sitting on a chair", "width": 512, "height": 512},
        {"prompt": "Abstract colorful painting", "width": 300, "height": 300}
    ]
    
    print(f"Testing image generation at {server_url}")
    print("=" * 50)
    
    for i, test_data in enumerate(test_prompts, 1):
        print(f"\nTest {i}: {test_data['prompt']}")
        print(f"Dimensions: {test_data['width']}x{test_data['height']}")
        
        try:
            # Make request
            response = requests.post(
                f"{server_url}/generate_image",
                json=test_data,
                timeout=30
            )
            
            if response.status_code == 200:
                data = response.json()
                print(f"✅ Success!")
                print(f"   Prompt: {data['prompt']}")
                print(f"   Size: {data['width']}x{data['height']}")
                print(f"   Image data length: {len(data['image'])} chars")
                
                # Validate image data
                try:
                    # Extract base64 data
                    image_data = data['image'].split(',')[1]
                    image_bytes = base64.b64decode(image_data)
                    
                    # Try to open as image
                    img = Image.open(BytesIO(image_bytes))
                    print(f"   ✅ Valid PNG image: {img.size} {img.mode}")
                    
                except Exception as e:
                    print(f"   ❌ Invalid image data: {e}")
                    
            else:
                print(f"❌ Failed with status {response.status_code}")
                print(f"   Error: {response.text}")
                
        except requests.RequestException as e:
            print(f"❌ Request failed: {e}")
    
    print("\n" + "=" * 50)
    print("Test complete!")

def test_health_check(server_url="http://localhost:8000"):
    """Test the health check endpoint"""
    try:
        response = requests.get(f"{server_url}/healthz", timeout=5)
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Server healthy: {data}")
            return True
        else:
            print(f"❌ Health check failed: {response.status_code}")
            return False
    except requests.RequestException as e:
        print(f"❌ Cannot connect to server: {e}")
        return False

if __name__ == "__main__":
    server_url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000"
    
    print("Local LLM App - Image Generation Test")
    print("=" * 50)
    
    # Check if server is running
    if test_health_check(server_url):
        test_image_generation(server_url)
    else:
        print("\nPlease start the server first:")
        print("cd server && python app.py")
        sys.exit(1)