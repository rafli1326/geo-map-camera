# Geo Map Camera 📸🗺️

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![GitHub release](https://img.shields.io/github/v/release/rafli1326/geo-map-camera?color=success)](https://github.com/rafli1326/geo-map-camera/releases)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android)](https://www.android.com)
[![GitHub issues](https://img.shields.io/github/issues/rafli1326/geo-map-camera)](https://github.com/rafli1326/geo-map-camera/issues)

Aplikasi kamera Android sederhana, cepat, modern, dan ringan yang dirancang khusus untuk keperluan **dokumentasi lapangan, survei geospasial, absensi kerja, laporan inspeksi konstruksi, dan kegiatan operasional** dengan dukungan stempel (**watermark**) GPS, kompas, ketinggian, dan peta satelit otomatis.

---

## 📥 Unduh Aplikasi (Download APK)

Unduh versi rilis resmi siap pakai di **[Halaman Rilis GitHub](https://github.com/rafli1326/geo-map-camera/releases/latest)**:

| Varian APK | Ukuran | Rekomendasi Penggunaan |
| :--- | :---: | :--- |
| **`app-arm64-v8a-release.apk`** | **~21 MB** | **Direkomendasikan** untuk hampir semua smartphone Android modern (64-bit). |
| **`app-armeabi-v7a-release.apk`** | **~19 MB** | Untuk smartphone Android tipe lama (32-bit). |
| **`app-release.apk`** | **~57 MB** | **Universal APK** (kompatibel dengan seluruh jenis prosesor Android). |

---

## 🌟 Fitur Utama

1. **Watermark Otomatis pada Foto (JPEG)**:
   - **Tata Letak**: Banner bawah semi-transparan (*dark translucent bar*) elegan.
   - **Sisi Kiri**:
     - Judul Kegiatan / Nama Proyek / Catatan Lapangan.
     - Alamat Lokasi Lengkap (*Reverse Geocoded*: nama jalan, kecamatan, kabupaten/kota, provinsi).
     - Koordinat GPS (format Desimal `DD°` atau `DMS`) beserta indikator akurasi (±meter).
     - Tanggal & Waktu riil (WIB/NTP) serta Nama Petugas / Instansi.
     - Orientasi Kompas & Ketinggian (Elevasi) dari permukaan laut.
   - **Sisi Kanan**: Inset **Peta Satelit Presisi Tinggi** (Esri World Imagery / OpenStreetMap) dengan pin lokasi tepat di tengah (*dead-center*).
   - **Toleran Offline**: Tetap dapat memotret di area tanpa sinyal internet; koordinat GPS dan waktu tetap tercetak sempurna dengan tampilan peta radar taktis cadangan.

2. **Perekaman Video dengan Live Watermark (Hardware-Accelerated)**:
   - Menggunakan native **AndroidX Media3 Transformer** untuk pencetakan telemetri dinamis per detik langsung ke dalam video tanpa lagging.
   - Menyesuaikan sensor orientasi perangkat secara otomatis (baik rotasi potret maupun lanskap).

3. **Kontrol Kamera Profesional**:
   - Viewfinder *full-bleed* dengan live watermark banner interaktif.
   - Exposure Control: Slider kompensasi pencahayaan terintegrasi langsung dengan kunci eksposur (AE Lock).
   - Status sinyal GPS real-time (*Mencari Sinyal* vs *GPS Siap ±X.Xm*).
   - Kontrol lampu kilat/senter (*Off*, *Torch/On*, *Auto*).
   - Beralih kamera depan & belakang (*flip camera*).
   - Kontrol zoom cepat (1x, 2x) dan *pinch-to-zoom*.
   - Kisi bantu komposisi (*3x3 Rule of Thirds Grid*).

4. **Keamanan & Integritas Data Lapangan (Hardened)**:
   - **Anti-Spoofing**: Deteksi lokasi palsu (*Mock Location/Fake GPS*). Jika terdeteksi lokasi palsu, koordinat langsung dicopot dari stempel demi keaslian data audit lapangan.
   - **Proteksi Path Traversal**: Isolasi ketat penyimpanan file pada native layer dan Dart layer.
   - **Enkripsi Lalu Lintas**: Pemblokiran koneksi tidak terenkripsi (`usesCleartextTraffic="false"`).
   - **Proteksi Backup**: Penonaktifan ekstraksi data ADB (`allowBackup="false"`).

5. **Penyimpanan Langsung ke Galeri Publik**:
   - Foto dan video langsung tersimpan di folder publik perangkat:
     `/storage/emulated/0/Pictures/Geo Map Camera/`
   - Langsung terdeteksi di Google Photos dan Galeri bawaan HP, mudah dibagikan ke WhatsApp, Telegram, email, atau cloud storage.

6. **Galeri Dokumentasi & Pratinjau**:
   - Grid galeri foto dan video di dalam aplikasi.
   - Pratinjau layar penuh dengan dukungan *zoom* gambar interaktif.
   - Pemutar video dengan kontrol *play/pause* dan *seek bar*.
   - Tombol langsung **Bagikan (Share)** dan **Hapus**.

---

## 📁 Struktur Proyek

```
lib/
├── main.dart                          # Inisialisasi tema, entry point, dan konfigurasi app
├── models/
│   ├── gps_telemetry.dart             # Model data telemetri GPS, formatting koordinat & alamat
│   ├── watermark_config.dart          # Model konfigurasi stempel & persistensi pengaturan
│   └── media_item.dart                # Model item foto & video hasil dokumentasi
├── services/
│   ├── location_service.dart          # Pelacakan GPS presisi tinggi & reverse geocoding offline-tolerant
│   ├── map_tile_service.dart          # Pengunduh tile satelit Esri, OSM, & generator peta taktis offline
│   ├── watermark_burner.dart          # Engine pencetakan watermark ke file JPEG menggunakan Canvas dart:ui
│   ├── video_watermark_service.dart   # Engine overlay video dinamis via native Media3 Transformer
│   ├── storage_service.dart           # Manajemen penyimpanan publik di Pictures/Geo Map Camera
│   └── preferences_service.dart       # Penyimpanan preferensi via SharedPreferences
├── screens/
│   ├── camera_screen.dart             # Viewfinder kamera utama, status GPS, kontrol shutter, foto/video
│   ├── gallery_screen.dart            # Grid galeri dokumentasi
│   ├── media_viewer_screen.dart       # Pratinjau detail media, pemutar video, share, dan delete
│   └── settings_screen.dart           # Form pengaturan identitas stempel & toggle elemen
└── widgets/
    └── live_watermark_banner.dart     # Widget reusable banner semi-transparan live telemetri & peta mini
```

---

## 🚀 Cara Menjalankan & Membangun Kode

### 1. Menjalankan di Perangkat Android
Pastikan perangkat Android terhubung via USB dengan USB Debugging aktif:
```bash
flutter pub get
flutter run
```

### 2. Membangun File APK (Release)
```bash
# Split per-ABI (ukuran lebih hemat)
flutter build apk --release --split-per-abi

# Universal APK
flutter build apk --release
```

File APK tersimpan di folder `build/app/outputs/flutter-apk/`.

---

## 🤝 Berkontribusi (Contributing)

Kontribusi dari komunitas sangat dihargai! Silakan baca panduan lengkap di **[CONTRIBUTING.md](CONTRIBUTING.md)** untuk alur kerja pembuatan branch, standar kode, dan pengajuan Pull Request.

---

## 🔒 Keamanan (Security)

Jika Anda menemukan kerentanan keamanan, harap laporkan secara privat sesuai prosedur di **[SECURITY.md](SECURITY.md)** atau hubungi pengembang melalui email.

---

## 👤 Penulis & Pengelola (Author & Maintainer)

- **Muhammad Rafli** ([@rafli1326](https://github.com/rafli1326)) - *Lead Developer & Maintainer*
  - GitHub: [github.com/rafli1326](https://github.com/rafli1326)
  - Email: `rafli.maildir@gmail.com`

---

## 📜 Lisensi & Atribusi Pihak Ketiga (License & Attributions)

Proyek ini dilisensikan di bawah **[GNU General Public License v3.0 (GPL-3.0)](LICENSE)**.

### Atribusi Pihak Ketiga:
- **Peta OpenStreetMap**: Data peta © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), berlisensi [ODbL](https://opendatacommons.org/licenses/odbl/).
- **Citra Satelit Esri**: Layanan *World Imagery MapServer* disediakan oleh [Esri](https://www.esri.com/) dengan sumber citra dari Esri, Maxar, Earthstar Geographics, dan komunitas GIS.
- **AndroidX Media3 Transformer**: Dilisensikan di bawah [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).
- **Flutter Framework & Material Icons**: Dilisensikan di bawah lisensi BSD-style oleh Google LLC.
