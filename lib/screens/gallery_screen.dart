import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/media_item.dart';
import '../services/storage_service.dart';
import 'media_viewer_screen.dart';

enum _GalleryFilter { all, photos, videos }

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  static const Color _accentYellow = Color(0xFFFACC15);
  static const Color _cardBg = Color(0xFF141417);

  _GalleryFilter _filter = _GalleryFilter.all;
  bool _selectionMode = false;
  final Set<String> _selectedPaths = <String>{};

  @override
  void initState() {
    super.initState();
    StorageService().loadMediaItems();
  }

  List<MediaItem> _applyFilter(List<MediaItem> all) {
    switch (_filter) {
      case _GalleryFilter.photos:
        return all.where((item) => !item.isVideo).toList();
      case _GalleryFilter.videos:
        return all.where((item) => item.isVideo).toList();
      case _GalleryFilter.all:
        return all;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _dateGroupLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(itemDay).inDays;

    if (diff == 0) return 'Hari Ini';
    if (diff == 1) return 'Kemarin';

    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    final mName = (dt.month >= 1 && dt.month <= 12) ? months[dt.month - 1] : '${dt.month}';
    return '${dt.day} $mName ${dt.year}';
  }

  String _timeLabel(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  void _toggleSelect(MediaItem item) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedPaths.contains(item.path)) {
        _selectedPaths.remove(item.path);
        if (_selectedPaths.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedPaths.add(item.path);
        _selectionMode = true;
      }
    });
  }

  void _selectAll(List<MediaItem> visibleItems) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedPaths.length == visibleItems.length) {
        _selectedPaths.clear();
        _selectionMode = false;
      } else {
        _selectedPaths
          ..clear()
          ..addAll(visibleItems.map((e) => e.path));
        _selectionMode = true;
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
    });
  }

  Future<void> _shareSelected(List<MediaItem> allItems) async {
    final selected = allItems.where((i) => _selectedPaths.contains(i.path)).toList();
    if (selected.isEmpty) return;

    HapticFeedback.selectionClick();
    await SharePlus.instance.share(
      ShareParams(
        files: selected.map((e) => XFile(e.path)).toList(),
        text: 'Dokumentasi Geo Map Camera (${selected.length} item)',
      ),
    );
  }

  Future<void> _deleteSelected(List<MediaItem> allItems) async {
    final selected = allItems.where((i) => _selectedPaths.contains(i.path)).toList();
    if (selected.isEmpty) return;

    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Hapus ${selected.length} Dokumentasi?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'Item yang dipilih akan dihapus permanen dari penyimpanan perangkat Anda.',
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
      final storage = StorageService();
      for (final item in selected) {
        await storage.deleteMedia(item);
      }
      _exitSelectionMode();
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = StorageService();

    return ListenableBuilder(
      listenable: storage,
      builder: (context, _) {
        final allItems = storage.mediaItems;
        final visibleItems = _applyFilter(allItems);

        final int photoCount = allItems.where((e) => !e.isVideo).length;
        final int videoCount = allItems.where((e) => e.isVideo).length;
        final int totalBytes = allItems.fold<int>(0, (sum, e) => sum + e.sizeBytes);

        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0C),
          appBar: _buildAppBar(storage, visibleItems),
          body: Column(
            children: [
              // 1. Storage Summary & Filter Header
              _buildHeaderSection(
                totalCount: allItems.length,
                photoCount: photoCount,
                videoCount: videoCount,
                totalSizeLabel: _formatBytes(totalBytes),
              ),

              // 2. Media Content (Grouped by Date)
              Expanded(
                child: visibleItems.isEmpty
                    ? _buildEmptyState()
                    : _buildGroupedMediaList(visibleItems),
              ),
            ],
          ),
          bottomNavigationBar: _selectionMode && _selectedPaths.isNotEmpty
              ? _buildSelectionBottomBar(allItems)
              : null,
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(StorageService storage, List<MediaItem> visibleItems) {
    if (_selectionMode) {
      final allSelected =
          visibleItems.isNotEmpty && _selectedPaths.length == visibleItems.length;
      return AppBar(
        backgroundColor: const Color(0xFF141417),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 22),
          onPressed: _exitSelectionMode,
        ),
        title: Text(
          '${_selectedPaths.length} Dipilih',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _selectAll(visibleItems),
            icon: Icon(
              allSelected ? Icons.deselect : Icons.select_all,
              color: _accentYellow,
              size: 18,
            ),
            label: Text(
              allSelected ? 'Batal Semua' : 'Pilih Semua',
              style: const TextStyle(
                color: _accentYellow,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );
    }

    return AppBar(
      backgroundColor: const Color(0xFF0A0A0C),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 19),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Galeri Dokumentasi',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      actions: [
        if (visibleItems.isNotEmpty)
          IconButton(
            tooltip: 'Pilih Beberapa',
            icon: const Icon(Icons.checklist_rounded, color: Colors.white, size: 22),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _selectionMode = true);
            },
          ),
        IconButton(
          tooltip: 'Muat Ulang',
          icon: const Icon(Icons.refresh_rounded, color: _accentYellow, size: 22),
          onPressed: () {
            HapticFeedback.selectionClick();
            storage.loadMediaItems();
          },
        ),
      ],
    );
  }

  Widget _buildHeaderSection({
    required int totalCount,
    required int photoCount,
    required int videoCount,
    required String totalSizeLabel,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0C),
        border: Border(bottom: BorderSide(color: Colors.white12, width: 0.8)),
      ),
      child: Column(
        children: [
          // Storage Summary Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatColumn(Icons.perm_media_outlined, '$totalCount', 'Total File'),
                Container(width: 1, height: 26, color: Colors.white12),
                _buildStatColumn(Icons.photo_camera_outlined, '$photoCount', 'Foto GPS'),
                Container(width: 1, height: 26, color: Colors.white12),
                _buildStatColumn(Icons.videocam_outlined, '$videoCount', 'Video GPS'),
                Container(width: 1, height: 26, color: Colors.white12),
                _buildStatColumn(Icons.sd_storage_outlined, totalSizeLabel, 'Ukuran'),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Filter Pills Row: Semua | Foto | Video
          Row(
            children: [
              _buildFilterChip(
                label: 'Semua ($totalCount)',
                selected: _filter == _GalleryFilter.all,
                onTap: () => setState(() => _filter = _GalleryFilter.all),
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                label: 'Foto ($photoCount)',
                selected: _filter == _GalleryFilter.photos,
                onTap: () => setState(() => _filter = _GalleryFilter.photos),
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                label: 'Video ($videoCount)',
                selected: _filter == _GalleryFilter.videos,
                onTap: () => setState(() => _filter = _GalleryFilter.videos),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _accentYellow, size: 17),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _accentYellow : _cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _accentYellow : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildGroupedMediaList(List<MediaItem> visibleItems) {
    // Group items by date string while preserving chronological order
    final groups = <String, List<MediaItem>>{};
    for (final item in visibleItems) {
      final key = _dateGroupLabel(item.dateTime);
      groups.putIfAbsent(key, () => <MediaItem>[]).add(item);
    }

    final groupKeys = groups.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      itemCount: groupKeys.length,
      itemBuilder: (context, gIndex) {
        final dateLabel = groupKeys[gIndex];
        final groupItems = groups[dateLabel]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 6, bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 3.5,
                    height: 14,
                    decoration: BoxDecoration(
                      color: _accentYellow,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${groupItems.length})',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 7,
                mainAxisSpacing: 7,
                childAspectRatio: 0.88,
              ),
              itemCount: groupItems.length,
              itemBuilder: (context, index) {
                final item = groupItems[index];
                final globalIndex = visibleItems.indexOf(item);
                return _buildGridTile(item, visibleItems, globalIndex);
              },
            ),
            const SizedBox(height: 10),
          ],
        );
      },
    );
  }

  Widget _buildGridTile(MediaItem item, List<MediaItem> visibleItems, int globalIndex) {
    final bool isSelected = _selectedPaths.contains(item.path);

    return GestureDetector(
      onTap: () {
        if (_selectionMode) {
          _toggleSelect(item);
        } else {
          HapticFeedback.selectionClick();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MediaViewerScreen(
                item: item,
                allItems: visibleItems,
                initialIndex: globalIndex,
              ),
            ),
          );
        }
      },
      onLongPress: () => _toggleSelect(item),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? _accentYellow : Colors.white12,
            width: isSelected ? 2.2 : 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail Image / Video Placeholder
            if (item.isVideo)
              Container(
                color: const Color(0xFF18181B),
                child: const Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: _accentYellow,
                    size: 38,
                  ),
                ),
              )
            else
              Image.file(
                File(item.path),
                fit: BoxFit.cover,
                cacheWidth: 360,
                errorBuilder: (_, _, _) => Container(
                  color: const Color(0xFF18181B),
                  child: const Icon(Icons.broken_image_outlined, color: Colors.white24),
                ),
              ),

            // Top-left size / video badge
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.isVideo) ...[
                      const Icon(Icons.videocam, color: Color(0xFFEF4444), size: 11),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      item.isVideo ? 'VIDEO' : item.formattedSize,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Selection checkmark circle in top-right
            if (_selectionMode)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: isSelected ? _accentYellow : Colors.black54,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? _accentYellow : Colors.white70,
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.black)
                      : null,
                ),
              ),

            // Bottom time & size bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xE6000000), Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time, color: _accentYellow, size: 10),
                        const SizedBox(width: 3),
                        Text(
                          _timeLabel(item.dateTime),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    if (item.isVideo)
                      Text(
                        item.formattedSize,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 8.5,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionBottomBar(List<MediaItem> allItems) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: Color(0xFF141417),
          border: Border(top: BorderSide(color: Colors.white12, width: 0.8)),
        ),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _shareSelected(allItems),
                icon: const Icon(Icons.share_outlined, size: 18),
                label: Text(
                  'Bagikan (${_selectedPaths.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentYellow,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _deleteSelected(allItems),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(
                  'Hapus (${_selectedPaths.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    String emptyTitle = 'Belum Ada Dokumentasi';
    String emptySub =
        'Foto dan video berstempel GPS yang Anda ambil akan tersimpan rapi di sini dan di folder Pictures perangkat Anda.';
    if (_filter == _GalleryFilter.photos) {
      emptyTitle = 'Belum Ada Foto GPS';
      emptySub = 'Belum ada foto dokumentasi yang tersimpan.';
    } else if (_filter == _GalleryFilter.videos) {
      emptyTitle = 'Belum Ada Video GPS';
      emptySub = 'Belum ada rekaman video dokumentasi yang tersimpan.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _cardBg,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white12, width: 1.5),
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                color: _accentYellow,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              emptyTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              emptySub,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
