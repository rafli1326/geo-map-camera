import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../models/media_item.dart';
import '../services/storage_service.dart';

class MediaViewerScreen extends StatefulWidget {
  final MediaItem item;
  final List<MediaItem>? allItems;
  final int initialIndex;

  const MediaViewerScreen({
    super.key,
    required this.item,
    this.allItems,
    this.initialIndex = 0,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  static const Color _accentYellow = Color(0xFFFACC15);

  late List<MediaItem> _items;
  late int _currentIndex;
  late PageController _pageController;

  VideoPlayerController? _videoController;
  bool _isPlaying = false;

  MediaItem get _currentItem => _items[_currentIndex];

  @override
  void initState() {
    super.initState();
    _items = (widget.allItems != null && widget.allItems!.isNotEmpty)
        ? List<MediaItem>.from(widget.allItems!)
        : <MediaItem>[widget.item];
    _currentIndex = widget.initialIndex.clamp(0, _items.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _setupCurrentMedia();
  }

  Future<void> _setupCurrentMedia() async {
    final prev = _videoController;
    _videoController = null;
    _isPlaying = false;
    await prev?.dispose();

    if (!mounted) return;
    setState(() {});

    final current = _currentItem;
    if (current.isVideo) {
      final controller = VideoPlayerController.file(File(current.path));
      try {
        await controller.initialize();
        controller.addListener(() {
          if (mounted) {
            final playing = controller.value.isPlaying;
            if (playing != _isPlaying) {
              setState(() => _isPlaying = playing);
            }
          }
        });
        if (mounted && _currentItem.path == current.path) {
          setState(() {
            _videoController = controller;
          });
        } else {
          await controller.dispose();
        }
      } catch (e) {
        debugPrint('Error initializing video player: $e');
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _shareMedia() {
    HapticFeedback.selectionClick();
    final current = _currentItem;
    SharePlus.instance.share(
      ShareParams(
        files: [XFile(current.path)],
        text: 'Dokumentasi Geo Map Camera: ${current.name}',
      ),
    );
  }

  Future<void> _confirmDelete() async {
    HapticFeedback.selectionClick();
    final current = _currentItem;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141417),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Hapus Dokumentasi?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'Apakah Anda yakin ingin menghapus "${current.name}" dari perangkat?',
          style: const TextStyle(color: Colors.white70, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: const Text('Hapus', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await StorageService().deleteMedia(current);
      if (!mounted) return;
      if (_items.length <= 1) {
        Navigator.pop(context);
      } else {
        setState(() {
          _items.removeAt(_currentIndex);
          if (_currentIndex >= _items.length) {
            _currentIndex = _items.length - 1;
          }
        });
        _setupCurrentMedia();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentItem;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0C),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 19),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              current.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            Text(
              '${current.formattedDate}  •  ${current.formattedSize}',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
        actions: [
          if (_items.length > 1)
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${_items.length}',
                  style: const TextStyle(
                    color: _accentYellow,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _items.length,
        onPageChanged: (idx) {
          setState(() => _currentIndex = idx);
          _setupCurrentMedia();
        },
        itemBuilder: (context, index) {
          final item = _items[index];
          if (item.isVideo) {
            return _buildVideoPlayer(item);
          }
          return _buildImageViewer(item);
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0A0A0C),
            border: Border(top: BorderSide(color: Colors.white12, width: 0.8)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _shareMedia,
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text(
                    'Bagikan Dokumentasi',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentYellow,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: _confirmDelete,
                icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF18181B),
                  padding: const EdgeInsets.all(13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Colors.white12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageViewer(MediaItem item) {
    return Center(
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 4.5,
        child: Image.file(
          File(item.path),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Center(
            child: Text(
              'Gagal memuat gambar',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer(MediaItem item) {
    if (item.path != _currentItem.path ||
        _videoController == null ||
        !_videoController!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(_accentYellow),
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          ),
        ),

        // Play / Pause button overlay
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              if (_videoController!.value.isPlaying) {
                _videoController!.pause();
              } else {
                _videoController!.play();
              }
            });
          },
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white30, width: 1.5),
            ),
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: _accentYellow,
              size: 38,
            ),
          ),
        ),

        // Video Progress Bar at bottom
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: VideoProgressIndicator(
            _videoController!,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: _accentYellow,
              bufferedColor: Colors.white24,
              backgroundColor: Colors.white12,
            ),
          ),
        ),
      ],
    );
  }
}
