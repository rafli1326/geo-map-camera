import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/gps_telemetry.dart';
import '../models/watermark_config.dart';

class LiveWatermarkBanner extends StatefulWidget {
  final GpsTelemetry telemetry;
  final WatermarkConfig config;
  final bool isInteractive;

  const LiveWatermarkBanner({
    super.key,
    required this.telemetry,
    required this.config,
    this.isInteractive = false,
  });

  @override
  State<LiveWatermarkBanner> createState() => _LiveWatermarkBannerState();
}

class _LiveWatermarkBannerState extends State<LiveWatermarkBanner> {
  final MapController _mapController = MapController();
  bool _mapReady = false;

  @override
  void didUpdateWidget(covariant LiveWatermarkBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_mapReady && widget.config.showMiniMap) {
      final latDiff = (oldWidget.telemetry.latitude - widget.telemetry.latitude).abs();
      final lonDiff = (oldWidget.telemetry.longitude - widget.telemetry.longitude).abs();
      if (latDiff > 0.00005 || lonDiff > 0.00005) {
        try {
          _mapController.move(
            LatLng(widget.telemetry.latitude, widget.telemetry.longitude),
            16.0,
          );
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    final telemetry = widget.telemetry;
    final config = widget.config;
    final showMap = config.showMiniMap &&
        (telemetry.latitude != 0.0 || telemetry.longitude != 0.0);
    final noteLine = _buildNoteLine(config);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Top-right small branding tab "[📷 Geo Map Camera]"
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: const BoxDecoration(
              color: Color(0xAD000000),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFACC15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    size: 8.5,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Geo Map Camera',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9.0,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Main Row: Left Satellite Mini-Map + Right Dark Info Card
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showMap) ...[
              _buildMiniMap(telemetry),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 96),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xAD000000),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                      // 1. Header: City, Province, Country + Flag
                      if (config.showAddress) ...[
                        Text(
                          telemetry.locationHeader,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            height: 1.18,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2.5),
                        // 2. Detailed Street / Plus Code / Postal Code Address
                        Text(
                          telemetry.fullAddressLine,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.2,
                            fontWeight: FontWeight.w400,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                      ],

                      // 3. Lat & Long (+ optional Altitude)
                      if (config.showCoordinates) ...[
                        Text(
                          _buildCoordText(telemetry, config),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.2,
                            fontWeight: FontWeight.w400,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                      ],

                      // 4. Day, Date, Time AM/PM GMT Offset
                      if (config.showDateTime) ...[
                        Text(
                          telemetry.dateTimeGmtLine,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.2,
                            fontWeight: FontWeight.w400,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      // 5. Note Line
                      if (noteLine.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          noteLine,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.2,
                            fontWeight: FontWeight.w400,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  String _buildCoordText(GpsTelemetry telemetry, WatermarkConfig config) {
    final base = config.coordFormat == 'dms'
        ? telemetry.latLongLineDms
        : telemetry.latLongLineDecimal;
    if (config.showAltitude && telemetry.altitude != 0.0) {
      return '$base • ${telemetry.formattedAltitude}';
    }
    return base;
  }

  Widget _buildMiniMap(GpsTelemetry telemetry) {
    final latLng = LatLng(telemetry.latitude, telemetry.longitude);
    final mapKey = ValueKey(
      '${telemetry.latitude.toStringAsFixed(3)}_${telemetry.longitude.toStringAsFixed(3)}',
    );

    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: const Color(0xFF1E3524),
        borderRadius: BorderRadius.circular(7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Satellite Imagery Tile Layer (Esri World Imagery)
          IgnorePointer(
            ignoring: !widget.isInteractive,
            child: FlutterMap(
              key: mapKey,
              mapController: _mapController,
              options: MapOptions(
                initialCenter: latLng,
                initialZoom: 16.0,
                onMapReady: () {
                  _mapReady = true;
                },
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                  fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.geomap.camera',
                ),
              ],
            ),
          ),

          // Center red Google-style location pin marker
          Center(
            child: Transform.translate(
              offset: const Offset(0, -9),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.location_on,
                    color: Color(0xFFEA4335),
                    size: 28,
                    shadows: [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 4,
                        offset: Offset(0, 1.5),
                      ),
                    ],
                  ),
                  Transform.translate(
                    offset: const Offset(0, -3),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF7F1D1D),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // "SATELIT" badge in bottom-left corner
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: const Color(0xB8000000),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'SATELIT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 7.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
