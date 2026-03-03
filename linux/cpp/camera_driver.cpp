#include "camera_driver.h"
#include <iostream>
#include <vector>
#include <thread>
#include <mutex>
#include <atomic>
#include <chrono>
#include <cstring>
#include <opencv2/opencv.hpp>
#include <opencv2/core.hpp>
#include <opencv2/videoio.hpp>
#include <opencv2/imgproc.hpp>

// Camera state
static std::atomic<bool> g_isOpen{false};
static std::atomic<bool> g_isPaused{false};
static std::atomic<bool> g_isRunning{false};

static int g_width = 640;
static int g_height = 480;
static int g_deviceId = 0; // Default camera device

// OpenCV objects
static cv::VideoCapture g_cap;
static cv::Mat g_frame;
static cv::Mat g_rgbFrame;

static std::vector<uint8_t> g_frameBuffer;
static std::vector<uint8_t> g_currentFrame;
static std::mutex g_frameMutex;
static std::thread g_cameraThread;
static std::atomic<bool> g_threadRunning{false};

// Daftar device kamera yang tersedia
static std::vector<int> g_availableDevices;

// Fungsi untuk scan kamera yang tersedia
static void scanAvailableCameras() {
    g_availableDevices.clear();
    
    // Coba 5 device pertama (/dev/video0 sampai /dev/video4)
    for (int i = 0; i < 5; i++) {
        cv::VideoCapture testCap(i);
        if (testCap.isOpened()) {
            g_availableDevices.push_back(i);
            testCap.release();
            std::cout << "[Camera Driver] Found camera device: /dev/video" << i << std::endl;
        }
    }
    
    if (g_availableDevices.empty()) {
        std::cerr << "[Camera Driver] No camera devices found!" << std::endl;
    } else {
        std::cout << "[Camera Driver] Total cameras found: " << g_availableDevices.size() << std::endl;
    }
}

// Fungsi untuk inisialisasi OpenCV camera
static bool initOpenCVCamera() {
    // Scan kamera yang tersedia
    scanAvailableCameras();
    
    if (g_availableDevices.empty()) {
        return false;
    }
    
    // Gunakan device pertama sebagai default
    g_deviceId = g_availableDevices[0];
    std::cout << "[Camera Driver] Using camera device: /dev/video" << g_deviceId << std::endl;
    
    // Buka kamera
    g_cap.open(g_deviceId);
    if (!g_cap.isOpened()) {
        std::cerr << "[Camera Driver] Error: Cannot open camera device " << g_deviceId << std::endl;
        return false;
    }
    
    // Set resolusi
    g_cap.set(cv::CAP_PROP_FRAME_WIDTH, g_width);
    g_cap.set(cv::CAP_PROP_FRAME_HEIGHT, g_height);
    
    // Set FPS (jika didukung)
    g_cap.set(cv::CAP_PROP_FPS, 30);
    
    // Dapatkan resolusi aktual
    int actualWidth = static_cast<int>(g_cap.get(cv::CAP_PROP_FRAME_WIDTH));
    int actualHeight = static_cast<int>(g_cap.get(cv::CAP_PROP_FRAME_HEIGHT));
    double actualFps = g_cap.get(cv::CAP_PROP_FPS);
    
    std::cout << "[Camera Driver] Camera initialized: " 
              << actualWidth << "x" << actualHeight 
              << " @ " << actualFps << " fps" << std::endl;
    
    // Update resolusi jika berbeda
    if (actualWidth > 0 && actualHeight > 0) {
        g_width = actualWidth;
        g_height = actualHeight;
    }
    
    return true;
}

// Camera thread function
static void cameraThreadFunction() {
    std::cout << "[Camera Driver] Camera thread started" << std::endl;
    
    cv::Mat frame;
    int frameCount = 0;
    auto lastTime = std::chrono::steady_clock::now();
    
    while (g_threadRunning) {
        if (g_isOpen && !g_isPaused && g_cap.isOpened()) {
            // Capture frame
            if (g_cap.read(frame)) {
                if (!frame.empty()) {
                    // Convert BGR (OpenCV default) to RGB
                    cv::cvtColor(frame, frame, cv::COLOR_BGR2RGB);
                    
                    // Resize jika perlu
                    if (frame.cols != g_width || frame.rows != g_height) {
                        cv::resize(frame, frame, cv::Size(g_width, g_height));
                    }
                    
                    // Update current frame dengan thread safety
                    {
                        std::lock_guard<std::mutex> lock(g_frameMutex);
                        g_currentFrame.assign(frame.data, frame.data + (frame.total() * frame.elemSize()));
                    }
                    
                    // Hitung FPS real
                    frameCount++;
                    auto now = std::chrono::steady_clock::now();
                    auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(now - lastTime).count();
                    if (elapsed >= 1) {
                        std::cout << "[Camera Driver] Real FPS: " << frameCount / elapsed << std::endl;
                        frameCount = 0;
                        lastTime = now;
                    }
                }
            } else {
                std::cerr << "[Camera Driver] Failed to capture frame" << std::endl;
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
            }
        } else {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
    }
    
    std::cout << "[Camera Driver] Camera thread stopped" << std::endl;
}

// Implementation of camera control functions
void open_camera() {
    std::cout << "[Camera Driver] Opening camera..." << std::endl;
    
    if (!g_isOpen) {
        if (!g_cap.isOpened()) {
            if (!initOpenCVCamera()) {
                std::cerr << "[Camera Driver] Failed to initialize OpenCV camera" << std::endl;
                return;
            }
        }
        
        g_isOpen = true;
        g_isPaused = false;
        
        // Start camera thread
        if (!g_threadRunning) {
            g_threadRunning = true;
            g_cameraThread = std::thread(cameraThreadFunction);
        }
        
        std::cout << "[Camera Driver] Camera opened successfully" << std::endl;
    }
}

void stop_camera() {
    std::cout << "[Camera Driver] Stopping camera..." << std::endl;
    g_isOpen = false;
    g_isPaused = false;
    
    // Clear frame buffer
    {
        std::lock_guard<std::mutex> lock(g_frameMutex);
        g_currentFrame.clear();
    }
}

void pause_camera() {
    std::cout << "[Camera Driver] Pausing camera..." << std::endl;
    g_isPaused = true;
}

void resume_camera() {
    std::cout << "[Camera Driver] Resuming camera..." << std::endl;
    g_isPaused = false;
}

void init_camera(int width, int height) {
    std::cout << "[Camera Driver] Initializing camera with " << width << "x" << height << std::endl;
    g_width = width;
    g_height = height;
    g_frameBuffer.resize(width * height * 3); // RGB format
}

void close_camera() {
    std::cout << "[Camera Driver] Closing camera..." << std::endl;
    
    // Stop camera thread
    g_threadRunning = false;
    g_isOpen = false;
    
    if (g_cameraThread.joinable()) {
        g_cameraThread.join();
    }
    
    // Release OpenCV camera
    if (g_cap.isOpened()) {
        g_cap.release();
    }
    
    // Clear buffers
    {
        std::lock_guard<std::mutex> lock(g_frameMutex);
        g_currentFrame.clear();
    }
    g_frameBuffer.clear();
    
    std::cout << "[Camera Driver] Camera closed" << std::endl;
}

uint8_t* next_frame() {
    if (!g_isOpen || g_isPaused || !g_cap.isOpened()) {
        return nullptr;
    }
    
    std::lock_guard<std::mutex> lock(g_frameMutex);
    if (g_currentFrame.empty()) {
        return nullptr;
    }
    
    // Copy frame ke buffer static untuk return
    g_frameBuffer = g_currentFrame;
    return g_frameBuffer.data();
}

int frame_size() {
    return g_width * g_height * 3; // RGB = 3 bytes per pixel
}

uint8_t is_camera_open() {
    return g_isOpen ? 1 : 0;
}

uint8_t is_camera_paused() {
    return g_isPaused ? 1 : 0;
}