import 'package:intl/intl.dart';

class GpsTelemetry {
  final double latitude;
  final double longitude;
  final double altitude;
  final double accuracy;
  final double speed;
  final double heading;
  final DateTime timestamp;
  final String? address;
  final String? street;
  final String? subLocality;
  final String? locality;
  final String? subAdministrativeArea;
  final String? administrativeArea;
  final String? postalCode;
  final bool isMocked;

  GpsTelemetry({
    required this.latitude,
    required this.longitude,
    this.altitude = 0.0,
    this.accuracy = 0.0,
    this.speed = 0.0,
    this.heading = 0.0,
    DateTime? timestamp,
    this.address,
    this.street,
    this.subLocality,
    this.locality,
    this.subAdministrativeArea,
    this.administrativeArea,
    this.postalCode,
    this.isMocked = false,
  }) : timestamp = timestamp ?? DateTime.now();

  // Decimal coordinates formatted: -6.208832°, 106.845618°
  String get formattedCoordDecimal {
    final latSign = latitude >= 0 ? 'N' : 'S';
    final lonSign = longitude >= 0 ? 'E' : 'W';
    return '${latitude.abs().toStringAsFixed(6)}° $latSign, ${longitude.abs().toStringAsFixed(6)}° $lonSign';
  }

  // DMS coordinates: 6°12'31.8" S, 106°50'44.2" E
  String get formattedCoordDms {
    return '${_toDms(latitude, isLat: true)}, ${_toDms(longitude, isLat: false)}';
  }

  static String _toDms(double val, {required bool isLat}) {
    final sign = isLat ? (val >= 0 ? 'N' : 'S') : (val >= 0 ? 'E' : 'W');
    final absVal = val.abs();
    final degrees = absVal.floor();
    final minutesDouble = (absVal - degrees) * 60;
    final minutes = minutesDouble.floor();
    final seconds = (minutesDouble - minutes) * 60;
    return '$degrees°$minutes\'${seconds.toStringAsFixed(1)}"$sign';
  }

  String get formattedDate {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    final monthName = (timestamp.month >= 1 && timestamp.month <= 12)
        ? months[timestamp.month - 1]
        : '${timestamp.month}';
    return '${timestamp.day} $monthName ${timestamp.year}';
  }

  String get timezoneLabel {
    final hours = timestamp.timeZoneOffset.inHours;
    if (hours == 7) return 'WIB';
    if (hours == 8) return 'WITA';
    if (hours == 9) return 'WIT';
    final sign = hours >= 0 ? '+' : '';
    return 'UTC$sign$hours';
  }

  String get formattedTime {
    return '${DateFormat('HH:mm:ss').format(timestamp)} $timezoneLabel';
  }

  String get formattedAltitude {
    return '${altitude.toStringAsFixed(1)} m MDPL';
  }

  String get formattedAccuracy {
    return '±${accuracy.toStringAsFixed(1)} m';
  }

  /// Header line like "Tanjung, Kalimantan Selatan, Indonesia 🇮🇩"
  String get locationHeader {
    String cleanCity(String raw) {
      return raw
          .replaceFirst(RegExp(r'^(Kecamatan|Kec\.|Kabupaten|Kab\.|Kota)\s+', caseSensitive: false), '')
          .trim();
    }

    final parts = <String>[];
    if (locality != null && locality!.trim().isNotEmpty) {
      parts.add(cleanCity(locality!));
    } else if (subAdministrativeArea != null && subAdministrativeArea!.trim().isNotEmpty) {
      parts.add(cleanCity(subAdministrativeArea!));
    } else if (subLocality != null && subLocality!.trim().isNotEmpty) {
      parts.add(subLocality!.trim());
    }

    if (administrativeArea != null && administrativeArea!.trim().isNotEmpty) {
      final admin = administrativeArea!.trim();
      if (!parts.any((p) => p.toLowerCase() == admin.toLowerCase())) {
        parts.add(admin);
      }
    }

    if (parts.isNotEmpty) {
      return '${parts.join(', ')}, Indonesia 🇮🇩';
    }
    if (address != null && address!.trim().isNotEmpty) {
      return '${address!.split(',').take(2).join(', ').trim()} 🇮🇩';
    }
    return 'Indonesia 🇮🇩';
  }

  /// Full detailed address line (including Plus Code / postal code when available)
  String get fullAddressLine {
    if (street != null && street!.contains(',') && street!.trim().length > 15) {
      return street!.trim();
    }
    final base = displayAddress;
    if (postalCode != null && postalCode!.trim().isNotEmpty && !base.contains(postalCode!.trim())) {
      return '$base ${postalCode!.trim()}, Indonesia';
    }
    return base;
  }

  /// "Lat -2.054752° Long 115.454089°"
  String get latLongLineDecimal {
    return 'Lat ${latitude.toStringAsFixed(6)}° Long ${longitude.toStringAsFixed(6)}°';
  }

  /// "Lat 2°3'17.1"S Long 115°27'14.7"E"
  String get latLongLineDms {
    return 'Lat ${_toDms(latitude, isLat: true)} Long ${_toDms(longitude, isLat: false)}';
  }

  /// "Saturday, 07/11/2026 10:48:15 AM GMT +08:00"
  String get dateTimeGmtLine {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final dayName = (timestamp.weekday >= 1 && timestamp.weekday <= 7)
        ? days[timestamp.weekday - 1]
        : '';
    final dd = timestamp.day.toString().padLeft(2, '0');
    final mm = timestamp.month.toString().padLeft(2, '0');
    final yyyy = timestamp.year;
    final hour12 = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final hh = hour12.toString().padLeft(2, '0');
    final min = timestamp.minute.toString().padLeft(2, '0');
    final sec = timestamp.second.toString().padLeft(2, '0');
    final amPm = timestamp.hour >= 12 ? 'PM' : 'AM';

    final offset = timestamp.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final offH = offset.inHours.abs().toString().padLeft(2, '0');
    final offM = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');

    return '$dayName, $dd/$mm/$yyyy $hh:$min:$sec $amPm GMT $sign$offH:$offM';
  }

  static String formatCleanAddress({
    String? street,
    String? subLocality,
    String? locality,
    String? subAdministrativeArea,
    String? administrativeArea,
    String? fallbackAddress,
  }) {
    final plusCodeRegex = RegExp(r'^[A-Z0-9]{2,8}\+[A-Z0-9]{2,5}$', caseSensitive: false);
    final parts = <String>[];

    void addUnique(String? raw) {
      if (raw == null) return;
      final candidate = raw.trim();
      if (candidate.isEmpty) return;
      if (plusCodeRegex.hasMatch(candidate)) return;
      if (candidate.toLowerCase() == 'indonesia') return;

      final lower = candidate.toLowerCase();
      final alreadyExists = parts.any((existing) {
        final exLower = existing.toLowerCase();
        return exLower == lower || exLower.contains(lower) || lower.contains(exLower);
      });
      if (!alreadyExists) {
        parts.add(candidate);
      }
    }

    if (street != null && street.trim().isNotEmpty) {
      // Android Geocoder often puts the entire address line in `street`.
      // Extract only the first segment (actual street/thoroughfare) if not a Plus Code.
      final firstSegment = street.split(',').first.trim();
      addUnique(firstSegment);
    }

    addUnique(subLocality);
    addUnique(locality);
    addUnique(subAdministrativeArea);
    addUnique(administrativeArea);

    if (parts.isNotEmpty) {
      return parts.join(', ');
    }

    if (fallbackAddress != null && fallbackAddress.trim().isNotEmpty) {
      return fallbackAddress.trim();
    }

    if (street != null && street.trim().isNotEmpty) {
      return street.trim();
    }

    return 'Lokasi GPS Terkunci';
  }

  String get displayAddress {
    if (subLocality != null ||
        locality != null ||
        subAdministrativeArea != null ||
        administrativeArea != null) {
      return formatCleanAddress(
        street: street,
        subLocality: subLocality,
        locality: locality,
        subAdministrativeArea: subAdministrativeArea,
        administrativeArea: administrativeArea,
        fallbackAddress: address,
      );
    }

    if (address != null && address!.trim().isNotEmpty) {
      return address!.trim();
    }

    return 'Lokasi GPS Terkunci';
  }

  GpsTelemetry copyWith({
    double? latitude,
    double? longitude,
    double? altitude,
    double? accuracy,
    double? speed,
    double? heading,
    DateTime? timestamp,
    String? address,
    String? street,
    String? subLocality,
    String? locality,
    String? subAdministrativeArea,
    String? administrativeArea,
    String? postalCode,
    bool? isMocked,
  }) {
    return GpsTelemetry(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      accuracy: accuracy ?? this.accuracy,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      timestamp: timestamp ?? this.timestamp,
      address: address ?? this.address,
      street: street ?? this.street,
      subLocality: subLocality ?? this.subLocality,
      locality: locality ?? this.locality,
      subAdministrativeArea: subAdministrativeArea ?? this.subAdministrativeArea,
      administrativeArea: administrativeArea ?? this.administrativeArea,
      postalCode: postalCode ?? this.postalCode,
      isMocked: isMocked ?? this.isMocked,
    );
  }
}

