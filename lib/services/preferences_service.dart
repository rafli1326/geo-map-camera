import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/watermark_config.dart';

/// Photo aspect ratios offered in the camera. [ratio] is long edge / short edge.
enum CaptureAspect {
  r4x3('4:3', 4 / 3),
  r16x9('16:9', 16 / 9),
  r3x2('3:2', 3 / 2),
  r1x1('1:1', 1.0);

  final String label;
  final double ratio;
  const CaptureAspect(this.label, this.ratio);

  static CaptureAspect fromLabel(String? label) =>
      CaptureAspect.values.firstWhere((a) => a.label == label, orElse: () => CaptureAspect.r4x3);
}

class PreferencesService extends ChangeNotifier {
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService() => _instance;
  PreferencesService._internal();

  static const String _prefKey = 'watermark_config';
  static const String _flashKey = 'camera_flash';
  static const String _gridKey = 'camera_grid';
  static const String _zoomKey = 'camera_zoom';
  static const String _aspectKey = 'camera_aspect';

  WatermarkConfig _config = const WatermarkConfig();

  // Last-used camera settings (restored on next launch).
  String flashMode = 'off'; // off | torch | auto
  bool showGrid = false;
  double zoom = 1.0;
  CaptureAspect aspect = CaptureAspect.r4x3;

  WatermarkConfig get config => _config;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        _config = WatermarkConfig.fromJson(jsonStr);
      }
      flashMode = prefs.getString(_flashKey) ?? 'off';
      showGrid = prefs.getBool(_gridKey) ?? false;
      zoom = prefs.getDouble(_zoomKey) ?? 1.0;
      aspect = CaptureAspect.fromLabel(prefs.getString(_aspectKey));
    } catch (e) {
      debugPrint('Error loading preferences: $e');
    }
    notifyListeners();
  }

  Future<void> updateConfig(WatermarkConfig newConfig) async {
    _config = newConfig;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, newConfig.toJson());
    } catch (e) {
      debugPrint('Error saving preferences: $e');
    }
  }

  Future<void> saveCameraSettings({
    String? flashMode,
    bool? showGrid,
    double? zoom,
    CaptureAspect? aspect,
  }) async {
    if (flashMode != null) this.flashMode = flashMode;
    if (showGrid != null) this.showGrid = showGrid;
    if (zoom != null) this.zoom = zoom;
    if (aspect != null) this.aspect = aspect;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_flashKey, this.flashMode);
      await prefs.setBool(_gridKey, this.showGrid);
      await prefs.setDouble(_zoomKey, this.zoom);
      await prefs.setString(_aspectKey, this.aspect.label);
    } catch (e) {
      debugPrint('Error saving camera settings: $e');
    }
  }
}
