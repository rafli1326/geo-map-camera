import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocam_survey/models/gps_telemetry.dart';
import 'package:geocam_survey/models/watermark_config.dart';
import 'package:geocam_survey/widgets/live_watermark_banner.dart';

void main() {
  test('GpsTelemetry formatting test', () {
    final telemetry = GpsTelemetry(
      latitude: -6.208832,
      longitude: 106.845618,
      altitude: 42.5,
      accuracy: 1.2,
      address: 'Jl. Sudirman No. 45, Jakarta Pusat',
    );

    expect(telemetry.formattedCoordDecimal, contains('6.208832° S'));
    expect(telemetry.formattedCoordDecimal, contains('106.845618° E'));
    expect(telemetry.displayAddress, equals('Jl. Sudirman No. 45, Jakarta Pusat'));
    expect(telemetry.formattedAccuracy, equals('±1.2 m'));
  });

  test('WatermarkConfig serialization test', () {
    const config = WatermarkConfig(
      projectTitle: 'Survei Toko Cabang A',
      officerName: 'Budi Santoso',
      coordFormat: 'dms',
    );

    final jsonStr = config.toJson();
    final restored = WatermarkConfig.fromJson(jsonStr);

    expect(restored.projectTitle, equals('Survei Toko Cabang A'));
    expect(restored.officerName, equals('Budi Santoso'));
    expect(restored.coordFormat, equals('dms'));

    final noLoc = restored.withoutLocation();
    expect(noLoc.showAddress, isFalse);
    expect(noLoc.showCoordinates, isFalse);
    expect(noLoc.showMiniMap, isFalse);
    expect(noLoc.showProjectTitle, isTrue);
    expect(noLoc.showDateTime, isTrue);
  });

  testWidgets('LiveWatermarkBanner renders without crashing', (tester) async {
    final telemetry = GpsTelemetry(
      latitude: -6.208832,
      longitude: 106.845618,
      address: 'Jl. Sudirman No. 45, Jakarta',
    );
    const config = WatermarkConfig();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveWatermarkBanner(
            telemetry: telemetry,
            config: config,
          ),
        ),
      ),
    );

    expect(find.text('Geo Map Camera'), findsOneWidget);
    expect(find.text('Note : Dokumentasi Lapangan'), findsOneWidget);
    expect(find.text('Jl. Sudirman No. 45, Jakarta'), findsOneWidget);
  });
}
