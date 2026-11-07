import 'dart:io';

class MediaItem {
  final String path;
  final String name;
  final bool isVideo;
  final DateTime dateTime;
  final int sizeBytes;

  MediaItem({
    required this.path,
    required this.name,
    required this.isVideo,
    required this.dateTime,
    this.sizeBytes = 0,
  });

  File get file => File(path);

  bool get exists => File(path).existsSync();

  String get formattedDate {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    final monthName = (dateTime.month >= 1 && dateTime.month <= 12)
        ? months[dateTime.month - 1]
        : '${dateTime.month}';
    final hh = dateTime.hour.toString().padLeft(2, '0');
    final mm = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.day} $monthName ${dateTime.year}, $hh:$mm';
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

