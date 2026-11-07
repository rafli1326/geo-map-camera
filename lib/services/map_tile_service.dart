import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class MapTileResult {
  /// 2x2 neighborhood tile bytes: [topLeft, topRight, bottomLeft, bottomRight].
  final List<Uint8List?> quadBytes;

  /// Exact coordinate position inside the 2x2 grid, guaranteed within [0.5 .. 1.5].
  final double gridX;
  final double gridY;

  /// True when tiles came from Esri World Imagery (Satellite), false when OpenStreetMap fallback.
  final bool isSatellite;
  final String cacheKey;

  const MapTileResult({
    required this.quadBytes,
    required this.gridX,
    required this.gridY,
    required this.isSatellite,
    this.cacheKey = '',
  });

  bool get isEmpty => quadBytes.every((b) => b == null || b.isEmpty);
}

class MapTileService {
  static final MapTileService _instance = MapTileService._internal();
  factory MapTileService() => _instance;
  MapTileService._internal();

  static const int _maxCacheEntries = 64;
  final Map<String, Uint8List> _satTileCache = {};
  final Map<String, Uint8List> _osmTileCache = {};
  final Map<String, Future<Uint8List?>> _inFlightRequests = {};
  final http.Client _httpClient = http.Client();
  Directory? _diskCacheDir;

  void _putRamCache(Map<String, Uint8List> cache, String key, Uint8List bytes) {
    if (cache.length >= _maxCacheEntries && !cache.containsKey(key)) {
      cache.remove(cache.keys.first);
    }
    cache[key] = bytes;
  }

  Future<File?> _getDiskTileFile(String prefix, int zoom, int x, int y) async {
    try {
      // Security: Sanitize prefix to prevent path traversal
      final cleanPrefix = prefix.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
      if (cleanPrefix.isEmpty) return null;

      if (_diskCacheDir == null) {
        final tempDir = await getTemporaryDirectory();
        final dir = Directory('${tempDir.path}/map_tiles_v2');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        _diskCacheDir = dir;
      }
      return File('${_diskCacheDir!.path}/${cleanPrefix}_${zoom}_${x}_$y.tile');
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveTileToDisk(
    String prefix,
    int zoom,
    int x,
    int y,
    Uint8List bytes,
  ) async {
    try {
      final file = await _getDiskTileFile(prefix, zoom, x, y);
      if (file != null) {
        await file.writeAsBytes(bytes, flush: false);
      }
    } catch (_) {}
  }

  /// Fetches a 2x2 tile neighborhood around ([latitude], [longitude]) so that
  /// the target coordinate is ALWAYS centered at (0.5, 0.5) of the resulting crop
  /// with the location pin dead-center in both Satellite and OpenStreetMap modes.
  Future<MapTileResult?> fetchTileResult({
    required double latitude,
    required double longitude,
    int zoom = 16,
  }) async {
    // Security & robust math: Guard against NaN, Infinity, and Mercator limits
    if (latitude.isNaN || latitude.isInfinite || longitude.isNaN || longitude.isInfinite) {
      return null;
    }
    final safeLat = latitude.clamp(-85.05112878, 85.05112878);
    final safeLon = longitude.clamp(-180.0, 180.0);

    final int n = 1 << zoom;
    final double xExact = (safeLon + 180.0) / 360.0 * n;
    final double latRad = safeLat * pi / 180.0;
    final double yExact =
        (1.0 - (log(tan(latRad) + 1.0 / cos(latRad)) / pi)) / 2.0 * n;

    final int x = xExact.floor();
    final int y = yExact.floor();
    final double fracX = (xExact - x).clamp(0.0, 1.0);
    final double fracY = (yExact - y).clamp(0.0, 1.0);

    // Choose 2x2 grid origin (startX, startY) so (xExact, yExact) is always
    // inside [0.5 .. 1.5] of the 2x2 grid — guaranteeing a 100% centered pin!
    final int startX = fracX < 0.5 ? x - 1 : x;
    final int startY = fracY < 0.5 ? y - 1 : y;
    final double gridX = (xExact - startX).clamp(0.5, 1.5);
    final double gridY = (yExact - startY).clamp(0.5, 1.5);

    final coords = <(int, int)>[
      (startX, startY),
      (startX + 1, startY),
      (startX, startY + 1),
      (startX + 1, startY + 1),
    ];

    // 1. Try fetching all 4 neighborhood Satellite tiles in parallel
    final satQuad = await Future.wait(
      coords.map((c) => _fetchSingleSatelliteTile(zoom, c.$1, c.$2)),
    );

    if (satQuad.any((b) => b != null && b.isNotEmpty)) {
      final key =
          'esri_${zoom}_${startX}_${startY}_${gridX.toStringAsFixed(3)}_${gridY.toStringAsFixed(3)}';
      return MapTileResult(
        quadBytes: satQuad,
        gridX: gridX,
        gridY: gridY,
        isSatellite: true,
        cacheKey: key,
      );
    }

    // 2. Fallback: fetch all 4 neighborhood OpenStreetMap tiles in parallel
    final osmQuad = await Future.wait(
      coords.map((c) => _fetchSingleOsmTile(zoom, c.$1, c.$2)),
    );

    if (osmQuad.any((b) => b != null && b.isNotEmpty)) {
      final key =
          'osm_${zoom}_${startX}_${startY}_${gridX.toStringAsFixed(3)}_${gridY.toStringAsFixed(3)}';
      return MapTileResult(
        quadBytes: osmQuad,
        gridX: gridX,
        gridY: gridY,
        isSatellite: false,
        cacheKey: key,
      );
    }

    return null;
  }

  Future<Uint8List?> _fetchSingleSatelliteTile(int zoom, int x, int y) async {
    final key = 'esri_$zoom/$x/$y';
    final cached = _satTileCache[key];
    if (cached != null) return cached;

    final future = _inFlightRequests.putIfAbsent(
      key,
      () => _downloadSatelliteTile(zoom, x, y, key),
    );
    try {
      return await future;
    } finally {
      _inFlightRequests.remove(key);
    }
  }

  Future<Uint8List?> _downloadSatelliteTile(
    int zoom,
    int x,
    int y,
    String key,
  ) async {
    // Check disk cache first (only genuine Esri satellite tiles use prefix 'esri')
    try {
      final diskFile = await _getDiskTileFile('esri', zoom, x, y);
      if (diskFile != null && await diskFile.exists()) {
        final bytes = await diskFile.readAsBytes();
        if (bytes.isNotEmpty) {
          _putRamCache(_satTileCache, key, bytes);
          return bytes;
        }
      }
    } catch (_) {}

    final urls = [
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/$zoom/$y/$x',
      'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/$zoom/$y/$x',
    ];

    for (final urlStr in urls) {
      try {
        final response = await _httpClient.get(
          Uri.parse(urlStr),
          headers: const {
            'User-Agent': 'flutter_map (com.geomap.camera)',
            'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
          },
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          _putRamCache(_satTileCache, key, response.bodyBytes);
          unawaited(_saveTileToDisk('esri', zoom, x, y, response.bodyBytes));
          return response.bodyBytes;
        }
      } catch (e) {
        debugPrint('Esri satellite tile attempt failed ($urlStr): $e');
      }
    }
    return null;
  }

  Future<Uint8List?> _fetchSingleOsmTile(int zoom, int x, int y) async {
    final key = 'osm_$zoom/$x/$y';
    final cached = _osmTileCache[key];
    if (cached != null) return cached;

    final future = _inFlightRequests.putIfAbsent(
      key,
      () => _downloadOsmTile(zoom, x, y, key),
    );
    try {
      return await future;
    } finally {
      _inFlightRequests.remove(key);
    }
  }

  Future<Uint8List?> _downloadOsmTile(
    int zoom,
    int x,
    int y,
    String key,
  ) async {
    try {
      final diskFile = await _getDiskTileFile('osm', zoom, x, y);
      if (diskFile != null && await diskFile.exists()) {
        final bytes = await diskFile.readAsBytes();
        if (bytes.isNotEmpty) {
          _putRamCache(_osmTileCache, key, bytes);
          return bytes;
        }
      }
    } catch (_) {}

    try {
      final osmUrl = Uri.parse('https://tile.openstreetmap.org/$zoom/$x/$y.png');
      final response = await _httpClient.get(
        osmUrl,
        headers: const {
          'User-Agent': 'flutter_map (com.geomap.camera)',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        _putRamCache(_osmTileCache, key, response.bodyBytes);
        unawaited(_saveTileToDisk('osm', zoom, x, y, response.bodyBytes));
        return response.bodyBytes;
      }
    } catch (e) {
      debugPrint('OSM fallback tile fetch error: $e');
    }
    return null;
  }

  /// Draw a fallback satellite-tinted mini-map on canvas when completely offline
  void drawFallbackMiniMap({
    required Canvas canvas,
    required Rect rect,
    required double latitude,
    required double longitude,
    double scale = 1.0,
  }) {
    final radius = Radius.circular(8.0 * scale);
    final rrect = RRect.fromRectAndRadius(rect, radius);

    // Deep forest/satellite green terrain background
    final bgPaint = Paint()..color = const Color(0xFF1E3524);
    canvas.drawRRect(rrect, bgPaint);

    // Subtle terrain grid lines
    final gridPaint = Paint()
      ..color = const Color(0x3386EFAC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1 * scale;

    final center = rect.center;
    final maxRadius = rect.width * 0.40;
    canvas.drawCircle(center, maxRadius, gridPaint);
    canvas.drawCircle(center, maxRadius * 0.62, gridPaint);

    canvas.drawLine(
      Offset(rect.left + 8 * scale, center.dy),
      Offset(rect.right - 8 * scale, center.dy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx, rect.top + 8 * scale),
      Offset(center.dx, rect.bottom - 8 * scale),
      gridPaint,
    );

    drawMapPin(canvas: canvas, target: center, scale: scale);
    drawGpsBadge(canvas: canvas, rect: rect, scale: scale);
  }

  /// Draws a classic red teardrop Google-style map pin pointing at [target]
  void drawMapPin({
    required Canvas canvas,
    required Offset target,
    required double scale,
  }) {
    canvas.drawOval(
      Rect.fromCenter(
        center: target,
        width: 10.0 * scale,
        height: 4.5 * scale,
      ),
      Paint()..color = const Color(0x77000000),
    );

    final double pinRadius = 9.0 * scale;
    final Offset headCenter = Offset(target.dx, target.dy - 15.0 * scale);

    final Path pinPath = Path()
      ..moveTo(target.dx, target.dy)
      ..lineTo(headCenter.dx - pinRadius * 0.78, headCenter.dy + pinRadius * 0.5)
      ..arcToPoint(
        Offset(headCenter.dx + pinRadius * 0.78, headCenter.dy + pinRadius * 0.5),
        radius: Radius.circular(pinRadius),
        largeArc: true,
        clockwise: true,
      )
      ..close();

    // Red pin fill
    canvas.drawPath(
      pinPath,
      Paint()
        ..color = const Color(0xFFEA4335)
        ..style = PaintingStyle.fill,
    );

    // Dark crimson inner dot
    canvas.drawCircle(
      headCenter,
      3.4 * scale,
      Paint()..color = const Color(0xFF7F1D1D),
    );
  }

  /// Draws the "SATELIT" badge at bottom-left inside [rect]
  void drawGpsBadge({
    required Canvas canvas,
    required Rect rect,
    required double scale,
    String label = 'SATELIT',
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 11.5 * scale,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6 * scale,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final padH = 6.0 * scale;
    final padV = 3.0 * scale;
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        rect.left + 6.0 * scale,
        rect.bottom - textPainter.height - padV * 2 - 5.0 * scale,
        textPainter.width + padH * 2,
        textPainter.height + padV * 2,
      ),
      Radius.circular(5.0 * scale),
    );

    canvas.drawRRect(badgeRect, Paint()..color = const Color(0xB8000000));
    textPainter.paint(
      canvas,
      Offset(
        badgeRect.left + padH,
        badgeRect.top + padV,
      ),
    );
  }
}
