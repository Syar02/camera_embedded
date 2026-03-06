import 'dart:async';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:file_picker/file_picker.dart';

// Video & Shader packages
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
// 1. ENGINE DATA (BENCHMARKING)
// ---------------------------------------------------------
class EngineData extends ChangeNotifier {
  double fps = 0.0;
  double frameTimeMs = 0.0;
  String memoryMB = "0";
  
  // Timer untuk update metrik sistem secara berkala
  Timer? _timer;

  EngineData() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateSystemMetrics();
    });
  }

  void updateFrame(double currentFps, double currentMs) {
    fps = currentFps;
    frameTimeMs = currentMs;
    notifyListeners();
  }

  void _updateSystemMetrics() {
    // Mengambil penggunaan memori dari Dart VM
    final usage = ProcessInfo.currentRss / 1024 / 1024;
    memoryMB = usage.toStringAsFixed(1);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------
// 2. MOIL CONFIGURATION
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

  final double p0 = 0.0, p1 = 0.0, p2 = -8.5773, p3 = 16.551, p4 = -4.9915, p5 = 147.64;

  void updateControls(double a, double b, double z) {
    alpha = a;
    beta = b;
    zoom = z;
    notifyListeners();
  }

  void reset() {
    alpha = 0.0; beta = 0.0; zoom = 1.0;
    notifyListeners();
  }
}

// ---------------------------------------------------------
// 3. MAIN UI
// ---------------------------------------------------------
class MoilShaderHome extends StatefulWidget {
  const MoilShaderHome({super.key});
  @override
  State<MoilShaderHome> createState() => _MoilShaderHomeState();
}

class _MoilShaderHomeState extends State<MoilShaderHome> {
  final EngineData _engineData = EngineData();
  final MoilConfig _moilConfig = MoilConfig();

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
    setState(() => _program = program);
  }

  Future<void> _pickVideo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null) {
      await _player.open(Media(result.files.single.path!));
      await _player.setVolume(0);
      await _player.play();
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    double newAlpha = (_moilConfig.alpha + (details.delta.dy * 0.3)).clamp(-110.0, 110.0);
    double newBeta = _moilConfig.beta - (details.delta.dx * 0.3);
    if (newBeta > 180) newBeta -= 360;
    if (newBeta < -180) newBeta += 360;
    _moilConfig.updateControls(newAlpha, newBeta, _moilConfig.zoom);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _program != null
                        ? AnimatedBuilder(
                            animation: _moilConfig,
                            builder: (context, _) {
                              return Listener(
                                onPointerSignal: (event) {
                                  if (event is PointerScrollEvent) {
                                    double z = (_moilConfig.zoom + (event.scrollDelta.dy > 0 ? -0.2 : 0.2)).clamp(1.0, 12.0);
                                    _moilConfig.updateControls(_moilConfig.alpha, _moilConfig.beta, z);
                                  }
                                },
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanUpdate: _handlePanUpdate,
                                  onDoubleTap: () => _moilConfig.reset(),
                                  child: AnimatedSampler(
                                    (image, size, canvas) {
                                      final now = DateTime.now();
                                      final dt = now.difference(_lastTick).inMicroseconds / 1000000.0;
                                      if (dt > 0) {
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          if (mounted) _engineData.updateFrame(1.0 / dt, dt * 1000.0);
                                        });
                                      }
                                      _lastTick = now;

                                      final shader = _program!.fragmentShader();
                                      [size.width, size.height, _moilConfig.alpha, _moilConfig.beta, _moilConfig.zoom,
                                       _moilConfig.imageWidth, _moilConfig.imageHeight, _moilConfig.iCx, _moilConfig.iCy,
                                       _moilConfig.calibrationRatio, _moilConfig.p0, _moilConfig.p1, _moilConfig.p2,
                                       _moilConfig.p3, _moilConfig.p4, _moilConfig.p5].asMap().forEach((i, v) => shader.setFloat(i, v));

                                      shader.setImageSampler(0, image);
                                      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
                                    },
                                    child: IgnorePointer(child: Video(controller: _videoController)),
                                  ),
                                ),
                              );
                            },
                          )
                        : const CircularProgressIndicator(),
                  ),
                ),
              ),
              _buildBottomConsole(),
            ],
          ),
          _buildPerformanceOverlay(), // Overlay melayang untuk benchmark
        ],
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildPerformanceOverlay() {
    return Positioned(
      top: 40,
      left: 20,
      child: ListenableBuilder(
        listenable: _engineData,
        builder: (context, _) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _perfRow(Icons.speed, "FPS", "${_engineData.fps.toStringAsFixed(1)}"),
                _perfRow(Icons.timer, "FRAME", "${_engineData.frameTimeMs.toStringAsFixed(2)} ms"),
                _perfRow(Icons.memory, "MEM (RSS)", "${_engineData.memoryMB} MB"),
                const SizedBox(height: 4),
                const Text("GPU: SHADER ACTIVE", style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _perfRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.cyanAccent),
          const SizedBox(width: 8),
          Text("$label:", style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(width: 5),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildBottomConsole() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF0D0D0D),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.folder),
              label: const Text("LOAD VIDEO SOURCE"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, padding: const EdgeInsets.all(20)),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(onPressed: () => _moilConfig.reset(), icon: const Icon(Icons.refresh), color: Colors.cyanAccent),
        ],
      ),
    );
  }
}