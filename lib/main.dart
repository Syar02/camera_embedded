import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

// Video & Shader packages
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize the media_kit engine for video decoding
  MediaKit.ensureInitialized();
  runApp(const MoilShaderApp());
}

class MoilShaderApp extends StatelessWidget {
  const MoilShaderApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: ThemeData.dark(),
        home: const MoilShaderHome(),
        debugShowCheckedModeBanner: false,
      );
}

// ---------------------------------------------------------
// 1. MOIL CONFIGURATION & PARAMETERS
// ---------------------------------------------------------
class MoilConfig extends ChangeNotifier {
  double alpha = 0.0;
  double beta = 0.0;
  double zoom = 1.0;

  final double imageWidth = 2880.0;
  final double imageHeight = 2880.0;
  final double iCx = 1440.0;
  final double iCy = 1440.0;
  final double calibrationRatio = 6.0;

  final double p0 = 0.0;
  final double p1 = 0.0;
  final double p2 = -8.5773;
  final double p3 = 16.551;
  final double p4 = -4.9915;
  final double p5 = 147.64;

  void updateControls(double a, double b, double z) {
    alpha = a;
    beta = b;
    zoom = z;
    notifyListeners();
  }
}

// ---------------------------------------------------------
// 2. BENCHMARKING ENGINE
// ---------------------------------------------------------
class EngineData extends ChangeNotifier {
  double fps = 0.0;
  double ms = 0.0;

  void update(double currentFps, double currentMs) {
    fps = currentFps;
    ms = currentMs;
    notifyListeners();
  }
}

// ---------------------------------------------------------
// 3. UI & STATE LOOP
// ---------------------------------------------------------
class MoilShaderHome extends StatefulWidget {
  const MoilShaderHome({super.key});
  @override
  State<MoilShaderHome> createState() => _MoilShaderHomeState();
}

class _MoilShaderHomeState extends State<MoilShaderHome> {
  final EngineData _engineData = EngineData();
  final MoilConfig _moilConfig = MoilConfig();

  // Media Kit Controllers
  late final Player _player = Player();
  late final VideoController _videoController = VideoController(_player);

  ui.FragmentProgram? _program;
  DateTime _lastTick = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    final program = await ui.FragmentProgram.fromAsset('shaders/anypoint.frag');
    setState(() {
      _program = program;
    });
  }

  Future<void> _pickVideo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video, // Ensure we are looking for video files
    );
    if (result != null) {
      final path = result.files.single.path!;
      await _player.open(Media(path));
      await _player.setVolume(0); // Optional: mute for visual processing
      await _player.play();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _moilConfig.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _program != null
                    // 1. Listen to config changes so we re-render if sliders move while paused
                    ? AnimatedBuilder(
                        animation: _moilConfig,
                        builder: (context, _) {
                          // 2. AnimatedSampler grabs the child widget as a ui.Image texture
                          return AnimatedSampler(
                            (image, size, canvas) {
                              // Benchmark updates
                              final now = DateTime.now();
                              final dt = now.difference(_lastTick).inMicroseconds / 1000000.0;
                              if (dt > 0) {
                                // Defer state update to avoid "setState during build" errors
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) _engineData.update(1.0 / dt, dt * 1000.0);
                                });
                              }
                              _lastTick = now;

                              final shader = _program!.fragmentShader();

                              // Feed Uniforms
                              shader.setFloat(0, size.width);
                              shader.setFloat(1, size.height);
                              shader.setFloat(2, _moilConfig.alpha);
                              shader.setFloat(3, _moilConfig.beta);
                              shader.setFloat(4, _moilConfig.zoom);
                              shader.setFloat(5, _moilConfig.imageWidth);
                              shader.setFloat(6, _moilConfig.imageHeight);
                              shader.setFloat(7, _moilConfig.iCx);
                              shader.setFloat(8, _moilConfig.iCy);
                              shader.setFloat(9, _moilConfig.calibrationRatio);
                              shader.setFloat(10, _moilConfig.p0);
                              shader.setFloat(11, _moilConfig.p1);
                              shader.setFloat(12, _moilConfig.p2);
                              shader.setFloat(13, _moilConfig.p3);
                              shader.setFloat(14, _moilConfig.p4);
                              shader.setFloat(15, _moilConfig.p5);

                              // Feed the video frame texture
                              shader.setImageSampler(0, image);

                              // Paint the shader
                              canvas.drawRect(
                                Offset.zero & size,
                                Paint()..shader = shader,
                              );
                            },
                            // The actual video rendering layer
                            child: Video(controller: _videoController),
                          );
                        },
                      )
                    : const Center(
                        child: Text(
                          "Loading Shader Engine...",
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
              ),
            ),
          ),

          // Control Sliders
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF111111),
            child: Column(
              children: [
                _buildSlider("Alpha (Pitch)", _moilConfig.alpha, -110, 110, (v) {
                  _moilConfig.updateControls(v, _moilConfig.beta, _moilConfig.zoom);
                }),
                _buildSlider("Beta (Yaw)", _moilConfig.beta, -180, 180, (v) {
                  _moilConfig.updateControls(_moilConfig.alpha, v, _moilConfig.zoom);
                }),
                _buildSlider("Zoom", _moilConfig.zoom, 1.0, 12.0, (v) {
                  _moilConfig.updateControls(_moilConfig.alpha, _moilConfig.beta, v);
                }),
              ],
            ),
          ),

          // Stats Bar
          ListenableBuilder(
            listenable: _engineData,
            builder: (context, _) => Container(
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _engineData.fps > 0
                    ? "MOIL ENGINE | Pipeline: ${_engineData.ms.toStringAsFixed(2)}ms | Render: ${_engineData.fps.toStringAsFixed(1)} FPS"
                    : "ENGINE: IDLE",
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  color: Color(0xFF00FF00),
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton.icon(
                onPressed: _pickVideo,
                icon: const Icon(Icons.video_file),
                label: const Text('Load Fisheye Video Buffer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF222222),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(
      String label, double value, double min, double max, Function(double) onChanged) {
    return Row(
      children: [
        SizedBox(width: 100, child: Text(label, style: const TextStyle(color: Colors.white))),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            activeColor: Colors.cyanAccent,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 50, child: Text(value.toStringAsFixed(1), style: const TextStyle(color: Colors.white))),
      ],
    );
  }
}