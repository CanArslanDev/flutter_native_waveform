import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:just_audio/just_audio.dart';
import 'dart:async';

import 'package:flutter/services.dart' show MethodChannel, rootBundle;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Native Waveform',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const WaveformPage(),
    );
  }
}

class WaveformPage extends StatefulWidget {
  const WaveformPage({super.key});

  @override
  State<WaveformPage> createState() => _WaveformPageState();
}

class _WaveformPageState extends State<WaveformPage> {
  Uint8List? audioData;
  bool isLoading = true;

  double barWidth = 3.0;
  double spacing = 2.0;
  double borderRadius = 8.0;
  int barCount = 100;
  Color waveformColor = const Color(0xFFE1306C);
  Color backgroundColor = const Color(0xFF121212);
  bool isPlaying = false;

  final AudioPlayer _audioPlayer = AudioPlayer();
  Duration? _duration;
  Duration _position = Duration.zero;
  Timer? _progressTimer;

  final List<double> _audioLevels = [];

  final String _audioAsset = 'assets/audio.m4a';

  static const platform = MethodChannel(
    'com.example.flutter_native_waveform/audio',
  );

  @override
  void initState() {
    super.initState();
    _loadAudioFile();
    _initializePlayer();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _initializePlayer() async {
    try {
      await _audioPlayer.setAsset(_audioAsset);

      _duration = await _audioPlayer.duration;

      _audioPlayer.positionStream.listen((position) {
        if (mounted) {
          setState(() {
            _position = position;
            if (isPlaying) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {});
              });
            }
          });
        }
      });

      _audioPlayer.playerStateStream.listen((state) {
        if (mounted) {
          setState(() {
            isPlaying = state.playing;
            if (isPlaying) {
              _startProgressTimer();
            } else {
              _progressTimer?.cancel();
            }
          });
        }
      });
    } catch (e) {
      print('Error initializing audio player: $e');
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _loadAudioFile() async {
    try {
      final ByteData data = await rootBundle.load(_audioAsset);
      final Uint8List audioBytes = data.buffer.asUint8List();

      setState(() {
        audioData = audioBytes;
        isLoading = false;
      });

      print('Audio file loaded successfully. Size: ${audioBytes.length} bytes');

      await _generateWaveformUsingPlatformChannel();
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      print('Error loading audio file: $e');
    }
  }

  Future<void> _generateWaveformUsingPlatformChannel() async {
    if (audioData == null || audioData!.isEmpty) {
      print("Audio data is empty or null, cannot process");
      return;
    }

    try {
      print(
        "Sending data to platform channel. Data size: ${audioData!.length}",
      );

      final List<dynamic> pcmData = await platform.invokeMethod(
        'extractPCMFromMP3',
        {'mp3Data': Uint8List.fromList(audioData!)},
      );

      print("Received ${pcmData.length} PCM values from platform channel");

      _generateWaveformFromPCMData(pcmData);

      if (pcmData.isEmpty) {
        print('PCM data is empty, creating simulated waveform');
        _generateFakeButVisuallyRealisticWaveform();
      }
    } catch (e) {
      print('Platform channel waveform error: $e');

      _generateFakeButVisuallyRealisticWaveform();
    }
  }

  void _generateWaveformFromPCMData(List<dynamic> pcmData) {
    _audioLevels.clear();

    const int totalBars = 200;

    int totalSamples = pcmData.length;

    int samplesPerBar = totalSamples ~/ totalBars;

    for (int i = 0; i < totalBars; i++) {
      int startSample = i * samplesPerBar;
      int endSample = math.min((i + 1) * samplesPerBar, totalSamples);

      double rmsValue = _calculateRMSAmplitude(pcmData, startSample, endSample);
      _audioLevels.add(rmsValue);
    }

    _normalizeAudioLevels();

    if (mounted) {
      setState(() {});
    }
  }

  double _calculateRMSAmplitude(List<dynamic> pcmData, int start, int end) {
    if (start >= end || start >= pcmData.length) return 0;

    double sumOfSquares = 0;
    int sampleCount = 0;

    for (int i = start; i < end && i < pcmData.length; i++) {
      double sampleValue = pcmData[i].toDouble();
      sumOfSquares += sampleValue * sampleValue;
      sampleCount++;
    }

    return sampleCount > 0 ? math.sqrt(sumOfSquares / sampleCount) : 0;
  }

  void _generateFakeButVisuallyRealisticWaveform() {
    _audioLevels.clear();

    const int barCount = 200;
    final random = math.Random(42);

    List<double> baseSine = List.generate(
      barCount,
      (i) =>
          0.3 +
          0.15 * math.sin(i * 0.05) +
          0.1 * math.sin(i * 0.02) +
          0.05 * math.sin(i * 0.01),
    );

    for (int i = 0; i < barCount; i++) {
      double randomVariation = 0.1 * random.nextDouble();
      double value = baseSine[i] + randomVariation;

      if (i > barCount * 0.6) {
        value *= 1.5;
      } else if (i < barCount * 0.3) {
        value *= 0.8;
      }

      if (random.nextInt(20) == 0) {
        value *= 1.5;
      }

      _audioLevels.add(value);
    }

    _normalizeAudioLevels();
  }

  void _normalizeAudioLevels() {
    if (_audioLevels.isEmpty) return;

    double minValue = double.infinity;
    double maxValue = -double.infinity;

    for (double level in _audioLevels) {
      if (level < minValue) minValue = level;
      if (level > maxValue) maxValue = level;
    }

    double range = maxValue - minValue;

    if (range <= 0.01) {
      for (int i = 0; i < _audioLevels.length; i++) {
        _audioLevels[i] = 0.3 + 0.2 * math.sin(i * 0.1);
      }
      return;
    }

    for (int i = 0; i < _audioLevels.length; i++) {
      _audioLevels[i] = 0.1 + 0.9 * ((_audioLevels[i] - minValue) / range);
    }

    _smoothWaveform();

    _enhancePeaks();
  }

  void _smoothWaveform() {
    if (_audioLevels.length < 3) return;

    List<double> smoothed = List<double>.from(_audioLevels);

    for (int i = 1; i < _audioLevels.length - 1; i++) {
      smoothed[i] =
          (_audioLevels[i - 1] * 0.25 +
              _audioLevels[i] * 0.5 +
              _audioLevels[i + 1] * 0.25);
    }

    _audioLevels.clear();
    _audioLevels.addAll(smoothed);
  }

  void _enhancePeaks() {
    if (_audioLevels.length < 3) return;

    List<double> enhanced = List<double>.from(_audioLevels);

    for (int i = 1; i < _audioLevels.length - 1; i++) {
      if (_audioLevels[i] > _audioLevels[i - 1] &&
          _audioLevels[i] > _audioLevels[i + 1]) {
        enhanced[i] = math.min(1.0, _audioLevels[i] * 1.2);
      }
    }

    _audioLevels.clear();
    _audioLevels.addAll(enhanced);
  }

  void _togglePlayPause() {
    if (isPlaying) {
      _audioPlayer.pause();
      _progressTimer?.cancel();
    } else {
      _audioPlayer.play();

      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && _audioPlayer.playing) {
          _startProgressTimer();
        }
      });
    }
  }

  double get _progressPercent {
    if (_duration == null || _duration!.inMilliseconds == 0) {
      return 0.0;
    }

    if (isPlaying && _progressTimer == null) {
      return 0.0;
    }

    final position = _position;
    final durationMs = _duration!.inMilliseconds;
    double progress = position.inMilliseconds / durationMs;

    if (isPlaying) {
      final predictiveFactor = 50.0 / durationMs;
      progress = math.min(1.0, progress + predictiveFactor);
    }

    return progress.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Audio Waveform',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: backgroundColor,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body:
          isLoading
              ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFE1306C)),
              )
              : audioData == null
              ? const Center(
                child: Text(
                  'Could not load audio file',
                  style: TextStyle(color: Colors.white),
                ),
              )
              : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: double.infinity,
                              height: 200,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child:
                                    _audioLevels.isEmpty
                                        ? const Center(
                                          child: Text(
                                            'Analyzing audio...',
                                            style: TextStyle(
                                              color: Colors.white54,
                                            ),
                                          ),
                                        )
                                        : SimpleWaveform(
                                          audioLevels: _audioLevels,
                                          barWidth: barWidth,
                                          spacing: spacing,
                                          borderRadius: borderRadius,
                                          barCount: barCount,
                                          color: waveformColor,
                                          isPlaying: isPlaying,
                                          progress: _progressPercent,
                                        ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _formatDuration(_position),
                                  style: const TextStyle(color: Colors.white),
                                ),
                                const SizedBox(width: 12),
                                GestureDetector(
                                  onTap: _togglePlayPause,
                                  child: Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: waveformColor,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: waveformColor.withOpacity(0.3),
                                          blurRadius: 12,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _duration != null
                                      ? _formatDuration(_duration!)
                                      : '0:00',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Waveform Settings',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildSlider(
                            label: 'Bar Width',
                            value: barWidth,
                            min: 1.0,
                            max: 10.0,
                            onChanged: (value) {
                              setState(() {
                                barWidth = value;
                              });
                            },
                          ),
                          _buildSlider(
                            label: 'Bar Spacing',
                            value: spacing,
                            min: 0.0,
                            max: 5.0,
                            onChanged: (value) {
                              setState(() {
                                spacing = value;
                              });
                            },
                          ),
                          _buildSlider(
                            label: 'Bar Count',
                            value: barCount.toDouble(),
                            min: 20,
                            max: 200,
                            onChanged: (value) {
                              setState(() {
                                barCount = value.toInt();
                              });
                            },
                          ),
                          _buildSlider(
                            label: 'Corner Radius',
                            value: borderRadius,
                            min: 0.0,
                            max: 10.0,
                            onChanged: (value) {
                              setState(() {
                                borderRadius = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '$twoDigitMinutes:$twoDigitSeconds';
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required Function(double) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70)),
            Text(
              value.toStringAsFixed(1),
              style: TextStyle(color: waveformColor),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: waveformColor,
            inactiveTrackColor: Colors.white24,
            thumbColor: waveformColor,
            overlayColor: waveformColor.withOpacity(0.2),
            trackHeight: 4,
          ),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class SimpleWaveform extends StatelessWidget {
  final List<double> audioLevels;
  final double barWidth;
  final double spacing;
  final double borderRadius;
  final int barCount;
  final Color color;
  final bool isPlaying;
  final double progress;

  const SimpleWaveform({
    super.key,
    required this.audioLevels,
    this.barWidth = 3.0,
    this.spacing = 2.0,
    this.borderRadius = 8.0,
    this.barCount = 100,
    this.color = const Color(0xFFE1306C),
    this.isPlaying = false,
    this.progress = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: SimpleWaveformPainter(
        audioLevels: audioLevels,
        barWidth: barWidth,
        spacing: spacing,
        borderRadius: borderRadius,
        barCount: barCount,
        color: color,
        isPlaying: isPlaying,
        progress: progress,
      ),
      child: Container(),
    );
  }
}

class SimpleWaveformPainter extends CustomPainter {
  final List<double> audioLevels;
  final double barWidth;
  final double spacing;
  final double borderRadius;
  final int barCount;
  final Color color;
  final bool isPlaying;
  final double progress;
  final Paint barPaint;
  final Paint playedBarPaint;

  SimpleWaveformPainter({
    required this.audioLevels,
    required this.barWidth,
    required this.spacing,
    required this.borderRadius,
    required this.barCount,
    required this.color,
    required this.isPlaying,
    required this.progress,
  }) : barPaint =
           Paint()
             ..color = color.withOpacity(0.5)
             ..style = PaintingStyle.fill,
       playedBarPaint =
           Paint()
             ..color = color
             ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (audioLevels.isEmpty) return;

    final int visibleBarCount = math.min(barCount, audioLevels.length);
    final double totalWidth = (barWidth + spacing) * visibleBarCount - spacing;
    final double startX = (size.width - totalWidth) / 2;

    final int playProgress = (visibleBarCount * progress).round();

    final double samplingRatio = audioLevels.length / visibleBarCount;

    for (int i = 0; i < visibleBarCount; i++) {
      double level;
      if (samplingRatio <= 1) {
        level = audioLevels[i % audioLevels.length];
      } else {
        int idx = (i * samplingRatio).floor();
        idx = idx.clamp(0, audioLevels.length - 1);
        level = audioLevels[idx];
      }

      double barHeight = size.height * level.clamp(0.1, 1.0);

      double left = startX + i * (barWidth + spacing);
      double top = (size.height - barHeight) / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth, barHeight),
        Radius.circular(borderRadius),
      );

      canvas.drawRRect(rect, i < playProgress ? playedBarPaint : barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant SimpleWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.barWidth != barWidth ||
        oldDelegate.spacing != spacing ||
        oldDelegate.borderRadius != borderRadius;
  }
}
