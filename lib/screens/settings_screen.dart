import 'package:flutter/material.dart';
import '../models/watermark_config.dart';
import '../services/location_service.dart';
import '../services/preferences_service.dart';
import '../widgets/live_watermark_banner.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _projectController;
  late TextEditingController _officerController;
  late WatermarkConfig _currentConfig;

  @override
  void initState() {
    super.initState();
    _currentConfig = PreferencesService().config;
    _projectController = TextEditingController(text: _currentConfig.projectTitle);
    _officerController = TextEditingController(text: _currentConfig.officerName);
  }

  @override
  void dispose() {
    _projectController.dispose();
    _officerController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    final updated = _currentConfig.copyWith(
      projectTitle: _projectController.text.trim(),
      officerName: _officerController.text.trim(),
    );
    PreferencesService().updateConfig(updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFFFACC15), size: 19),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pengaturan stempel berhasil disimpan!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xF018181B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Colors.white12, width: 0.8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sampleTelemetry = LocationService().currentTelemetry;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0C),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () {
            _saveSettings();
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Pengaturan Stempel GPS',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _saveSettings();
              Navigator.pop(context);
            },
            child: const Text(
              'Simpan',
              style: TextStyle(
                color: Color(0xFFFACC15),
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        children: [
          // Section: Live Watermark Preview
          _buildSectionHeader('Pratinjau Watermark'),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12, width: 1.0),
            ),
            child: LiveWatermarkBanner(
              telemetry: sampleTelemetry,
              config: _currentConfig.copyWith(
                projectTitle: _projectController.text,
                officerName: _officerController.text,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Section: Teks Kustom Dokumentasi
          _buildSectionHeader('Identitas Dokumentasi'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF141417),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                // Project / Activity Name
                TextField(
                  controller: _projectController,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (val) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Nama Kegiatan / Proyek / Catatan',
                    labelStyle: const TextStyle(color: Color(0xFFFACC15), fontSize: 13),
                    hintText: 'Contoh: Kunjungan Toko / Dokumentasi STA 42',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.assignment, color: Color(0xFFFACC15), size: 20),
                    filled: true,
                    fillColor: const Color(0xFF1C1C21),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFFACC15), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Officer / Company Name
                TextField(
                  controller: _officerController,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (val) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Nama Petugas / Instansi',
                    labelStyle: const TextStyle(color: Color(0xFFFACC15), fontSize: 13),
                    hintText: 'Contoh: Budi Santoso - PT Maju Bersama',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.person, color: Color(0xFFFACC15), size: 20),
                    filled: true,
                    fillColor: const Color(0xFF1C1C21),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFFACC15), width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section: Format Koordinat
          _buildSectionHeader('Format Koordinat GPS'),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF141417),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildFormatTab(
                    title: 'Desimal (DD°)',
                    subtitle: '-6.2088°, 106.8456°',
                    isSelected: _currentConfig.coordFormat == 'decimal',
                    onTap: () {
                      setState(() {
                        _currentConfig = _currentConfig.copyWith(coordFormat: 'decimal');
                      });
                      PreferencesService().updateConfig(_currentConfig);
                    },
                  ),
                ),
                Expanded(
                  child: _buildFormatTab(
                    title: 'DMS (D°M\'S")',
                    subtitle: '6°12\'31" S, 106°50\'44" E',
                    isSelected: _currentConfig.coordFormat == 'dms',
                    onTap: () {
                      setState(() {
                        _currentConfig = _currentConfig.copyWith(coordFormat: 'dms');
                      });
                      PreferencesService().updateConfig(_currentConfig);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section: Toggle Elemen Watermark
          _buildSectionHeader('Elemen Tercetak (Burn-In)'),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141417),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                _buildSwitchTile(
                  title: 'Alamat Lokasi (Reverse Geocoding)',
                  subtitle: 'Nama jalan, kelurahan, dan kota',
                  value: _currentConfig.showAddress,
                  onChanged: (val) {
                    setState(() => _currentConfig = _currentConfig.copyWith(showAddress: val));
                    PreferencesService().updateConfig(_currentConfig);
                  },
                ),
                const Divider(height: 1, color: Colors.white10),
                _buildSwitchTile(
                  title: 'Koordinat GPS & Akurasi',
                  subtitle: 'Latitude, longitude, dan toleransi akurasi',
                  value: _currentConfig.showCoordinates,
                  onChanged: (val) {
                    setState(() => _currentConfig = _currentConfig.copyWith(showCoordinates: val));
                    PreferencesService().updateConfig(_currentConfig);
                  },
                ),
                const Divider(height: 1, color: Colors.white10),
                _buildSwitchTile(
                  title: 'Thumbnail Peta Satelit (Mini-Map)',
                  subtitle: 'Inset peta satelit dengan pin lokasi di sisi kiri',
                  value: _currentConfig.showMiniMap,
                  onChanged: (val) {
                    setState(() => _currentConfig = _currentConfig.copyWith(showMiniMap: val));
                    PreferencesService().updateConfig(_currentConfig);
                  },
                ),
                const Divider(height: 1, color: Colors.white10),
                _buildSwitchTile(
                  title: 'Tanggal & Waktu Riil',
                  subtitle: 'Stempel waktu pemotretan',
                  value: _currentConfig.showDateTime,
                  onChanged: (val) {
                    setState(() => _currentConfig = _currentConfig.copyWith(showDateTime: val));
                    PreferencesService().updateConfig(_currentConfig);
                  },
                ),
                const Divider(height: 1, color: Colors.white10),
                _buildSwitchTile(
                  title: 'Ketinggian (Elevasi MDPL)',
                  subtitle: 'Tinggi dari permukaan laut',
                  value: _currentConfig.showAltitude,
                  onChanged: (val) {
                    setState(() => _currentConfig = _currentConfig.copyWith(showAltitude: val));
                    PreferencesService().updateConfig(_currentConfig);
                  },
                ),
                const Divider(height: 1, color: Colors.white10),
                _buildSwitchTile(
                  title: 'Judul / Catatan Kegiatan',
                  subtitle: 'Tampilkan teks judul kegiatan pada watermark',
                  value: _currentConfig.showProjectTitle,
                  onChanged: (val) {
                    setState(() => _currentConfig = _currentConfig.copyWith(showProjectTitle: val));
                    PreferencesService().updateConfig(_currentConfig);
                  },
                ),
                const Divider(height: 1, color: Colors.white10),
                _buildSwitchTile(
                  title: 'Nama Petugas / Instansi',
                  subtitle: 'Tampilkan identitas petugas pada watermark',
                  value: _currentConfig.showOfficerName,
                  onChanged: (val) {
                    setState(() => _currentConfig = _currentConfig.copyWith(showOfficerName: val));
                    PreferencesService().updateConfig(_currentConfig);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFFFACC15),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildFormatTab({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFACC15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: isSelected ? Colors.black87 : Colors.white60,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: const Color(0xFFFACC15),
      activeTrackColor: const Color(0x66FACC15),
      inactiveThumbColor: Colors.grey,
      inactiveTrackColor: Colors.white10,
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white60, fontSize: 11),
      ),
    );
  }
}
