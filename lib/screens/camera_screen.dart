import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';
import '../models/media_item.dart';
import '../models/gps_telemetry.dart';
import '../models/watermark_config.dart';
import '../services/location_service.dart';
import '../services/map_tile_service.dart';
import '../services/preferences_service.dart';
import '../services/storage_service.dart';
import '../services/video_watermark_service.dart';
import '../services/watermark_burner.dart';
import '../widgets/live_watermark_banner.dart';
import 'gallery_screen.dart';
import 'settings_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;

  // Flash, Grid, Zoom, Exposure, Aspect
  FlashMode _flashMode = FlashMode.off;
  bool _showGrid = false;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 4.0;
  double _baseScaleZoom = 1.0;
  double _exposureOffset = 0.0;
  double _minExposure = -2.0;
  double _maxExposure = 2.0;
  CaptureAspect _aspect = CaptureAspect.r4x3;

  // Focus & Exposure Lock
  bool _isFocusLocked = false;
  Offset? _focusPointScreen;
  Timer? _focusResetTimer;
  bool _showFocusReticle = false;

  // Photo & Video modes
  bool _isVideoMode = false;
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  final List<GpsTelemetry> _videoSamples = [];
  int _recordingRotation = 0;

  // Non-blocking capture queue & shutter flash
  int _pendingCapturesCount = 0;
  bool _showShutterFlash = false;

  // Top pop-up toast notification state (adapts to Portrait & Landscape top edge)
  String? _toastMessage;
  bool _toastIsError = false;
  Timer? _toastTimer;

  // Isolated live clock notifier (updates only the watermark widget, never rebuilds CameraScreen)
  Timer? _clockTimer;
  final ValueNotifier<DateTime> _clockNotifier =
      ValueNotifier<DateTime>(DateTime.now());

  // Sensor-based orientation tracking (window stays portraitUp; UI & watermark rotate in-place)
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  int _deviceRotationDegrees = 0;

  static const Color _accentYellow = Color(0xFFFACC15);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAppServices();
    _startClockTimer();
    _startOrientationTracking();
  }

  void _startClockTimer() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _clockNotifier.value = DateTime.now();
      }
    });
  }

  void _startOrientationTracking() {
    _accelSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 200),
    ).listen(
      (AccelerometerEvent event) {
        // Planar magnitude squared in device screen plane (X-Y)
        final double planarMagSq = event.x * event.x + event.y * event.y;
        // If device is lying nearly flat on a table (face up or down), do not fluctuate
        if (planarMagSq < 4.5) return;

        // Angle in degrees in device coordinate space:
        //  0°: upright portrait (y > 0, x ≈ 0)
        // -90°: counter-clockwise landscape (top of phone on left, x > 0)
        // +90°: clockwise landscape (top of phone on right, x < 0)
        final double angle = atan2(-event.x, event.y) * 180 / pi;

        int newRot = _deviceRotationDegrees;

        // Hysteresis thresholds to eliminate boundary jitter and prevent getting stuck
        if (_deviceRotationDegrees == 0) {
          if (angle < -55 && angle > -125) {
            newRot = -90;
          } else if (angle > 55 && angle < 125) {
            newRot = 90;
          }
        } else if (_deviceRotationDegrees == -90) {
          if (angle >= -35 && angle <= 35) {
            newRot = 0;
          } else if (angle > 55 && angle < 125) {
            newRot = 90;
          }
        } else if (_deviceRotationDegrees == 90) {
          if (angle >= -35 && angle <= 35) {
            newRot = 0;
          } else if (angle < -55 && angle > -125) {
            newRot = -90;
          }
        } else {
          if (angle >= -45 && angle <= 45) {
            newRot = 0;
          } else if (angle < -45 && angle > -135) {
            newRot = -90;
          } else if (angle > 45 && angle < 135) {
            newRot = 90;
          }
        }

        if (newRot != _deviceRotationDegrees && mounted) {
          setState(() {
            _deviceRotationDegrees = newRot;
          });
        }
      },
      onError: (_) {},
    );
  }

  Future<void> _lockControllerOrientation(int rot) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    try {
      DeviceOrientation orient;
      if (rot == -90) {
        orient = DeviceOrientation.landscapeLeft;
      } else if (rot == 90) {
        orient = DeviceOrientation.landscapeRight;
      } else if (rot == 180) {
        orient = DeviceOrientation.portraitDown;
      } else {
        orient = DeviceOrientation.portraitUp;
      }
      await _cameraController!.lockCaptureOrientation(orient);
    } catch (e) {
      debugPrint('Error locking capture orientation: $e');
    }
  }

  /// Fractional turns for rotating icons/buttons in-place when phone is tilted
  double get _uiTurns {
    if (_deviceRotationDegrees == -90) return 0.25; // +90° CW on screen
    if (_deviceRotationDegrees == 90) return -0.25; // -90° CCW on screen
    return 0.0;
  }

  Future<void> _initAppServices() async {
    final prefService = PreferencesService();
    await prefService.init();
    await StorageService().loadMediaItems();

    _aspect = prefService.aspect;
    _showGrid = prefService.showGrid;
    _currentZoom = prefService.zoom;
    switch (prefService.flashMode) {
      case 'torch':
        _flashMode = FlashMode.torch;
        break;
      case 'auto':
        _flashMode = FlashMode.auto;
        break;
      default:
        _flashMode = FlashMode.off;
        break;
    }

    await LocationService().init();
    await _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      await _setupCameraController(_cameras[_selectedCameraIndex]);
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _setupCameraController(CameraDescription cameraDesc) async {
    final prevController = _cameraController;
    final controller = CameraController(
      cameraDesc,
      ResolutionPreset.veryHigh,
      enableAudio: true,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.jpeg : ImageFormatGroup.bgra8888,
    );

    await prevController?.dispose();

    try {
      await controller.initialize();
      try {
        await controller.setFlashMode(_flashMode);
      } catch (_) {}

      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = (await controller.getMaxZoomLevel()).clamp(1.0, 5.0);
      final clampedZoom = _currentZoom.clamp(_minZoom, _maxZoom);
      try {
        await controller.setZoomLevel(clampedZoom);
      } catch (_) {}

      try {
        final minExp = await controller.getMinExposureOffset();
        final maxExp = await controller.getMaxExposureOffset();
        if (minExp < maxExp) {
          _minExposure = minExp;
          _maxExposure = maxExp;
        }
        _exposureOffset = 0.0;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _cameraController = controller;
          _isCameraInitialized = true;
          _currentZoom = clampedZoom;
        });
        unawaited(_lockControllerOrientation(0));
      }
    } catch (e) {
      debugPrint('Error creating camera controller: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _setupCameraController(cameraController.description);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _clockNotifier.dispose();
    _recordTimer?.cancel();
    _focusResetTimer?.cancel();
    _toastTimer?.cancel();
    _accelSubscription?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length < 2) return;
    HapticFeedback.selectionClick();
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    _focusResetTimer?.cancel();
    setState(() {
      _isCameraInitialized = false;
      _isFocusLocked = false;
      _showFocusReticle = false;
      _focusPointScreen = null;
    });
    await _setupCameraController(_cameras[_selectedCameraIndex]);
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    HapticFeedback.selectionClick();

    FlashMode nextMode;
    switch (_flashMode) {
      case FlashMode.off:
        nextMode = FlashMode.torch;
        break;
      case FlashMode.torch:
        nextMode = FlashMode.auto;
        break;
      case FlashMode.auto:
      default:
        nextMode = FlashMode.off;
        break;
    }

    try {
      await _cameraController!.setFlashMode(nextMode);
      setState(() => _flashMode = nextMode);
      String flashStr = 'off';
      if (nextMode == FlashMode.torch) flashStr = 'torch';
      if (nextMode == FlashMode.auto) flashStr = 'auto';
      PreferencesService().saveCameraSettings(flashMode: flashStr);
    } catch (e) {
      debugPrint('Flash error: $e');
    }
  }

  Future<void> _setZoom(double zoom) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    final clamped = zoom.clamp(_minZoom, _maxZoom);
    try {
      await _cameraController!.setZoomLevel(clamped);
      setState(() => _currentZoom = clamped);
      PreferencesService().saveCameraSettings(zoom: clamped);
    } catch (e) {
      debugPrint('Zoom error: $e');
    }
  }

  Future<void> _setExposure(double value) async {
    final clamped = value.clamp(_minExposure, _maxExposure);
    setState(() => _exposureOffset = clamped);
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    try {
      if (_isFocusLocked) {
        await _cameraController!.setExposureMode(ExposureMode.auto);
      }
      await _cameraController!.setExposureOffset(clamped);
    } catch (_) {}
  }

  void _cycleAspectRatio() {
    HapticFeedback.selectionClick();
    final values = CaptureAspect.values;
    final currentIndex = values.indexOf(_aspect);
    final nextAspect = values[(currentIndex + 1) % values.length];
    setState(() => _aspect = nextAspect);
    PreferencesService().saveCameraSettings(aspect: nextAspect);
    _showToast('Rasio Kamera: ${nextAspect.label}');
  }

  // ---------------------------------------------------------------------------
  // FOCUS & EXPOSURE LOCK (AF/AE LOCK)
  // ---------------------------------------------------------------------------
  Future<void> _handleTapToFocus(Offset localPosition, double boxW, double boxH) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    final nx = (localPosition.dx / boxW).clamp(0.0, 1.0);
    final ny = (localPosition.dy / boxH).clamp(0.0, 1.0);
    final point = Offset(nx, ny);

    _focusResetTimer?.cancel();
    HapticFeedback.selectionClick();

    setState(() {
      _focusPointScreen = localPosition;
      _showFocusReticle = true;
    });

    try {
      await _cameraController!.setFocusPoint(point);
    } catch (_) {}
    try {
      await _cameraController!.setExposurePoint(point);
    } catch (_) {}

    if (!_isFocusLocked) {
      _focusResetTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted && !_isFocusLocked) {
          setState(() {
            _showFocusReticle = false;
          });
        }
      });
    }
  }

  Future<void> _lockFocus({Offset? screenPosition, double? boxW, double? boxH}) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    _focusResetTimer?.cancel();
    HapticFeedback.heavyImpact();

    Offset point = const Offset(0.5, 0.5);
    Offset screenPt = screenPosition ??
        Offset(boxW != null ? boxW / 2 : 180, boxH != null ? boxH / 2 : 240);

    if (screenPosition != null && boxW != null && boxH != null) {
      final nx = (screenPosition.dx / boxW).clamp(0.0, 1.0);
      final ny = (screenPosition.dy / boxH).clamp(0.0, 1.0);
      point = Offset(nx, ny);
      screenPt = screenPosition;
    }

    try {
      await _cameraController!.setFocusPoint(point);
    } catch (_) {}
    try {
      await _cameraController!.setExposurePoint(point);
    } catch (_) {}
    try {
      await _cameraController!.setFocusMode(FocusMode.locked);
    } catch (_) {}
    try {
      await _cameraController!.setExposureMode(ExposureMode.locked);
    } catch (_) {}

    setState(() {
      _isFocusLocked = true;
      _focusPointScreen = screenPt;
      _showFocusReticle = true;
    });

    _showToast('Fokus & Eksposur Terkunci (AF/AE Lock)');
  }

  Future<void> _unlockFocus() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    _focusResetTimer?.cancel();
    HapticFeedback.selectionClick();

    try {
      await _cameraController!.setFocusMode(FocusMode.auto);
    } catch (_) {}
    try {
      await _cameraController!.setExposureMode(ExposureMode.auto);
    } catch (_) {}
    try {
      await _cameraController!.setFocusPoint(null);
    } catch (_) {}
    try {
      await _cameraController!.setExposurePoint(null);
    } catch (_) {}
    try {
      await _cameraController!.setExposureOffset(0.0);
    } catch (_) {}

    setState(() {
      _isFocusLocked = false;
      _showFocusReticle = false;
      _exposureOffset = 0.0;
    });

    _showToast('Kunci Fokus Dilepas (Auto Focus)');
  }

  Future<void> _toggleFocusLock({double? boxW, double? boxH}) async {
    if (_isFocusLocked) {
      await _unlockFocus();
    } else {
      await _lockFocus(boxW: boxW, boxH: boxH);
    }
  }

  // ---------------------------------------------------------------------------
  // QUICK NOTE DIALOG (Top Bar Icon #3)
  // ---------------------------------------------------------------------------
  void _showQuickNoteDialog() {
    final currentConfig = PreferencesService().config;
    final noteCtrl = TextEditingController(text: currentConfig.projectTitle);
    final officerCtrl = TextEditingController(text: currentConfig.officerName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.edit_note, color: _accentYellow, size: 22),
            SizedBox(width: 8),
            Text(
              'Catatan Watermark (Note)',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: noteCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                labelText: 'Note / Nama Kegiatan',
                labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: officerCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                labelText: 'Nama Petugas (Opsional)',
                labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentYellow,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              PreferencesService().updateConfig(
                currentConfig.copyWith(
                  projectTitle: noteCtrl.text.trim().isEmpty
                      ? 'Dokumentasi Lapangan'
                      : noteCtrl.text.trim(),
                  officerName: officerCtrl.text.trim(),
                  showProjectTitle: true,
                ),
              );
              Navigator.pop(ctx);
              _showToast('Catatan watermark diperbarui');
            },
            child: const Text('Simpan', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LOCATIONS MODAL SHEET ("Lokasi" Bottom Button)
  // ---------------------------------------------------------------------------
  void _showLocationDetailsSheet(LocationService locationService, GpsTelemetry telemetry) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141417),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.satellite_alt,
                    color: locationService.hasFix ? const Color(0xFF4EDEA3) : _accentYellow,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      locationService.hasFix
                          ? 'Data Lokasi GPS Aktif (${telemetry.formattedAccuracy})'
                          : locationService.statusMessage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(
                          text:
                              '${telemetry.locationHeader}\n${telemetry.fullAddressLine}\n${telemetry.latLongLineDecimal}',
                        ),
                      );
                      Navigator.pop(ctx);
                      _showToast('Koordinat & alamat disalin!');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 15, color: _accentYellow),
                    label: const Text(
                      'Salin',
                      style: TextStyle(
                        color: _accentYellow,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 22),
              _buildLocationDetailRow('Header Lokasi', telemetry.locationHeader),
              const SizedBox(height: 8),
              _buildLocationDetailRow('Alamat Lengkap', telemetry.fullAddressLine),
              const SizedBox(height: 8),
              _buildLocationDetailRow('Koordinat', telemetry.latLongLineDecimal),
              const SizedBox(height: 8),
              _buildLocationDetailRow('Ketinggian', telemetry.formattedAltitude),
              const SizedBox(height: 8),
              _buildLocationDetailRow('Waktu GMT', telemetry.dateTimeGmtLine),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // NON-BLOCKING PHOTO CAPTURE
  // ---------------------------------------------------------------------------
  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (LocationService().isMocked) {
      HapticFeedback.vibrate();
      _showToast('Pengambilan ditolak: Lokasi palsu (Mock GPS) terdeteksi!', isError: true);
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _showShutterFlash = true);
    Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _showShutterFlash = false);
    });

    try {
      final XFile photoFile = await _cameraController!.takePicture();
      final Uint8List rawBytes = await photoFile.readAsBytes();

      try {
        await File(photoFile.path).delete();
      } catch (_) {}

      final bool isFront =
          _cameras[_selectedCameraIndex].lensDirection == CameraLensDirection.front;
      final bool hasFix =
          LocationService().hasFix && !LocationService().isMocked;
      final telemetry =
          LocationService().currentTelemetry.copyWith(timestamp: DateTime.now());
      final config = PreferencesService().config;
      final effectiveConfig = hasFix ? config : config.withoutLocation();
      final double targetAspect = _aspect.ratio;
      final int captureRotation = _deviceRotationDegrees;

      setState(() => _pendingCapturesCount++);
      _processPhotoInBackground(
        rawBytes: rawBytes,
        telemetry: telemetry,
        config: effectiveConfig,
        rotationDegrees: captureRotation,
        mirror: isFront,
        aspectRatio: targetAspect,
        includeGpsExif: hasFix,
      );
    } catch (e, stack) {
      debugPrint('Capture error: $e\n$stack');
      _showToast('Gagal memotret: $e', isError: true);
    }
  }

  void _processPhotoInBackground({
    required Uint8List rawBytes,
    required GpsTelemetry telemetry,
    required WatermarkConfig config,
    required int rotationDegrees,
    required bool mirror,
    required double aspectRatio,
    required bool includeGpsExif,
  }) async {
    try {
      MapTileResult? mapTileResult;
      if (config.showMiniMap && telemetry.latitude != 0) {
        mapTileResult = await MapTileService().fetchTileResult(
          latitude: telemetry.latitude,
          longitude: telemetry.longitude,
        );
      }

      final Uint8List stampedJpgBytes = await WatermarkBurner().burnWatermark(
        photoBytes: rawBytes,
        telemetry: telemetry,
        config: config,
        mapTileResult: mapTileResult,
        rotationDegrees: rotationDegrees,
        mirror: mirror,
        aspectRatio: aspectRatio,
        includeGpsExif: includeGpsExif,
      );

      await StorageService().savePhoto(stampedJpgBytes);
    } catch (e, stack) {
      debugPrint('Background watermark burn error: $e\n$stack');
      _showToast('Gagal memproses watermark: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          if (_pendingCapturesCount > 0) _pendingCapturesCount--;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // VIDEO RECORDING WITH DYNAMIC GPS WATERMARK (Non-Blocking Background Processing)
  // ---------------------------------------------------------------------------
  Future<void> _toggleVideoRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    if (_isRecording) {
      HapticFeedback.heavyImpact();
      _recordTimer?.cancel();

      try {
        final XFile videoFile = await _cameraController!.stopVideoRecording();
        unawaited(_lockControllerOrientation(0));
        final rawVideoPath = videoFile.path;
        final samples = List<GpsTelemetry>.from(_videoSamples);
        final hasFix = LocationService().hasFix;
        final config = PreferencesService().config;
        final effectiveConfig = hasFix ? config : config.withoutLocation();
        final recRotation = _recordingRotation;
        final previewSize = _cameraController?.value.previewSize;

        setState(() {
          _isRecording = false;
          _recordSeconds = 0;
          _pendingCapturesCount++;
        });

        _showToast('Video tersimpan! Memproses stempel di latar belakang...');

        _processVideoInBackground(
          rawVideoPath: rawVideoPath,
          samples: samples,
          config: effectiveConfig,
          rotationDegrees: recRotation,
          previewSize: previewSize,
        );
      } catch (e) {
        unawaited(_lockControllerOrientation(0));
        debugPrint('Error stopping video recording: $e');
        _showToast('Gagal menghentikan perekaman: $e', isError: true);
        if (mounted) {
          setState(() {
            _isRecording = false;
            _recordSeconds = 0;
          });
        }
      }
    } else {
      if (LocationService().isMocked) {
        HapticFeedback.vibrate();
        _showToast('Perekaman ditolak: Lokasi palsu (Mock GPS) terdeteksi!', isError: true);
        return;
      }

      HapticFeedback.mediumImpact();
      try {
        _recordingRotation = _deviceRotationDegrees;
        await _lockControllerOrientation(_recordingRotation);

        final bool isLandscape =
            _recordingRotation == -90 || _recordingRotation == 90;
        final previewSize = _cameraController!.value.previewSize;
        final int videoWidth = previewSize != null
            ? (isLandscape
                ? max(previewSize.width, previewSize.height).toInt()
                : min(previewSize.width, previewSize.height).toInt())
            : (isLandscape ? 1920 : 1080);
        final int videoHeight = previewSize != null
            ? (isLandscape
                ? min(previewSize.width, previewSize.height).toInt()
                : max(previewSize.width, previewSize.height).toInt())
            : (isLandscape ? 1080 : 1920);

        _videoSamples.clear();
        await VideoWatermarkService().startLiveSession(
          frameWidth: videoWidth,
          frameHeight: videoHeight,
        );

        void recordSampleTick() {
          final sample =
              LocationService().currentTelemetry.copyWith(timestamp: DateTime.now());
          _videoSamples.add(sample);
          final isMocked = LocationService().isMocked;
          final hasFix = LocationService().hasFix && !isMocked;
          final cfg = PreferencesService().config;
          VideoWatermarkService().enqueueLiveSample(
            telemetry: sample,
            config: hasFix ? cfg : cfg.withoutLocation(),
          );
        }

        recordSampleTick();
        await _cameraController!.startVideoRecording();

        setState(() {
          _isRecording = true;
          _recordSeconds = 0;
        });

        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            recordSampleTick();
            setState(() => _recordSeconds++);
          }
        });
      } catch (e) {
        unawaited(_lockControllerOrientation(0));
        unawaited(VideoWatermarkService().cancelLiveSession());
        debugPrint('Error starting video: $e');
        _showToast('Gagal memulai perekaman video', isError: true);
      }
    }
  }

  void _processVideoInBackground({
    required String rawVideoPath,
    required List<GpsTelemetry> samples,
    required WatermarkConfig config,
    required int rotationDegrees,
    required Size? previewSize,
  }) async {
    try {
      final bool isLandscape = rotationDegrees == -90 || rotationDegrees == 90;
      final int videoWidth = previewSize != null
          ? (isLandscape
              ? max(previewSize.width, previewSize.height).toInt()
              : min(previewSize.width, previewSize.height).toInt())
          : (isLandscape ? 1920 : 1080);
      final int videoHeight = previewSize != null
          ? (isLandscape
              ? min(previewSize.width, previewSize.height).toInt()
              : max(previewSize.width, previewSize.height).toInt())
          : (isLandscape ? 1080 : 1920);

      await StorageService().saveWatermarkedVideo(
        rawVideoPath: rawVideoPath,
        samples: samples,
        config: config,
        frameWidth: videoWidth,
        frameHeight: videoHeight,
        rotationDegrees: rotationDegrees,
      );
    } catch (e, stack) {
      debugPrint('Background video watermark burn error: $e\n$stack');
      _showToast('Gagal memproses stempel video: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          if (_pendingCapturesCount > 0) _pendingCapturesCount--;
        });
      }
    }
  }

  void _shareLatestMedia(MediaItem? lastMedia) {
    HapticFeedback.selectionClick();
    if (lastMedia == null || !File(lastMedia.path).existsSync()) {
      _showToast('Belum ada foto/video untuk dibagikan', isError: true);
      return;
    }
    SharePlus.instance.share(
      ShareParams(
        files: [XFile(lastMedia.path)],
        text: 'Dokumentasi Geo Map Camera: ${lastMedia.name}',
      ),
    );
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    _toastTimer?.cancel();
    setState(() {
      _toastMessage = message;
      _toastIsError = isError;
    });
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _toastMessage = null;
        });
      }
    });
  }

  String _formatTimer(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final locationService = LocationService();
    final prefService = PreferencesService();
    final storageService = StorageService();

    return ListenableBuilder(
      listenable: Listenable.merge([locationService, prefService, storageService]),
      builder: (context, _) {
        final telemetry = locationService.currentTelemetry;
        final baseConfig = prefService.config;
        final effectiveConfig =
            locationService.hasFix ? baseConfig : baseConfig.withoutLocation();
        final lastMedia = storageService.lastSavedItem;

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  // 1. Top Black Action Bar (6 icons)
                  _buildTopBlackBar(),

                  // 2. Full Portrait-Framed Viewfinder (never shrinks in landscape!)
                  Expanded(
                    child: _buildViewfinder(telemetry, effectiveConfig),
                  ),

                  // 3. Bottom Black Control Deck
                  _buildBottomControlDeck(locationService, telemetry, lastMedia),
                ],
              ),

              // Instant Shutter Flash Animation (120ms)
              if (_showShutterFlash)
                IgnorePointer(
                  child: Container(color: Colors.white.withValues(alpha: 0.85)),
                ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 1. TOP BLACK ACTION BAR (6 white outline icons rotating in-place)
  // ---------------------------------------------------------------------------
  Widget _buildTopBlackBar() {
    IconData flashIcon;
    Color flashColor = Colors.white;
    switch (_flashMode) {
      case FlashMode.torch:
        flashIcon = Icons.flash_on;
        flashColor = _accentYellow;
        break;
      case FlashMode.auto:
        flashIcon = Icons.flash_auto;
        flashColor = _accentYellow;
        break;
      case FlashMode.off:
      default:
        flashIcon = Icons.flash_off_outlined;
        break;
    }

    return Container(
      color: Colors.black,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // 1. Aspect Ratio / Aperture Icon
              _buildTopBarIconButton(
                onTap: _cycleAspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.camera_outlined, color: Colors.white, size: 25),
                    Positioned(
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: Colors.white38, width: 0.6),
                        ),
                        child: Text(
                          _aspect.label,
                          style: const TextStyle(
                            color: _accentYellow,
                            fontSize: 7.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Flash Icon
              _buildTopBarIconButton(
                onTap: _toggleFlash,
                child: Icon(flashIcon, color: flashColor, size: 25),
              ),

              // 3. Focus Lock Icon (Kunci Fokus)
              _buildTopBarIconButton(
                onTap: _toggleFocusLock,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      _isFocusLocked ? Icons.lock : Icons.filter_center_focus_outlined,
                      color: _isFocusLocked ? _accentYellow : Colors.white,
                      size: 25,
                    ),
                    if (_isFocusLocked)
                      Positioned(
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: _accentYellow, width: 0.6),
                          ),
                          child: const Text(
                            'AF',
                            style: TextStyle(
                              color: _accentYellow,
                              fontSize: 7.0,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // 4. Quick Note Icon
              _buildTopBarIconButton(
                onTap: _showQuickNoteDialog,
                child: const Icon(Icons.note_add_outlined, color: Colors.white, size: 25),
              ),

              // 4. Grid / Map Framing Overlay Toggle
              _buildTopBarIconButton(
                onTap: () {
                  HapticFeedback.selectionClick();
                  final next = !_showGrid;
                  setState(() => _showGrid = next);
                  PreferencesService().saveCameraSettings(showGrid: next);
                },
                child: Icon(
                  Icons.grid_on_outlined,
                  color: _showGrid ? _accentYellow : Colors.white,
                  size: 24,
                ),
              ),

              // 5. Flip Camera Icon
              _buildTopBarIconButton(
                onTap: _toggleCamera,
                child: const Icon(Icons.flip_camera_android_outlined, color: Colors.white, size: 25),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBarIconButton({
    required VoidCallback onTap,
    required Widget child,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: AnimatedRotation(
          turns: _uiTurns,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: child,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. VIEWFINDER (Portrait-framed, with in-place rotating floating watermark)
  // ---------------------------------------------------------------------------
  Widget _buildViewfinder(GpsTelemetry telemetry, WatermarkConfig config) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;

        // Always keep viewfinder in portrait aspect ratio (e.g. 3:4 for 4:3)
        // so the preview fills the screen and NEVER shrinks when tilting!
        final double targetRatio = 1.0 / _aspect.ratio;

        double boxW = maxW;
        double boxH = maxW / targetRatio;
        if (boxH > maxH) {
          boxH = maxH;
          boxW = maxH * targetRatio;
        }

        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: SizedBox(
            width: boxW,
            height: boxH,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Camera Sensor Preview (Tap-to-Focus & Long-press to Lock)
                  _buildCameraPreview(boxW, boxH),

                  // Rule-of-Thirds Grid Overlay
                  if (_showGrid) _buildGridOverlay(),

                  // Dynamic Focus / Lock Reticle (Visual indicator at tapped location)
                  _buildFocusReticle(boxW, boxH),

                  // Top Pop-Up Notifications, AF Lock Pill & REC Indicator
                  // (Automatically positioned at the TOP in both Portrait & Landscape without clipping!)
                  _buildTopStatusAndToastOverlay(),

                  // Vertical Brightness / Exposure Slider (Only visible when AF/AE Lock is active)
                  if (_isFocusLocked)
                    Positioned(
                      right: _deviceRotationDegrees == 90 ? null : 6,
                      left: _deviceRotationDegrees == 90 ? 6 : null,
                      top: 0,
                      bottom: 48,
                      child: Center(
                        child: _buildVerticalExposureSlider(),
                      ),
                    ),

                  // Floating Live Watermark (rotates in-place in landscape!)
                  _buildResponsiveWatermarkOverlay(telemetry, config),

                  // Bottom-Center 1x / 2x Zoom Buttons
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 8,
                    child: Center(
                      child: _buildZoomCircleButtons(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildResponsiveWatermarkOverlay(
    GpsTelemetry telemetry,
    WatermarkConfig config,
  ) {
    final banner = IgnorePointer(
      child: RepaintBoundary(
        child: ValueListenableBuilder<DateTime>(
          valueListenable: _clockNotifier,
          builder: (context, now, _) => LiveWatermarkBanner(
            telemetry: telemetry.copyWith(timestamp: now),
            config: config,
          ),
        ),
      ),
    );

    if (_deviceRotationDegrees == -90) {
      // Landscape CCW (top of phone on left, right edge pointing up — matches Reference Screenshots 1 & 2)
      return Positioned(
        left: 10,
        top: 14,
        bottom: 50,
        child: Align(
          alignment: Alignment.centerLeft,
          child: RotatedBox(
            quarterTurns: 1,
            child: banner,
          ),
        ),
      );
    } else if (_deviceRotationDegrees == 90) {
      // Landscape CW (top of phone on right, left edge pointing up)
      return Positioned(
        right: 10,
        top: 14,
        bottom: 50,
        child: Align(
          alignment: Alignment.centerRight,
          child: RotatedBox(
            quarterTurns: 3,
            child: banner,
          ),
        ),
      );
    }

    // Portrait Up (matches Reference Screenshot 3)
    return Positioned(
      left: 10,
      right: 10,
      bottom: 50,
      child: banner,
    );
  }

  Widget _buildCameraPreview(double width, double height) {
    if (!_isCameraInitialized ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(_accentYellow),
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    final previewSize = _cameraController!.value.previewSize!;
    final double previewW = previewSize.height;
    final double previewH = previewSize.width;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        _handleTapToFocus(details.localPosition, width, height);
      },
      onLongPressStart: (details) {
        _lockFocus(screenPosition: details.localPosition, boxW: width, boxH: height);
      },
      onScaleStart: (_) {
        _baseScaleZoom = _currentZoom;
      },
      onScaleUpdate: (details) {
        if (details.scale != 1.0) {
          final target = (_baseScaleZoom * details.scale).clamp(_minZoom, _maxZoom);
          _setZoom(target);
        }
      },
      child: SizedBox(
        width: width,
        height: height,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewW,
            height: previewH,
            child: _cameraController!.buildPreview(),
          ),
        ),
      ),
    );
  }

  Widget _buildTopStatusAndToastOverlay() {
    if (!_isRecording && !_isFocusLocked && _toastMessage == null) {
      return const SizedBox.shrink();
    }

    final pills = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_toastMessage != null)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            constraints: const BoxConstraints(maxWidth: 290),
            decoration: BoxDecoration(
              color: const Color(0xEB18181B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _toastIsError ? const Color(0x99EF4444) : const Color(0x66FACC15),
                width: 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _toastIsError ? Icons.error_outline : Icons.check_circle,
                  color: _toastIsError ? const Color(0xFFFFB4AB) : _accentYellow,
                  size: 16,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    _toastMessage!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (_isRecording)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xD97F1D1D),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFEF4444), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  'REC  ${_formatTimer(_recordSeconds)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        if (_isFocusLocked)
          GestureDetector(
            onTap: _unlockFocus,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xEBFACC15),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, color: Colors.black, size: 13.5),
                  SizedBox(width: 5),
                  Text(
                    'AF KUNCI  •  Ketuk untuk lepas',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    if (_deviceRotationDegrees == -90) {
      // Landscape CCW: Top of the user's landscape view is the RIGHT edge of the portrait viewfinder
      return Positioned(
        right: 40,
        top: 16,
        bottom: 54,
        child: Align(
          alignment: Alignment.centerRight,
          child: RotatedBox(
            quarterTurns: 1,
            child: pills,
          ),
        ),
      );
    } else if (_deviceRotationDegrees == 90) {
      // Landscape CW: Top of the user's landscape view is the LEFT edge of the portrait viewfinder
      return Positioned(
        left: 40,
        top: 16,
        bottom: 54,
        child: Align(
          alignment: Alignment.centerLeft,
          child: RotatedBox(
            quarterTurns: 3,
            child: pills,
          ),
        ),
      );
    }

    // Portrait Up: Top of the user's view is the TOP edge of the viewfinder
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Align(
        alignment: Alignment.topCenter,
        child: pills,
      ),
    );
  }

  Widget _buildFocusReticle(double boxW, double boxH) {
    if (!_showFocusReticle || _focusPointScreen == null) {
      return const SizedBox.shrink();
    }

    const double reticleSize = 64.0;
    final double left =
        (_focusPointScreen!.dx - reticleSize / 2).clamp(6.0, boxW - reticleSize - 6.0);
    final double top =
        (_focusPointScreen!.dy - reticleSize / 2).clamp(6.0, boxH - reticleSize - 6.0);

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: AnimatedRotation(
          turns: _uiTurns,
          duration: const Duration(milliseconds: 220),
          child: TweenAnimationBuilder<double>(
            key: ValueKey('${_focusPointScreen!.dx}_${_focusPointScreen!.dy}_$_isFocusLocked'),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            tween: Tween(begin: 1.35, end: 1.0),
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isFocusLocked)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: _accentYellow,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 4),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock, size: 9.5, color: Colors.black),
                        SizedBox(width: 3),
                        Text(
                          'AF/AE LOCK',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                CustomPaint(
                  size: const Size(reticleSize, reticleSize),
                  painter: _FocusReticlePainter(
                    color: _accentYellow,
                    isLocked: _isFocusLocked,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalExposureSlider() {
    return SizedBox(
      width: 34,
      height: 195,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.0,
                activeTrackColor: _accentYellow,
                inactiveTrackColor: Colors.white70,
                thumbColor: Colors.transparent,
                overlayColor: Colors.transparent,
                thumbShape: const _SunSliderThumbShape(),
              ),
              child: Slider(
                value: _exposureOffset.clamp(_minExposure, _maxExposure),
                min: _minExposure,
                max: _maxExposure,
                onChanged: _setExposure,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomCircleButtons() {
    final bool is1x = _currentZoom < 1.8;
    final bool is2x = _currentZoom >= 1.8;

    Widget buildBtn(String label, double targetZoom, bool active) {
      return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _setZoom(targetZoom);
        },
        child: AnimatedRotation(
          turns: _uiTurns,
          duration: const Duration(milliseconds: 220),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? _accentYellow : const Color(0x88000000),
              shape: BoxShape.circle,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: active ? Colors.black : Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        buildBtn('1x', 1.0, is1x),
        const SizedBox(width: 8),
        buildBtn('2x', 2.0, is2x),
      ],
    );
  }

  Widget _buildGridOverlay() {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GridPainter(),
        size: Size.infinite,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. BOTTOM BLACK CONTROL DECK (Zero Redundancy: Galeri, Lokasi, Shutter, Bagikan, Stempel)
  // ---------------------------------------------------------------------------
  Widget _buildBottomControlDeck(
    LocationService locationService,
    GpsTelemetry telemetry,
    MediaItem? lastMedia,
  ) {
    final totalMediaCount = StorageService().mediaItems.length;

    return Container(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 14, left: 8, right: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Clean 2-Mode Selector Row: FOTO | VIDEO
              _buildModeSelectorRow(),
              const SizedBox(height: 14),

              // 5 Distinct Action Items: Galeri | Lokasi | Shutter | Bagikan | Stempel
              // Fixed 58x58 square containers prevent adjacent items from colliding when rotated 90° in landscape
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 58,
                    height: 58,
                    child: Center(child: _buildGalleryItem(lastMedia, totalMediaCount)),
                  ),
                  SizedBox(
                    width: 58,
                    height: 58,
                    child: Center(child: _buildLocationsItem(locationService, telemetry)),
                  ),
                  _buildShutterButton(),
                  SizedBox(
                    width: 58,
                    height: 58,
                    child: Center(child: _buildShareItem(lastMedia)),
                  ),
                  SizedBox(
                    width: 58,
                    height: 58,
                    child: Center(child: _buildWatermarkSettingsItem()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelectorRow() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // FOTO
          GestureDetector(
            onTap: () {
              if (_isRecording) return;
              HapticFeedback.selectionClick();
              setState(() => _isVideoMode = false);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
              decoration: BoxDecoration(
                color: !_isVideoMode ? _accentYellow : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'FOTO',
                style: TextStyle(
                  color: !_isVideoMode ? Colors.black : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // VIDEO
          GestureDetector(
            onTap: () {
              if (_isRecording) return;
              HapticFeedback.selectionClick();
              setState(() => _isVideoMode = true);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
              decoration: BoxDecoration(
                color: _isVideoMode ? _accentYellow : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'VIDEO',
                style: TextStyle(
                  color: _isVideoMode ? Colors.black : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGalleryItem(MediaItem? lastMedia, int totalCount) {
    final bool hasFile = lastMedia != null && File(lastMedia.path).existsSync();

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const GalleryScreen()),
        );
      },
      child: AnimatedRotation(
        turns: _uiTurns,
        duration: const Duration(milliseconds: 220),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    color: const Color(0xFF1F2937),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasFile
                      ? (lastMedia.isVideo
                          ? const Icon(Icons.play_arrow, color: Colors.white, size: 20)
                          : Image.file(
                              File(lastMedia.path),
                              fit: BoxFit.cover,
                              cacheWidth: 120,
                            ))
                      : const Icon(Icons.photo_library_outlined, color: Colors.white70, size: 18),
                ),
                if (totalCount > 0)
                  Positioned(
                    right: -4,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                      decoration: BoxDecoration(
                        color: _accentYellow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black, width: 1.2),
                      ),
                      child: Text(
                        totalCount > 99 ? '99+' : '$totalCount',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            const Text(
              'Galeri',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationsItem(LocationService locationService, GpsTelemetry telemetry) {
    final bool hasFix = locationService.hasFix;

    return GestureDetector(
      onTap: () => _showLocationDetailsSheet(locationService, telemetry),
      child: AnimatedRotation(
        turns: _uiTurns,
        duration: const Duration(milliseconds: 220),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                  Positioned(
                    right: 3,
                    top: 4,
                    child: Container(
                      width: 7.5,
                      height: 7.5,
                      decoration: BoxDecoration(
                        color: hasFix ? const Color(0xFF4EDEA3) : _accentYellow,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Lokasi',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShutterButton() {
    return GestureDetector(
      onTap: () {
        if (_isVideoMode) {
          _toggleVideoRecording();
        } else {
          _capturePhoto();
        }
      },
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 3.5,
              ),
            ),
            padding: const EdgeInsets.all(4.5),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isVideoMode ? Colors.black : _accentYellow,
              ),
              child: Center(
                child: _isVideoMode
                    ? AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: _isRecording ? 24 : 20,
                        height: _isRecording ? 24 : 20,
                        decoration: BoxDecoration(
                          color: _isRecording ? const Color(0xFFEF4444) : Colors.white,
                          borderRadius: BorderRadius.circular(_isRecording ? 5 : 20),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),

          // Background photo encoding queue counter badge
          if (_pendingCapturesCount > 0)
            Positioned(
              right: -2,
              top: -2,
              child: AnimatedRotation(
                turns: _uiTurns,
                duration: const Duration(milliseconds: 220),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  child: Text(
                    '$_pendingCapturesCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildShareItem(MediaItem? lastMedia) {
    final bool hasFile = lastMedia != null && File(lastMedia.path).existsSync();

    return GestureDetector(
      onTap: () => _shareLatestMedia(lastMedia),
      child: AnimatedRotation(
        turns: _uiTurns,
        duration: const Duration(milliseconds: 220),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                Icons.share_outlined,
                color: hasFile ? Colors.white : Colors.white38,
                size: 26,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Bagikan',
              style: TextStyle(
                color: hasFile ? Colors.white : Colors.white38,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWatermarkSettingsItem() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      },
      child: AnimatedRotation(
        turns: _uiTurns,
        duration: const Duration(milliseconds: 220),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                Icons.dashboard_customize_outlined,
                color: Colors.white,
                size: 27,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Stempel',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom SliderThumbShape that draws a white sun icon ("☀️") along the vertical exposure track
class _SunSliderThumbShape extends SliderComponentShape {
  const _SunSliderThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(26, 26);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    // Dark backing circle so the sun icon is crisp over bright backgrounds
    canvas.drawCircle(
      center,
      11,
      Paint()..color = const Color(0x66000000),
    );

    final sunPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    // Center sun core
    canvas.drawCircle(center, 4.2, sunPaint);

    // 8 sun rays
    for (int i = 0; i < 8; i++) {
      final Offset p1 = Offset(
        center.dx + 6.5 * (i.isEven ? 1.0 : 0.7071) * (i == 0 ? 1 : (i == 4 ? -1 : (i < 4 ? (i == 2 ? 0 : (i == 1 ? 1 : -1)) : (i == 6 ? 0 : (i == 5 ? -1 : 1))))),
        center.dy + 6.5 * (i.isEven ? 1.0 : 0.7071) * (i == 2 ? 1 : (i == 6 ? -1 : (i == 0 || i == 4 ? 0 : (i < 4 ? 1 : -1)))),
      );
      final Offset p2 = Offset(
        center.dx + 9.2 * (p1.dx - center.dx) / 6.5,
        center.dy + 9.2 * (p1.dy - center.dy) / 6.5,
      );
      canvas.drawLine(p1, p2, sunPaint);
    }
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..strokeWidth = 0.9;

    canvas.drawLine(
      Offset(size.width / 3, 0),
      Offset(size.width / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 2 / 3, 0),
      Offset(size.width * 2 / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height * 2 / 3),
      Offset(size.width, size.height * 2 / 3),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FocusReticlePainter extends CustomPainter {
  final Color color;
  final bool isLocked;

  const _FocusReticlePainter({
    required this.color,
    required this.isLocked,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    const double corner = 14.0;
    final w = size.width;
    final h = size.height;

    // Top-left
    canvas.drawLine(const Offset(0, 0), const Offset(corner, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, corner), paint);

    // Top-right
    canvas.drawLine(Offset(w, 0), Offset(w - corner, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, corner), paint);

    // Bottom-left
    canvas.drawLine(Offset(0, h), Offset(corner, h), paint);
    canvas.drawLine(Offset(0, h), Offset(0, h - corner), paint);

    // Bottom-right
    canvas.drawLine(Offset(w, h), Offset(w - corner, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - corner), paint);

    // Center dot
    canvas.drawCircle(Offset(w / 2, h / 2), 2.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _FocusReticlePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isLocked != isLocked;
}
