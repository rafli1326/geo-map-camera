import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocam_survey/models/gps_telemetry.dart';
import 'package:geocam_survey/models/watermark_config.dart';
import 'package:geocam_survey/services/watermark_burner.dart';

void main() {
  test('EXIF builder attaches GPS and software tags', () {
    final exif = buildPhotoExif(
      originalJpeg: Uint8List(0),
      latitude: -2.0547,
      longitude: 115.4540,
      altitude: 45.0,
      includeGps: true,
      timestamp: DateTime(2026, 11, 7, 9, 30, 0),
    );

    expect(exif.imageIfd.software, equals('Geo Map Camera'));
    expect(exif.gpsIfd[0x0001]?.toString(), equals('S'));
    expect(exif.gpsIfd[0x0003]?.toString(), equals('E'));
    expect(exif.gpsIfd[0x001D]?.toString(), equals('2026:11:07'));
  });

  test('renderBannerPng renders cropped bottom strip instead of full frame', () async {
    final telemetry = GpsTelemetry(
      latitude: -2.0547,
      longitude: 115.4540,
      address: 'Tanjung, Kalimantan Selatan',
    );
    const config = WatermarkConfig();

    final pngBytes = await WatermarkBurner().renderBannerPng(
      frameWidth: 1080,
      frameHeight: 1920,
      telemetry: telemetry,
      config: config,
    );

    expect(pngBytes, isNotEmpty);
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, equals(1080));
    // Strip height should be only the bottom watermark card (~200-350px), not 1920px!
    expect(frame.image.height, lessThan(450));
    expect(frame.image.height, greaterThan(150));
    frame.image.dispose();
  });

  test('dart:ui canvas watermark stamping test', () async {
    const int width = 800;
    const int height = 600;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Draw background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Colors.blueGrey,
    );

    // Draw banner at bottom
    final bannerHeight = height * 0.22;
    final bannerRect = Rect.fromLTWH(0, height - bannerHeight, width.toDouble(), bannerHeight);
    canvas.drawRect(
      bannerRect,
      Paint()..color = const Color(0xD90B1326), // 85% opacity dark
    );

    // Draw text with TextPainter
    final tp = TextPainter(
      text: const TextSpan(
        text: "Jl. Sudirman No. 45, Jakarta\n-6.2088° S, 106.8456° E",
        style: TextStyle(color: Colors.white, fontSize: 20),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: width - 200);
    tp.paint(canvas, Offset(20, height - bannerHeight + 20));

    final pic = recorder.endRecording();
    final img = await pic.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    expect(byteData, isNotNull);
    expect(byteData!.lengthInBytes, greaterThan(1000));
  });
}
