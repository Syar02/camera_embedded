#!/bin/bash

echo "=== Building Camera App with OpenCV ==="

# Hapus build lama
echo "1. Cleaning old builds..."
rm -rf linux/cpp/build
rm -f libcamera_driver.so
rm -f linux/libcamera_driver.so
flutter clean

# Build C++ library
echo "2. Building C++ library with OpenCV..."
cd linux/cpp
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4
cd ../../..

# Check if build succeeded
if [ ! -f "linux/cpp/build/libcamera_driver.so" ]; then
    echo "Error: Failed to build C++ library"
    exit 1
fi

# Copy library
echo "3. Copying library..."
cp linux/cpp/build/libcamera_driver.so .
cp linux/cpp/build/libcamera_driver.so linux/

# Get Flutter packages
echo "4. Getting Flutter packages..."
flutter pub get

echo "=== Build Complete ==="
echo "Run with: ./run_final.sh"