import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/media_item.dart';
import '../models/gps_telemetry.dart';
import '../models/watermark_config.dart';
import 'video_watermark_service.dart';

class StorageService extends ChangeNotifier {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  Directory? _storageDir;
  List<MediaItem> _mediaItems = [];
  MediaItem? _lastSavedItem;

  List<MediaItem> get mediaItems => _mediaItems;
  MediaItem? get lastSavedItem => _lastSavedItem;

  Future<Directory> getStorageDirectory() async {
    if (_storageDir != null && _storageDir!.existsSync()) {
      return _storageDir!;
    }

    Directory dir;
    if (Platform.isAndroid) {
      final picturesDir = Directory('/storage/emulated/0/Pictures/Geo Map Camera');
      try {
        if (!picturesDir.existsSync()) {
          picturesDir.createSync(recursive: true);
        }
        dir = picturesDir;
      } catch (e) {
        debugPrint('Cannot write to /storage/emulated/0/Pictures: $e');
        final extDir = await getExternalStorageDirectory();
        dir = Directory('${extDir?.path ?? (await getApplicationDocumentsDirectory()).path}/Geo_Map_Camera');
        if (!dir.existsSync()) dir.createSync(recursive: true);
      }
    } else {
      final docDir = await getApplicationDocumentsDirectory();
      dir = Directory('${docDir.path}/Geo_Map_Camera');
      if (!dir.existsSync()) dir.createSync(recursive: true);
    }

    _storageDir = dir;
    return dir;
  }

  Future<void> loadMediaItems() async {
    try {
      final dir = await getStorageDirectory();
      final items = <MediaItem>[];

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          final path = entity.path.toLowerCase();
          final isImage = path.endsWith('.jpg') ||
              path.endsWith('.jpeg') ||
              path.endsWith('.png');
          final isVideo = path.endsWith('.mp4');

          if (isImage || isVideo) {
            final stat = await entity.stat();
            items.add(MediaItem(
              path: entity.path,
              name: entity.uri.pathSegments.last,
              isVideo: isVideo,
              dateTime: stat.modified,
              sizeBytes: stat.size,
            ));
          }
        }
      }

      // Sort newest first
      items.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      _mediaItems = items;
      if (items.isNotEmpty) {
        _lastSavedItem = items.first;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading media items: $e');
    }
  }

  /// Avoids overwriting when several photos are taken within the same second.
  String _uniqueName(Directory dir, String base, String ext) {
    var name = '$base.$ext';
    var i = 1;
    while (File('${dir.path}/$name').existsSync()) {
      name = '${base}_$i.$ext';
      i++;
    }
    return name;
  }

  Future<MediaItem> savePhoto(Uint8List jpgBytes) async {
    final dir = await getStorageDirectory();
    final now = DateTime.now();
    final timeStr = DateFormat('yyyyMMdd_HHmmss').format(now);
    final fileName = _uniqueName(dir, 'GPS_$timeStr', 'jpg');
    final filePath = '${dir.path}/$fileName';

    final file = File(filePath);
    await file.writeAsBytes(jpgBytes, flush: true);

    final item = MediaItem(
      path: filePath,
      name: fileName,
      isVideo: false,
      dateTime: now,
      sizeBytes: jpgBytes.length,
    );

    _lastSavedItem = item;
    _mediaItems.insert(0, item);
    notifyListeners();

    return item;
  }

  Future<MediaItem> saveVideo(String tempVideoPath) async {
    final dir = await getStorageDirectory();
    final now = DateTime.now();
    final timeStr = DateFormat('yyyyMMdd_HHmmss').format(now);
    final fileName = _uniqueName(dir, 'VID_$timeStr', 'mp4');
    final targetPath = '${dir.path}/$fileName';

    final tempFile = File(tempVideoPath);
    await tempFile.copy(targetPath);

    final targetFile = File(targetPath);
    final stat = await targetFile.stat();

    final item = MediaItem(
      path: targetPath,
      name: fileName,
      isVideo: true,
      dateTime: now,
      sizeBytes: stat.size,
    );

    _lastSavedItem = item;
    _mediaItems.insert(0, item);
    notifyListeners();

    // Clean up temp file
    try {
      await tempFile.delete();
    } catch (_) {}

    return item;
  }

  Future<MediaItem> saveWatermarkedVideo({
    required String rawVideoPath,
    required List<GpsTelemetry> samples,
    required WatermarkConfig config,
    int frameWidth = 1080,
    int frameHeight = 1920,
    int rotationDegrees = 0,
  }) async {
    final dir = await getStorageDirectory();
    final now = DateTime.now();
    final timeStr = DateFormat('yyyyMMdd_HHmmss').format(now);
    final fileName = _uniqueName(dir, 'VID_$timeStr', 'mp4');
    final targetPath = '${dir.path}/$fileName';

    try {
      await VideoWatermarkService().burnVideoWatermark(
        rawVideoPath: rawVideoPath,
        outputPath: targetPath,
        samples: samples,
        config: config,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        rotationDegrees: rotationDegrees,
      );
    } catch (e) {
      debugPrint('Video watermark failed, falling back to copy raw video: $e');
      final tempFile = File(rawVideoPath);
      await tempFile.copy(targetPath);
    }

    final targetFile = File(targetPath);
    final stat = await targetFile.stat();

    final item = MediaItem(
      path: targetPath,
      name: fileName,
      isVideo: true,
      dateTime: now,
      sizeBytes: stat.size,
    );

    _lastSavedItem = item;
    _mediaItems.insert(0, item);
    notifyListeners();

    // Clean up raw temp file
    try {
      final rawFile = File(rawVideoPath);
      if (rawFile.existsSync()) {
        await rawFile.delete();
      }
    } catch (_) {}

    return item;
  }

  Future<bool> deleteMedia(MediaItem item) async {
    try {
      final storageDir = await getStorageDirectory();
      final canonicalStorage = storageDir.resolveSymbolicLinksSync();
      final file = File(item.path);
      if (!file.existsSync()) return false;

      final canonicalFile = file.resolveSymbolicLinksSync();
      // Security: Only allow deleting files strictly inside the app storage folder
      if (!canonicalFile.startsWith(canonicalStorage)) {
        debugPrint('Security Warning: Blocked attempt to delete file outside storage directory: ${item.path}');
        return false;
      }

      await file.delete();
      _mediaItems.removeWhere((element) => element.path == item.path);
      if (_lastSavedItem?.path == item.path) {
        _lastSavedItem = _mediaItems.isNotEmpty ? _mediaItems.first : null;
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error deleting media: $e');
      return false;
    }
  }
}
