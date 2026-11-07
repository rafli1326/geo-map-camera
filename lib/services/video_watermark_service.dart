import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/gps_telemetry.dart';
import '../models/watermark_config.dart';
import 'map_tile_service.dart';
import 'watermark_burner.dart';

class VideoWatermarkService {
  static final VideoWatermarkService _instance = VideoWatermarkService._internal();
  factory VideoWatermarkService() => _instance;
  VideoWatermarkService._internal();

  static const MethodChannel _channel = MethodChannel('com.geomap.camera/video_watermark');

  Directory? _liveSessionDir;
  int _liveFrameWidth = 1080;
  int _liveFrameHeight = 1920;
  int _liveSampleIndex = 0;
  final List<String> _liveOverlayPaths = [];
  Future<void> _liveRenderChain = Future.value();
  Future<void> _burnQueue = Future.value();

  /// Starts a live overlay pre-rendering session when video recording begins.
  /// Each second's watermark strip is rendered in the background during recording
  /// so that pressing Stop starts Media3 hardware transcoding immediately (0 ms wait).
  Future<void> startLiveSession({
    int frameWidth = 1080,
    int frameHeight = 1920,
  }) async {
    await cancelLiveSession();
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(
      '${tempDir.path}/video_wm_${DateTime.now().millisecondsSinceEpoch}',
    );
    await dir.create(recursive: true);
    _liveSessionDir = dir;
    _liveFrameWidth = frameWidth > 0 ? frameWidth : 1080;
    _liveFrameHeight = frameHeight > 0 ? frameHeight : 1920;
    _liveSampleIndex = 0;
    _liveOverlayPaths.clear();
    _liveRenderChain = Future.value();
  }

  /// Enqueues one second's telemetry sample to be rendered into a cropped PNG strip
  /// while the camera is actively recording.
  void enqueueLiveSample({
    required GpsTelemetry telemetry,
    required WatermarkConfig config,
  }) {
    final sessionDir = _liveSessionDir;
    if (sessionDir == null) return;
    final int index = _liveSampleIndex++;
    final int width = _liveFrameWidth;
    final int height = _liveFrameHeight;

    _liveRenderChain = _liveRenderChain.then((_) async {
      if (_liveSessionDir?.path != sessionDir.path || !sessionDir.existsSync()) {
        return;
      }
      try {
        final pngPath = await _renderSingleOverlayStrip(
          dir: sessionDir,
          index: index,
          frameWidth: width,
          frameHeight: height,
          telemetry: telemetry,
          config: config,
        );
        if (_liveSessionDir?.path == sessionDir.path) {
          _liveOverlayPaths.add(pngPath);
        }
      } catch (e) {
        debugPrint('Live video overlay pre-render error (sec $index): $e');
      }
    });
  }

  /// Cancels and cleans up any active live pre-rendering session.
  Future<void> cancelLiveSession() async {
    final oldDir = _liveSessionDir;
    _liveSessionDir = null;
    _liveOverlayPaths.clear();
    _liveSampleIndex = 0;
    try {
      await _liveRenderChain;
    } catch (_) {}
    if (oldDir != null) {
      try {
        if (oldDir.existsSync()) {
          await oldDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Future<String> _renderSingleOverlayStrip({
    required Directory dir,
    required int index,
    required int frameWidth,
    required int frameHeight,
    required GpsTelemetry telemetry,
    required WatermarkConfig config,
  }) async {
    MiniMapTile? tile;
    if (config.showMiniMap &&
        (telemetry.latitude != 0.0 || telemetry.longitude != 0.0)) {
      final tileResult = await MapTileService().fetchTileResult(
        latitude: telemetry.latitude,
        longitude: telemetry.longitude,
      );
      tile = await WatermarkBurner().decodeTile(tileResult);
    }

    final pngBytes = await WatermarkBurner().renderBannerPng(
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      telemetry: telemetry,
      config: config,
      tile: tile,
    );

    final pngPath = '${dir.path}/overlay_$index.png';
    await File(pngPath).writeAsBytes(pngBytes, flush: false);
    return pngPath;
  }

  /// Burns dynamic per-second watermarks onto [rawVideoPath] and outputs to [outputPath].
  /// Uses pre-rendered live overlay strips if available, or renders any remaining samples.
  /// Runs sequentially on a background queue so multiple video exports never collide.
  Future<String> burnVideoWatermark({
    required String rawVideoPath,
    required String outputPath,
    required List<GpsTelemetry> samples,
    required WatermarkConfig config,
    int frameWidth = 1080,
    int frameHeight = 1920,
    int rotationDegrees = 0,
  }) {
    final completer = Completer<String>();
    _burnQueue = _burnQueue.then((_) async {
      try {
        final result = await _executeBurnVideoWatermark(
          rawVideoPath: rawVideoPath,
          outputPath: outputPath,
          samples: samples,
          config: config,
          frameWidth: frameWidth,
          frameHeight: frameHeight,
          rotationDegrees: rotationDegrees,
        );
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<String> _executeBurnVideoWatermark({
    required String rawVideoPath,
    required String outputPath,
    required List<GpsTelemetry> samples,
    required WatermarkConfig config,
    required int frameWidth,
    required int frameHeight,
    required int rotationDegrees,
  }) async {
    // Wait for any in-flight live pre-render task (typically < 15 ms for the final tick).
    try {
      await _liveRenderChain;
    } catch (_) {}

    Directory watermarkDir;
    final overlayPaths = <String>[];

    if (_liveSessionDir != null &&
        _liveSessionDir!.existsSync() &&
        _liveOverlayPaths.isNotEmpty) {
      watermarkDir = _liveSessionDir!;
      overlayPaths.addAll(_liveOverlayPaths);
      // Detach session so cleanup happens in finally block below
      _liveSessionDir = null;
      _liveOverlayPaths.clear();
      _liveSampleIndex = 0;
    } else {
      final tempDir = await getTemporaryDirectory();
      watermarkDir = Directory(
        '${tempDir.path}/video_wm_${DateTime.now().millisecondsSinceEpoch}',
      );
      await watermarkDir.create(recursive: true);
    }

    try {
      final effectiveSamples = samples.isNotEmpty
          ? samples
          : [GpsTelemetry(latitude: 0, longitude: 0, timestamp: DateTime.now())];

      final int targetW = frameWidth > 0 ? frameWidth : _liveFrameWidth;
      final int targetH = frameHeight > 0 ? frameHeight : _liveFrameHeight;

      // Only render remaining samples if any were not already pre-rendered live
      for (int i = overlayPaths.length; i < effectiveSamples.length; i++) {
        final pngPath = await _renderSingleOverlayStrip(
          dir: watermarkDir,
          index: i,
          frameWidth: targetW,
          frameHeight: targetH,
          telemetry: effectiveSamples[i],
          config: config,
        );
        overlayPaths.add(pngPath);
      }

      // Call Media3 Transformer on Android with lazy O(1) bitmap decoding
      final result = await _channel.invokeMethod<String>('burnWatermark', {
        'inputPath': rawVideoPath,
        'outputPath': outputPath,
        'overlayPaths': overlayPaths,
        'rotationDegrees': rotationDegrees,
      });

      return result ?? outputPath;
    } finally {
      try {
        if (watermarkDir.existsSync()) {
          await watermarkDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }
}
