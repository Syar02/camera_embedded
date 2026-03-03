#!/bin/bash

echo "=== Running Camera App with OpenCV ==="

# Set library path
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$(pwd):$(pwd)/linux

# Run with verbose to see details
flutter run -d linux --verbose