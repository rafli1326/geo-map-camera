import 'dart:convert';

class WatermarkConfig {
  final String projectTitle;
  final String officerName;
  final bool showAddress;
  final bool showCoordinates;
  final bool showDateTime;
  final bool showMiniMap;
  final bool showProjectTitle;
  final bool showOfficerName;
  final bool showAltitude;
  final String coordFormat; // 'decimal' or 'dms'

  const WatermarkConfig({
    this.projectTitle = 'Dokumentasi Lapangan',
    this.officerName = '',
    this.showAddress = true,
    this.showCoordinates = true,
    this.showDateTime = true,
    this.showMiniMap = true,
    this.showProjectTitle = true,
    this.showOfficerName = true,
    this.showAltitude = false,
    this.coordFormat = 'decimal',
  });

  WatermarkConfig copyWith({
    String? projectTitle,
    String? officerName,
    bool? showAddress,
    bool? showCoordinates,
    bool? showDateTime,
    bool? showMiniMap,
    bool? showProjectTitle,
    bool? showOfficerName,
    bool? showAltitude,
    String? coordFormat,
  }) {
    return WatermarkConfig(
      projectTitle: projectTitle ?? this.projectTitle,
      officerName: officerName ?? this.officerName,
      showAddress: showAddress ?? this.showAddress,
      showCoordinates: showCoordinates ?? this.showCoordinates,
      showDateTime: showDateTime ?? this.showDateTime,
      showMiniMap: showMiniMap ?? this.showMiniMap,
      showProjectTitle: showProjectTitle ?? this.showProjectTitle,
      showOfficerName: showOfficerName ?? this.showOfficerName,
      showAltitude: showAltitude ?? this.showAltitude,
      coordFormat: coordFormat ?? this.coordFormat,
    );
  }

  /// Config to use when there is no valid GPS fix: keep title, officer and
  /// date/time, hide every location element.
  WatermarkConfig withoutLocation() => copyWith(
        showAddress: false,
        showCoordinates: false,
        showMiniMap: false,
        showAltitude: false,
      );

  Map<String, dynamic> toMap() {
    return {
      'projectTitle': projectTitle,
      'officerName': officerName,
      'showAddress': showAddress,
      'showCoordinates': showCoordinates,
      'showDateTime': showDateTime,
      'showMiniMap': showMiniMap,
      'showProjectTitle': showProjectTitle,
      'showOfficerName': showOfficerName,
      'showAltitude': showAltitude,
      'coordFormat': coordFormat,
    };
  }

  factory WatermarkConfig.fromMap(Map<String, dynamic> map) {
    return WatermarkConfig(
      projectTitle: map['projectTitle'] ?? 'Dokumentasi Lapangan',
      officerName: map['officerName'] ?? '',
      showAddress: map['showAddress'] ?? true,
      showCoordinates: map['showCoordinates'] ?? true,
      showDateTime: map['showDateTime'] ?? true,
      showMiniMap: map['showMiniMap'] ?? true,
      showProjectTitle: map['showProjectTitle'] ?? true,
      showOfficerName: map['showOfficerName'] ?? true,
      showAltitude: map['showAltitude'] ?? false,
      coordFormat: map['coordFormat'] ?? 'decimal',
    );
  }

  String toJson() => json.encode(toMap());

  factory WatermarkConfig.fromJson(String source) =>
      WatermarkConfig.fromMap(json.decode(source));
}

