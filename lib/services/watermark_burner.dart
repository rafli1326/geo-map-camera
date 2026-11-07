import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../models/gps_telemetry.dart';
import '../models/watermark_config.dart';
import 'map_tile_service.dart';

/// Decoded mini-map tile centered on the exact GPS coordinate.
class MiniMapTile {
  final ui.Image image;
  final bool isSatellite;
  const MiniMapTile(this.image, {this.isSatellite = true});
}

class WatermarkBurner {
  static final WatermarkBurner _instance = WatermarkBurner._internal();
  factory WatermarkBurner() => _instance;
  WatermarkBurner._internal();

  /// Longest edge of saved photos. Keeps background encoding fast while preserving crisp detail.
  static const int maxPhotoLongEdge = 2560;

  static const int _maxDecodedTiles = 12;
  final Map<String, MiniMapTile> _decodedTileCache = {};

  void _cacheDecodedTile(String key, MiniMapTile tile) {
    if (key.isEmpty) return;
    if (_decodedTileCache.length >= _maxDecodedTiles &&
        !_decodedTileCache.containsKey(key)) {
      final oldestKey = _decodedTileCache.keys.first;
      _decodedTileCache.remove(oldestKey);
    }
    _decodedTileCache[key] = tile;
  }

  /// Pre-fetches and pre-decodes the satellite map tile into GPU/UI memory
  /// so that photo shutter and video recording have 0 ms tile wait time.
  Future<MiniMapTile?> prewarmTile({
    required double latitude,
    required double longitude,
  }) async {
    if (latitude == 0.0 && longitude == 0.0) return null;
    final result = await MapTileService().fetchTileResult(
      latitude: latitude,
      longitude: longitude,
    );
    return decodeTile(result);
  }

  Future<MiniMapTile?> decodeTile(MapTileResult? result) async {
    if (result == null || result.isEmpty) return null;
    if (result.cacheKey.isNotEmpty) {
      final cached = _decodedTileCache[result.cacheKey];
      if (cached != null) return cached;
    }
    try {
      // Stitch the 2x2 neighborhood onto a 256x256 canvas centered on (gridX, gridY)
      // so the target GPS coordinate is ALWAYS at the exact center (128, 128)!
      const double tileSize = 256.0;
      const double outSize = 256.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Base background matching the map mode
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, outSize, outSize),
        Paint()
          ..color = result.isSatellite
              ? const Color(0xFF1E3524)
              : const Color(0xFFE5E7EB),
      );

      final double cx = result.gridX * tileSize;
      final double cy = result.gridY * tileSize;
      canvas.save();
      canvas.translate(outSize / 2.0 - cx, outSize / 2.0 - cy);

      const offsets = <Offset>[
        Offset(0, 0),
        Offset(tileSize, 0),
        Offset(0, tileSize),
        Offset(tileSize, tileSize),
      ];

      final decodedSubTiles = <ui.Image>[];
      for (int i = 0; i < 4 && i < result.quadBytes.length; i++) {
        final bytes = result.quadBytes[i];
        if (bytes == null || bytes.isEmpty) continue;
        try {
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          final subImg = frame.image;
          decodedSubTiles.add(subImg);
          canvas.drawImageRect(
            subImg,
            Rect.fromLTWH(0, 0, subImg.width.toDouble(), subImg.height.toDouble()),
            Rect.fromLTWH(offsets[i].dx, offsets[i].dy, tileSize, tileSize),
            Paint()..filterQuality = FilterQuality.low,
          );
        } catch (_) {}
      }
      canvas.restore();

      final centeredImage =
          await recorder.endRecording().toImage(outSize.toInt(), outSize.toInt());
      for (final sub in decodedSubTiles) {
        sub.dispose();
      }

      final miniTile = MiniMapTile(
        centeredImage,
        isSatellite: result.isSatellite,
      );
      _cacheDecodedTile(result.cacheKey, miniTile);
      return miniTile;
    } catch (e) {
      debugPrint('Tile decode failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // PHOTO
  // ---------------------------------------------------------------------------

  /// Builds the final JPEG: orientation fix, front-camera un-mirror, aspect
  /// crop, resolution cap, floating watermark card and EXIF (GPS + time + device).
  ///
  /// [rotationDegrees]:
  ///  - `0`: portrait upright
  ///  - `-90`: phone turned counter-clockwise (top of phone on left, right edge up)
  ///  - `90`: phone turned clockwise (top of phone on right, left edge up)
  /// [aspectRatio]: long edge / short edge (e.g. 4/3). Applied to the oriented frame.
  Future<Uint8List> burnWatermark({
    required Uint8List photoBytes,
    required GpsTelemetry telemetry,
    required WatermarkConfig config,
    MapTileResult? mapTileResult,
    int rotationDegrees = 0,
    bool mirror = false,
    double? aspectRatio,
    bool includeGpsExif = true,
  }) async {
    // 1. Hardware-assisted downsampled decode via ImageDescriptor so large sensor
    // images (e.g., 12MP/50MP) are decoded directly near target size.
    final ui.ImmutableBuffer immutableBuffer =
        await ui.ImmutableBuffer.fromUint8List(photoBytes);
    final ui.ImageDescriptor descriptor =
        await ui.ImageDescriptor.encoded(immutableBuffer);
    final int rawW = descriptor.width;
    final int rawH = descriptor.height;
    final double preScale = min(1.0, maxPhotoLongEdge / max(rawW, rawH));
    final ui.Codec codec = await descriptor.instantiateCodec(
      targetWidth: (rawW * preScale).round(),
      targetHeight: (rawH * preScale).round(),
    );
    final ui.Image baseImage = (await codec.getNextFrame()).image;
    descriptor.dispose();
    immutableBuffer.dispose();

    final int srcW = baseImage.width;
    final int srcH = baseImage.height;

    final bool landscape = (rotationDegrees == -90 || rotationDegrees == 90) && srcW < srcH;
    final bool upsideDown = rotationDegrees == 180;

    // Oriented frame size (before crop).
    final double frameW = (landscape ? srcH : srcW).toDouble();
    final double frameH = (landscape ? srcW : srcH).toDouble();

    // 2. Center crop to requested aspect ratio (ratio follows frame orientation).
    double cropW = frameW, cropH = frameH;
    if (aspectRatio != null && aspectRatio > 0) {
      final double target = frameW >= frameH ? aspectRatio : 1 / aspectRatio; // w/h
      if (frameW / frameH > target) {
        cropW = frameH * target;
      } else {
        cropH = frameW / target;
      }
    }
    final double cropLeft = (frameW - cropW) / 2;
    final double cropTop = (frameH - cropH) / 2;

    // 3. Resolution cap.
    final double outScale = min(1.0, maxPhotoLongEdge / max(cropW, cropH));
    final int width = (cropW * outScale).round();
    final int height = (cropH * outScale).round();

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    // Transform chain (applied to the photo, last call acts first):
    // output = scale * (orient(mirror(src)) - cropOffset)
    canvas.save();
    canvas.scale(outScale);
    canvas.translate(-cropLeft, -cropTop);
    if (landscape) {
      if (rotationDegrees == -90) {
        canvas.translate(0, frameH);
        canvas.rotate(-pi / 2);
      } else {
        canvas.translate(frameW, 0);
        canvas.rotate(pi / 2);
      }
    } else if (upsideDown) {
      canvas.translate(frameW, frameH);
      canvas.rotate(pi);
    }
    if (mirror) {
      // Mirror in the sensor (portrait) frame so it stays horizontal for the subject.
      canvas.translate(srcW.toDouble(), 0);
      canvas.scale(-1, 1);
    }
    canvas.drawImage(baseImage, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();

    // 4. Floating Watermark Card (Left Satellite Map + Right Dark Card).
    final bool showMap = config.showMiniMap &&
        (telemetry.latitude != 0.0 || telemetry.longitude != 0.0);
    final tile = showMap ? await decodeTile(mapTileResult) : null;
    final layout = _layoutBanner(
      width: width.toDouble(),
      shortEdge: min(width, height).toDouble(),
      telemetry: telemetry,
      config: config,
      showMap: showMap,
    );
    _paintBanner(
      canvas,
      layout,
      width.toDouble(),
      height - layout.totalHeight,
      telemetry,
      tile,
    );

    // 5. Rasterize, then zero-copy transfer RGBA + 64KB EXIF header to background Isolate.
    final ui.Image composited = await recorder.endRecording().toImage(width, height);
    final ByteData? rawRgba = await composited.toByteData(format: ui.ImageByteFormat.rawRgba);
    baseImage.dispose();
    composited.dispose();
    if (rawRgba == null) {
      throw Exception('Failed to get raw RGBA bytes from composited image');
    }

    final transferableRgba = TransferableTypedData.fromList([
      rawRgba.buffer.asUint8List(),
    ]);
    final int exifHeaderLen = min(photoBytes.length, 65536);
    final transferableExifHeader = TransferableTypedData.fromList([
      Uint8List.sublistView(photoBytes, 0, exifHeaderLen),
    ]);
    final exifInput = _ExifInput(
      latitude: telemetry.latitude,
      longitude: telemetry.longitude,
      altitude: telemetry.altitude,
      includeGps: includeGpsExif,
      timestamp: telemetry.timestamp,
    );
    final transferableJpg = await Isolate.run(
      () => _encodeJpegWithExifTransferable(
        transferableRgba,
        width,
        height,
        transferableExifHeader,
        exifInput,
      ),
    );
    return transferableJpg.materialize().asUint8List();
  }

  // ---------------------------------------------------------------------------
  // VIDEO OVERLAY STRIP
  // ---------------------------------------------------------------------------

  /// Renders ONLY the cropped bottom watermark strip ([frameWidth] x `stripHeight`)
  /// instead of a full-frame transparent canvas, cutting pixel area & RAM by ~8x.
  /// Positioned at the bottom of the video frame via Media3 `OverlaySettings`.
  Future<Uint8List> renderBannerPng({
    required int frameWidth,
    required int frameHeight,
    required GpsTelemetry telemetry,
    required WatermarkConfig config,
    MiniMapTile? tile,
  }) async {
    final bool showMap = config.showMiniMap &&
        (telemetry.latitude != 0.0 || telemetry.longitude != 0.0);
    final layout = _layoutBanner(
      width: frameWidth.toDouble(),
      shortEdge: min(frameWidth, frameHeight).toDouble(),
      telemetry: telemetry,
      config: config,
      showMap: showMap,
    );
    final int stripHeight = layout.totalHeight.ceil().clamp(1, frameHeight);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _paintBanner(canvas, layout, frameWidth.toDouble(), 0.0, telemetry, tile);
    final image = await recorder.endRecording().toImage(frameWidth, stripHeight);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  // ---------------------------------------------------------------------------
  // BANNER LAYOUT + PAINT (Reference Floating Dual-Box Design)
  // ---------------------------------------------------------------------------

  String _buildNoteLine(WatermarkConfig config) {
    final parts = <String>[];
    if (config.showProjectTitle && config.projectTitle.trim().isNotEmpty) {
      parts.add(config.projectTitle.trim());
    }
    if (config.showOfficerName && config.officerName.trim().isNotEmpty) {
      parts.add(config.officerName.trim());
    }
    if (parts.isEmpty) return '';
    return 'Note : ${parts.join(' • ')}';
  }

  _BannerLayout _layoutBanner({
    required double width,
    required double shortEdge,
    required GpsTelemetry telemetry,
    required WatermarkConfig config,
    required bool showMap,
  }) {
    final double scale = (shortEdge / 640.0).clamp(0.8, 4.0);
    final double marginH = 20.0 * scale;
    final double marginB = 20.0 * scale;
    final double gap = 16.0 * scale;
    final double cardPadH = 20.0 * scale;
    final double cardPadV = 14.0 * scale;
    final double badgeH = 30.0 * scale;
    final double mapBaseSize = showMap ? 176.0 * scale : 0.0;

    final double cardWidth =
        width - marginH * 2 - (showMap ? mapBaseSize + gap : 0.0);
    final double textMaxWidth = max(120.0, cardWidth - cardPadH * 2);

    TextPainter tp(String text, TextStyle style, int maxLines) => TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          maxLines: maxLines,
          ellipsis: '…',
        )..layout(maxWidth: textMaxWidth);

    final rows = <_WatermarkRow>[];

    if (config.showAddress) {
      // 1. Header: City, Province, Country + Flag
      rows.add(_WatermarkRow(
        painter: tp(
          telemetry.locationHeader,
          TextStyle(
            color: Colors.white,
            fontSize: 25.0 * scale,
            fontWeight: FontWeight.w700,
            height: 1.18,
          ),
          2,
        ),
        spacingAfter: 5.0 * scale,
      ));

      // 2. Full Address
      rows.add(_WatermarkRow(
        painter: tp(
          telemetry.fullAddressLine,
          TextStyle(
            color: Colors.white,
            fontSize: 18.5 * scale,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
          2,
        ),
        spacingAfter: 4.0 * scale,
      ));
    }

    if (config.showCoordinates) {
      // 3. Lat & Long
      String coordLine = config.coordFormat == 'dms'
          ? telemetry.latLongLineDms
          : telemetry.latLongLineDecimal;
      if (config.showAltitude && telemetry.altitude != 0.0) {
        coordLine = '$coordLine • ${telemetry.formattedAltitude}';
      }
      rows.add(_WatermarkRow(
        painter: tp(
          coordLine,
          TextStyle(
            color: Colors.white,
            fontSize: 18.5 * scale,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
          1,
        ),
        spacingAfter: 4.0 * scale,
      ));
    }

    if (config.showDateTime) {
      // 4. Day, Date, Time + GMT
      rows.add(_WatermarkRow(
        painter: tp(
          telemetry.dateTimeGmtLine,
          TextStyle(
            color: Colors.white,
            fontSize: 18.5 * scale,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
          1,
        ),
        spacingAfter: 4.0 * scale,
      ));
    }

    final noteLine = _buildNoteLine(config);
    if (noteLine.isNotEmpty) {
      // 5. Note
      rows.add(_WatermarkRow(
        painter: tp(
          noteLine,
          TextStyle(
            color: Colors.white,
            fontSize: 18.5 * scale,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
          1,
        ),
        spacingAfter: 0.0,
      ));
    }

    double textH = 0;
    for (int i = 0; i < rows.length; i++) {
      textH += rows[i].painter.height;
      if (i < rows.length - 1) textH += rows[i].spacingAfter;
    }

    final double cardHeight = max(textH + cardPadV * 2, mapBaseSize);
    final double totalHeight = badgeH + cardHeight + marginB;

    return _BannerLayout(
      scale: scale,
      marginH: marginH,
      marginB: marginB,
      gap: gap,
      cardPadH: cardPadH,
      cardPadV: cardPadV,
      badgeH: badgeH,
      mapSize: mapBaseSize,
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      rows: rows,
      textHeight: textH,
      totalHeight: totalHeight,
    );
  }

  void _paintBanner(
    Canvas canvas,
    _BannerLayout l,
    double width,
    double top,
    GpsTelemetry telemetry,
    MiniMapTile? tile,
  ) {
    final s = l.scale;
    final double cardTop = top + l.badgeH;
    final double cardLeft =
        l.marginH + (l.mapSize > 0 ? l.mapSize + l.gap : 0.0);

    // 1. Top-Right "[📷 Geo Map Camera]" branding tab above the dark card
    final badgePainter = TextPainter(
      text: TextSpan(
        text: 'Geo Map Camera',
        style: TextStyle(
          color: Colors.white,
          fontSize: 15.5 * s,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final double iconBoxSize = 20.0 * s;
    final double badgePadH = 12.0 * s;
    final double badgeGap = 7.0 * s;
    final double badgeW = badgePadH * 2 + iconBoxSize + badgeGap + badgePainter.width;
    final double badgeRight = cardLeft + l.cardWidth - 12.0 * s;
    final double badgeLeft = badgeRight - badgeW;

    final badgeRect = Rect.fromLTWH(badgeLeft, top, badgeW, l.badgeH);
    final badgeRRect = RRect.fromRectAndCorners(
      badgeRect,
      topLeft: Radius.circular(10.0 * s),
      topRight: Radius.circular(10.0 * s),
    );
    canvas.drawRRect(badgeRRect, Paint()..color = const Color(0xAD000000));

    // Tiny yellow camera icon box inside badge
    final iconRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        badgeLeft + badgePadH,
        top + (l.badgeH - iconBoxSize) / 2,
        iconBoxSize,
        iconBoxSize,
      ),
      Radius.circular(5.0 * s),
    );
    canvas.drawRRect(iconRect, Paint()..color = const Color(0xFFFACC15));
    canvas.drawCircle(
      iconRect.center,
      4.5 * s,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * s,
    );

    badgePainter.paint(
      canvas,
      Offset(
        badgeLeft + badgePadH + iconBoxSize + badgeGap,
        top + (l.badgeH - badgePainter.height) / 2,
      ),
    );

    // 2. Left Satellite Mini-Map
    if (l.mapSize > 0) {
      final mapRect = Rect.fromLTWH(
        l.marginH,
        cardTop,
        l.mapSize,
        l.cardHeight,
      );
      if (tile != null) {
        _paintTile(canvas, mapRect, tile, s);
      } else {
        MapTileService().drawFallbackMiniMap(
          canvas: canvas,
          rect: mapRect,
          latitude: telemetry.latitude,
          longitude: telemetry.longitude,
          scale: s,
        );
      }
    }

    // 3. Right Semi-Transparent Dark Info Card
    final cardRect = Rect.fromLTWH(cardLeft, cardTop, l.cardWidth, l.cardHeight);
    final cardRRect = RRect.fromRectAndRadius(cardRect, Radius.circular(14.0 * s));
    canvas.drawRRect(cardRRect, Paint()..color = const Color(0xAD000000));

    double y = cardTop + (l.cardHeight - l.textHeight) / 2;
    final double textLeft = cardLeft + l.cardPadH;
    for (int i = 0; i < l.rows.length; i++) {
      final row = l.rows[i];
      row.painter.paint(canvas, Offset(textLeft, y));
      y += row.painter.height + row.spacingAfter;
    }
  }

  void _paintTile(Canvas canvas, Rect mapRect, MiniMapTile tile, double s) {
    final double tileW = tile.image.width.toDouble();
    final double tileH = tile.image.height.toDouble();
    // Zoom in slightly around the centered coordinate (128, 128)
    final double crop = min(tileW, tileH) * 0.72;
    final double srcLeft = (tileW - crop) / 2.0;
    final double srcTop = (tileH - crop) / 2.0;

    // Because decodeTile stitched the 2x2 neighborhood around the exact GPS coordinate,
    // the pin is ALWAYS at the exact center of mapRect (both Satellite and OpenStreetMap)!
    final Offset pin = mapRect.center;

    final rrect = RRect.fromRectAndRadius(mapRect, Radius.circular(14.0 * s));
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawImageRect(
      tile.image,
      Rect.fromLTWH(srcLeft, srcTop, crop, crop),
      mapRect,
      Paint()..filterQuality = FilterQuality.medium,
    );
    MapTileService().drawMapPin(canvas: canvas, target: pin, scale: s);
    MapTileService().drawGpsBadge(
      canvas: canvas,
      rect: mapRect,
      scale: s,
      label: tile.isSatellite ? 'SATELIT' : 'PETA GPS',
    );
    canvas.restore();
  }
}

// -----------------------------------------------------------------------------
// Isolate side: JPEG encode + EXIF
// -----------------------------------------------------------------------------

class _ExifInput {
  final double latitude;
  final double longitude;
  final double altitude;
  final bool includeGps;
  final DateTime timestamp;
  const _ExifInput({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.includeGps,
    required this.timestamp,
  });
}

TransferableTypedData _encodeJpegWithExifTransferable(
  TransferableTypedData transferableRgba,
  int width,
  int height,
  TransferableTypedData transferableExifHeader,
  _ExifInput e,
) {
  final rgba = transferableRgba.materialize().asUint8List();
  final exifHeader = transferableExifHeader.materialize().asUint8List();
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    order: img.ChannelOrder.rgba,
  );
  image.exif = buildPhotoExif(
    originalJpeg: exifHeader,
    latitude: e.latitude,
    longitude: e.longitude,
    altitude: e.altitude,
    includeGps: e.includeGps,
    timestamp: e.timestamp,
  );
  final jpgBytes = img.encodeJpg(image, quality: 90);
  return TransferableTypedData.fromList([jpgBytes]);
}

/// Fresh EXIF block: device make/model copied from the camera JPEG,
/// capture time, orientation reset (pixels are already upright) and
/// standard GPS tags (DMS rationals, readable by Google Photos/Maps).
img.ExifData buildPhotoExif({
  required Uint8List originalJpeg,
  required double latitude,
  required double longitude,
  required double altitude,
  required bool includeGps,
  required DateTime timestamp,
}) {
  final exif = img.ExifData();
  img.ExifData? src;
  try {
    src = img.decodeJpgExif(originalJpeg);
  } catch (_) {}

  String two(int v) => v.toString().padLeft(2, '0');
  final dt = '${timestamp.year}:${two(timestamp.month)}:${two(timestamp.day)} '
      '${two(timestamp.hour)}:${two(timestamp.minute)}:${two(timestamp.second)}';

  final ifd0 = exif.imageIfd;
  final make = src?.imageIfd.make;
  final model = src?.imageIfd.model;
  if (make != null && make.trim().isNotEmpty) ifd0.make = make.trim();
  if (model != null && model.trim().isNotEmpty) ifd0.model = model.trim();
  ifd0.orientation = 1;
  ifd0.software = 'Geo Map Camera';
  ifd0['DateTime'] = img.IfdValueAscii(dt);
  exif.exifIfd['DateTimeOriginal'] = img.IfdValueAscii(dt);
  exif.exifIfd['DateTimeDigitized'] = img.IfdValueAscii(dt);

  if (includeGps) {
    img.IfdValueRational dms(double value) {
      final v = value.abs();
      final deg = v.floor();
      final minF = (v - deg) * 60;
      final mins = minF.floor();
      final secs = ((minF - mins) * 60 * 10000).round();
      return _rationals([deg, 1, mins, 1, secs, 10000]);
    }

    final gps = exif.gpsIfd;
    gps[0x0000] = img.IfdByteValue.list(Uint8List.fromList([2, 3, 0, 0])); // GPSVersionID
    gps[0x0001] = img.IfdValueAscii(latitude < 0 ? 'S' : 'N');
    gps[0x0002] = dms(latitude);
    gps[0x0003] = img.IfdValueAscii(longitude < 0 ? 'W' : 'E');
    gps[0x0004] = dms(longitude);
    gps[0x0005] = img.IfdByteValue(altitude < 0 ? 1 : 0); // GPSAltitudeRef
    gps[0x0006] = img.IfdValueRational((altitude.abs() * 100).round(), 100);
    final utc = timestamp.toUtc();
    gps[0x0007] = _rationals([utc.hour, 1, utc.minute, 1, utc.second, 1]);
    gps[0x001D] = img.IfdValueAscii('${utc.year}:${two(utc.month)}:${two(utc.day)}');
  }
  return exif;
}

/// Multi-value RATIONAL from [numerator, denominator, ...] pairs.
/// (`Rational` itself is not exported by package:image.)
img.IfdValueRational _rationals(List<int> pairs) {
  final bytes = ByteData(pairs.length * 4);
  for (int i = 0; i < pairs.length; i++) {
    bytes.setUint32(i * 4, pairs[i], Endian.little);
  }
  return img.IfdValueRational.data(
    img.InputBuffer(bytes.buffer.asUint8List()),
    pairs.length ~/ 2,
  );
}

class _WatermarkRow {
  final TextPainter painter;
  final double spacingAfter;

  const _WatermarkRow({
    required this.painter,
    required this.spacingAfter,
  });
}

class _BannerLayout {
  final double scale;
  final double marginH;
  final double marginB;
  final double gap;
  final double cardPadH;
  final double cardPadV;
  final double badgeH;
  final double mapSize;
  final double cardWidth;
  final double cardHeight;
  final List<_WatermarkRow> rows;
  final double textHeight;
  final double totalHeight;

  const _BannerLayout({
    required this.scale,
    required this.marginH,
    required this.marginB,
    required this.gap,
    required this.cardPadH,
    required this.cardPadV,
    required this.badgeH,
    required this.mapSize,
    required this.cardWidth,
    required this.cardHeight,
    required this.rows,
    required this.textHeight,
    required this.totalHeight,
  });
}
