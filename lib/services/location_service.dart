import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../models/gps_telemetry.dart';
import 'watermark_burner.dart';

class LocationService extends ChangeNotifier {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  /// A fix older than this is treated as "no fix" (location hidden in watermark).
  static const Duration maxFixAge = Duration(seconds: 30);

  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _staleTimer;

  // No real coordinates until the first fix arrives.
  GpsTelemetry _currentTelemetry = GpsTelemetry(latitude: 0, longitude: 0);
  DateTime? _lastFixTime;

  bool _hasPermission = false;
  String _statusMessage = 'Menginisialisasi GPS...';
  DateTime? _lastGeocodeTime;
  Position? _lastGeocodedPosition;

  GpsTelemetry get currentTelemetry => _currentTelemetry;
  bool get hasPermission => _hasPermission;
  String get statusMessage {
    if (isMocked) return 'Lokasi palsu terdeteksi';
    if (!hasFix && _hasPermission) return 'Menunggu sinyal GPS...';
    return _statusMessage;
  }

  /// True when a real position was received within [maxFixAge].
  bool get hasFix =>
      _lastFixTime != null && DateTime.now().difference(_lastFixTime!) <= maxFixAge;

  /// Kept for existing UI code: "still locating" == no valid fix.
  bool get isLocating => !hasFix;

  /// True when the latest fix comes from a mock-location provider (Fake GPS).
  bool get isMocked => hasFix && _currentTelemetry.isMocked;

  Future<void> init() async {
    await checkAndRequestPermission();
    if (_hasPermission) {
      await startListening();
    }
    // Re-evaluate staleness periodically so the UI flips to "no fix" on its own.
    _staleTimer?.cancel();
    _staleTimer = Timer.periodic(const Duration(seconds: 5), (_) => notifyListeners());
  }

  Future<bool> checkAndRequestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _statusMessage = 'Layanan lokasi nonaktif';
      notifyListeners();
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _statusMessage = 'Izin lokasi ditolak';
        _hasPermission = false;
        notifyListeners();
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _statusMessage = 'Izin lokasi ditolak permanen';
      _hasPermission = false;
      notifyListeners();
      return false;
    }

    _hasPermission = true;
    _statusMessage = 'Mencari sinyal satelit...';
    notifyListeners();
    return true;
  }

  Future<void> startListening() async {
    try {
      // 1. Use last known position only if it is fresh enough.
      final initialPos = await Geolocator.getLastKnownPosition();
      if (initialPos != null &&
          DateTime.now().difference(initialPos.timestamp) <= maxFixAge) {
        _updateTelemetry(initialPos);
        _reverseGeocode(initialPos);
      }

      // 2. Continuous updates every second (needed for freshness + video track).
      final LocationSettings locationSettings = defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
              intervalDuration: const Duration(seconds: 1),
            )
          : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0);

      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          _updateTelemetry(position);
          _shouldReverseGeocode(position);
        },
        onError: (e) {
          debugPrint('Location stream error: $e');
          _statusMessage = 'Sinyal GPS terputus';
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('Error starting location stream: $e');
      _statusMessage = 'Gagal mengakses GPS';
      notifyListeners();
    }
  }

  void _updateTelemetry(Position position) {
    // Use receive time so a device with a skewed GPS clock is not marked stale.
    _lastFixTime = DateTime.now();
    _statusMessage = 'GPS Siap (±${position.accuracy.toStringAsFixed(1)}m)';
    _currentTelemetry = _currentTelemetry.copyWith(
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      accuracy: position.accuracy,
      speed: position.speed,
      heading: position.heading,
      timestamp: position.timestamp,
      isMocked: position.isMocked,
    );
    // Pre-fetch & pre-decode the satellite map tile in the background so shutter is instant.
    unawaited(
      WatermarkBurner().prewarmTile(
        latitude: position.latitude,
        longitude: position.longitude,
      ),
    );
    notifyListeners();
  }

  void _shouldReverseGeocode(Position position) {
    final now = DateTime.now();
    if (_lastGeocodeTime != null &&
        now.difference(_lastGeocodeTime!).inSeconds < 10) {
      return; // Debounce lookups
    }

    if (_lastGeocodedPosition != null) {
      final distance = Geolocator.distanceBetween(
        _lastGeocodedPosition!.latitude,
        _lastGeocodedPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      if (distance < 20) {
        return; // Position didn't change enough
      }
    }

    _reverseGeocode(position);
  }

  Future<void> _reverseGeocode(Position position) async {
    _lastGeocodeTime = DateTime.now();
    _lastGeocodedPosition = position;

    try {
      final placemarks = await Geocoding().placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 4));

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final fullAddr = GpsTelemetry.formatCleanAddress(
          street: place.street,
          subLocality: place.subLocality,
          locality: place.locality,
          subAdministrativeArea: place.subAdministrativeArea,
          administrativeArea: place.administrativeArea,
          fallbackAddress:
              'Lokasi (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})',
        );

        _currentTelemetry = _currentTelemetry.copyWith(
          address: fullAddr,
          street: place.street,
          subLocality: place.subLocality,
          locality: place.locality,
          subAdministrativeArea: place.subAdministrativeArea,
          administrativeArea: place.administrativeArea,
          postalCode: place.postalCode,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Reverse geocoding offline/failed: $e');
      if (_currentTelemetry.address == null) {
        _currentTelemetry = _currentTelemetry.copyWith(
          address:
              'Lokasi: ${position.latitude.toStringAsFixed(5)}°, ${position.longitude.toStringAsFixed(5)}°',
        );
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _staleTimer?.cancel();
    super.dispose();
  }
}
