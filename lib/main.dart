import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

// FFI bindings
typedef OpenCameraFunc = Void Function();
typedef OpenCamera = void Function();

typedef StopCameraFunc = Void Function();
typedef StopCamera = void Function();

typedef PauseCameraFunc = Void Function();
typedef PauseCamera = void Function();

typedef ResumeCameraFunc = Void Function();
typedef ResumeCamera = void Function();

typedef InitCameraFunc = Void Function(Int32, Int32);
typedef InitCamera = void Function(int, int);

typedef CloseCameraFunc = Void Function();
typedef CloseCamera = void Function();

typedef NextFrameFunc = Pointer<Uint8> Function();
typedef NextFrame = Pointer<Uint8> Function();

typedef FrameSizeFunc = Int32 Function();
typedef FrameSize = int Function();

typedef IsCameraOpenFunc = Uint8 Function();
typedef IsCameraOpenDart = int Function();

typedef IsCameraPausedFunc = Uint8 Function();
typedef IsCameraPausedDart = int Function();

// Native library functions
late OpenCamera openCamera;
late StopCamera stopCamera;
late PauseCamera pauseCamera;
late ResumeCamera resumeCamera;
late InitCamera initCamera;
late CloseCamera closeCamera;
late NextFrame nextFrame;
late FrameSize frameSize;
late int Function() isCameraOpen;
late int Function() isCameraPaused;

bool _isNativeLibLoaded = false;

void _loadNativeLibrary() {
  if (_isNativeLibLoaded) return;
  
  if (Platform.isLinux) {
    String exeDir = Directory.current.path;
    
    final possiblePaths = [
      './libcamera_driver.so',
      './linux/libcamera_driver.so',
      '${exeDir}/libcamera_driver.so',
      '${exeDir}/linux/libcamera_driver.so',
      '${exeDir}/build/linux/x64/debug/bundle/libcamera_driver.so',
      '/usr/local/lib/libcamera_driver.so',
    ];
    
    String? ldLibraryPath = Platform.environment['LD_LIBRARY_PATH'];
    if (ldLibraryPath != null) {
      for (var path in ldLibraryPath.split(':')) {
        possiblePaths.add('${path}/libcamera_driver.so');
      }
    }
    
    DynamicLibrary? dylib;
    String? loadedPath;
    
    for (final libPath in possiblePaths) {
      try {
        print('Trying to load: $libPath');
        dylib = DynamicLibrary.open(libPath);
        loadedPath = libPath;
        print('✓ Successfully loaded from: $libPath');
        break;
      } catch (e) {
        print('✗ Failed to load $libPath: $e');
      }
    }
    
    if (dylib == null) {
      throw Exception('Could not load camera driver library from any path');
    }
    
    try {
      openCamera = dylib.lookup<NativeFunction<OpenCameraFunc>>('open_camera').asFunction();
      stopCamera = dylib.lookup<NativeFunction<StopCameraFunc>>('stop_camera').asFunction();
      pauseCamera = dylib.lookup<NativeFunction<PauseCameraFunc>>('pause_camera').asFunction();
      resumeCamera = dylib.lookup<NativeFunction<ResumeCameraFunc>>('resume_camera').asFunction();
      initCamera = dylib.lookup<NativeFunction<InitCameraFunc>>('init_camera').asFunction();
      closeCamera = dylib.lookup<NativeFunction<CloseCameraFunc>>('close_camera').asFunction();
      nextFrame = dylib.lookup<NativeFunction<NextFrameFunc>>('next_frame').asFunction();
      frameSize = dylib.lookup<NativeFunction<FrameSizeFunc>>('frame_size').asFunction();
      isCameraOpen = dylib.lookup<NativeFunction<IsCameraOpenFunc>>('is_camera_open').asFunction();
      isCameraPaused = dylib.lookup<NativeFunction<IsCameraPausedFunc>>('is_camera_paused').asFunction();
      
      _isNativeLibLoaded = true;
      print('✓ All native functions loaded successfully');
      print('✓ Camera driver initialized from: $loadedPath');
      
    } catch (e) {
      throw Exception('Failed to bind native functions: $e');
    }
  } else {
    throw UnsupportedError('Platform not supported');
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    _loadNativeLibrary();
    runApp(const CameraApp());
  } catch (e) {
    print('Fatal error: $e');
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Failed to load native library',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error: $e',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => exit(0),
                child: const Text('Exit'),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}

class CameraApp extends StatelessWidget {
  const CameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Embedded Camera Controller',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const CameraPage(),
    );
  }
}

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  static const int width = 640;
  static const int height = 480;
  
  ui.Image? _currentImage;
  Timer? _frameTimer;
  bool _isInitialized = false;
  bool _isCameraOpen = false;
  bool _isCameraPaused = false;
  String _statusMessage = 'Initializing...';
  int _frameCount = 0;
  double _fps = 0;
  DateTime _lastFpsUpdate = DateTime.now();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopFrameCapture();
    if (_isNativeLibLoaded && _isCameraOpen) {
      try {
        closeCamera();
      } catch (e) {
        print('Error closing camera: $e');
      }
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _stopFrameCapture();
    } else if (state == AppLifecycleState.resumed) {
      if (_isCameraOpen && !_isCameraPaused) {
        _startFrameCapture();
      }
    }
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Initializing camera...';
    });

    try {
      initCamera(width, height);
      
      setState(() {
        _isInitialized = true;
        _isLoading = false;
        _statusMessage = 'Camera ready';
      });
      
      print('Camera initialized successfully');
      
    } catch (e) {
      print('Failed to initialize camera: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Failed to initialize camera';
      });
    }
  }

  void _openCamera() {
    if (!_isInitialized) {
      _showSnackBar('Camera not initialized');
      return;
    }
    
    setState(() {
      _isLoading = true;
      _statusMessage = 'Opening camera...';
    });

    try {
      openCamera();
      
      setState(() {
        _isCameraOpen = true;
        _isCameraPaused = false;
        _isLoading = false;
        _statusMessage = 'Camera running';
        _frameCount = 0;
      });
      
      _startFrameCapture();
      _showSnackBar('Camera opened successfully');
      print('Camera opened');
      
    } catch (e) {
      print('Failed to open camera: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Failed to open camera';
      });
      _showSnackBar('Error opening camera');
    }
  }

  void _stopCamera() {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Stopping camera...';
    });

    try {
      stopCamera();
      
      setState(() {
        _isCameraOpen = false;
        _isCameraPaused = false;
        _isLoading = false;
        _statusMessage = 'Camera stopped';
        _currentImage = null;
      });
      
      _stopFrameCapture();
      _showSnackBar('Camera stopped');
      print('Camera stopped');
      
    } catch (e) {
      print('Failed to stop camera: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Failed to stop camera';
      });
    }
  }

  void _pauseCamera() {
    if (!_isCameraOpen) {
      _showSnackBar('Camera is not open');
      return;
    }
    
    if (_isCameraPaused) {
      _showSnackBar('Camera already paused');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Pausing camera...';
    });

    try {
      pauseCamera();
      
      setState(() {
        _isCameraPaused = true;
        _isLoading = false;
        _statusMessage = 'Camera paused';
      });
      
      _showSnackBar('Camera paused');
      print('Camera paused');
      
    } catch (e) {
      print('Failed to pause camera: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Failed to pause camera';
      });
    }
  }

  void _resumeCamera() {
    if (!_isCameraOpen) {
      _showSnackBar('Camera is not open');
      return;
    }
    
    if (!_isCameraPaused) {
      _showSnackBar('Camera is not paused');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Resuming camera...';
    });

    try {
      resumeCamera();
      
      setState(() {
        _isCameraPaused = false;
        _isLoading = false;
        _statusMessage = 'Camera running';
      });
      
      _showSnackBar('Camera resumed');
      print('Camera resumed');
      
    } catch (e) {
      print('Failed to resume camera: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Failed to resume camera';
      });
    }
  }

  void _startFrameCapture() {
    _frameTimer?.cancel();
    _lastFpsUpdate = DateTime.now();
    _frameCount = 0;
    
    _frameTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (_isCameraOpen && !_isCameraPaused && mounted) {
        _captureFrame();
      }
    });
  }

  void _stopFrameCapture() {
    _frameTimer?.cancel();
    _frameTimer = null;
  }

  Future<void> _captureFrame() async {
    try {
      final ptr = nextFrame();
      final size = frameSize();
      
      if (ptr.address != 0 && size > 0) {
        final rawData = ptr.asTypedList(size);
        
        // Convert RGB to RGBA
        final rgbaData = Uint8List(size ~/ 3 * 4);
        for (int i = 0; i < size; i += 3) {
          final rgbaIdx = (i ~/ 3) * 4;
          rgbaData[rgbaIdx] = rawData[i];
          rgbaData[rgbaIdx + 1] = rawData[i + 1];
          rgbaData[rgbaIdx + 2] = rawData[i + 2];
          rgbaData[rgbaIdx + 3] = 255;
        }
        
        final completer = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          rgbaData,
          width,
          height,
          ui.PixelFormat.rgba8888,
          (ui.Image image) {
            completer.complete(image);
          },
        );
        
        final image = await completer.future;
        
        if (mounted) {
          _frameCount++;
          final now = DateTime.now();
          final diff = now.difference(_lastFpsUpdate).inMilliseconds;
          if (diff >= 1000) {
            setState(() {
              _fps = _frameCount * 1000 / diff;
              _frameCount = 0;
              _lastFpsUpdate = now;
            });
          }
          
          setState(() {
            _currentImage = image;
          });
        }
      } else {
        print('Warning: Null frame or zero size');
      }
    } catch (e) {
      print('Frame capture error: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Embedded Camera Controller'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          if (_isCameraOpen)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isCameraPaused ? Colors.orange : Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isCameraPaused ? 'PAUSED' : 'LIVE',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Camera view
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black,
              child: Stack(
                children: [
                  Center(
                    child: _currentImage == null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isLoading ? Icons.hourglass_empty : Icons.videocam_off,
                                size: 64,
                                color: Colors.white54,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _statusMessage,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              if (_isLoading)
                                const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: CircularProgressIndicator(),
                                ),
                            ],
                          )
                        : RawImage(
                            image: _currentImage,
                            width: width.toDouble(),
                            height: height.toDouble(),
                            fit: BoxFit.contain,
                          ),
                  ),
                  // FPS counter
                  if (_isCameraOpen && !_isCameraPaused && _currentImage != null)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_fps.toStringAsFixed(1)} FPS',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  // Resolution info
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${width}x${height}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Control panel
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              children: [
                // Status indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _isCameraOpen
                        ? (_isCameraPaused ? Colors.orange : Colors.green)
                        : Colors.red,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: (_isCameraOpen
                            ? (_isCameraPaused ? Colors.orange : Colors.green)
                            : Colors.red).withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isCameraOpen
                            ? (_isCameraPaused ? 'PAUSED' : 'RUNNING')
                            : 'STOPPED',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildControlButton(
                      icon: Icons.play_arrow,
                      label: 'Open',
                      color: Colors.green,
                      onPressed: (!_isInitialized || _isCameraOpen) ? null : _openCamera,
                    ),
                    _buildControlButton(
                      icon: Icons.pause,
                      label: 'Pause',
                      color: Colors.orange,
                      onPressed: (_isCameraOpen && !_isCameraPaused)
                          ? _pauseCamera
                          : null,
                    ),
                    _buildControlButton(
                      icon: Icons.play_arrow,
                      label: 'Resume',
                      color: Colors.blue,
                      onPressed: (_isCameraOpen && _isCameraPaused) ? _resumeCamera : null,
                    ),
                    _buildControlButton(
                      icon: Icons.stop,
                      label: 'Stop',
                      color: Colors.red,
                      onPressed: _isCameraOpen ? _stopCamera : null,
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Info text
                Text(
                  'Camera Status: $_statusMessage',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onPressed,
  }) {
    final isEnabled = onPressed != null && !_isLoading;
    
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isEnabled ? color : Colors.grey[700],
            boxShadow: isEnabled ? [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ] : null,
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white),
            onPressed: onPressed,
            iconSize: 32,
            padding: const EdgeInsets.all(16),
            disabledColor: Colors.grey[500],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: isEnabled ? Colors.white : Colors.grey[500],
            fontSize: 12,
            fontWeight: isEnabled ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}