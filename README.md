# Geo Map Camera (Kamera Dokumentasi Ber-Watermark GPS & Peta Satelit)

Aplikasi kamera Android sederhana, cepat, dan ringan yang dirancang khusus untuk keperluan **dokumentasi lapangan, survei geospasial, absensi kerja, laporan inspeksi konstruksi, dan kegiatan operasional** dengan dukungan stempel (**watermark**) GPS, kompas, ketinggian, dan peta satelit otomatis.

---

## 🌟 Fitur Utama

1. **Watermark Burn-in Permanen pada Foto (JPEG)**:
   - **Tata Letak**: Banner bawah semi-transparan (*dark translucent bar*).
   - **Sisi Kiri**:
     - Judul Kegiatan / Nama Proyek (dapat diubah di Pengaturan).
     - Alamat Lokasi Lengkap (*Reverse Geocoded*: nama jalan, kecamatan, kota).
     - Koordinat GPS (format Desimal `DD°` atau `DMS`) beserta akurasi (±meter).
     - Tanggal & Waktu riil (WIB/NTP) serta Nama Petugas / Instansi.
   - **Sisi Kanan**: Inset **Peta Mini (Mini-Map)** dengan titik penanda lokasi saat foto diambil.
   - **Toleran Offline**: Tetap dapat memotret di area tanpa internet; koordinat GPS dan waktu tetap tercetak sempurna dengan tampilan peta radar taktis cadangan.

2. **Kamera Lapangan**:
   - Viewfinder *full-bleed* dengan live watermark banner interaktif.
   - Status sinyal GPS real-time (*Mencari Sinyal* vs *GPS Siap ±X.Xm*).
   - Kontrol lampu kilat/senter (*Off*, *Torch/On*, *Auto*).
   - Beralih kamera depan & belakang (*flip camera*).
   - Kontrol zoom cepat (1x, 2x) dan *pinch-to-zoom*.
   - Kisi bantu komposisi (*3x3 Rule of Thirds Grid*).
   - Dukungan pemotretan **Foto** dan perekaman **Video** dengan HUD telemetri live.

3. **Penyimpanan Langsung ke Galeri Publik**:
   - Foto dan video langsung tersimpan di folder publik perangkat:
     `/storage/emulated/0/Pictures/Geo Map Camera/`
   - Langsung terdeteksi di Google Photos, Galeri bawaan HP, dan mudah dilampirkan (*attach*) langsung ke WhatsApp, Telegram, email, atau Google Drive.

4. **Galeri Dokumentasi & Pratinjau**:
   - Grid galeri foto dan video di dalam aplikasi.
   - Pratinjau layar penuh dengan dukungan *zoom* gambar interaktif.
   - Pemutar video dengan kontrol *play/pause* dan *seek bar*.
   - Tombol langsung **Bagikan (Share)** dan **Hapus**.

5. **Pengaturan Identitas Dokumentasi**:
   - Input Nama Kegiatan / Proyek / Catatan.
   - Input Nama Petugas / Instansi.
   - Pilihan format koordinat: Desimal (`-6.2088°, 106.8456°`) atau DMS (`6°12'31" S, 106°50'44" E`).
   - Toggle on/off untuk setiap elemen stempel (alamat, koordinat, peta mini, waktu, ketinggian).
   - Kartu pratinjau stempel *live* yang langsung menyesuaikan saat pengaturan diedit.

---

## 📁 Struktur Kode

```
lib/
├── main.dart                          # Inisialisasi tema, orientasi potret, dan konfigurasi app
├── models/
│   ├── gps_telemetry.dart             # Model data telemetri GPS, formatting koordinat & alamat
│   ├── watermark_config.dart          # Model konfigurasi stempel & persistensi pengaturan
│   └── media_item.dart                # Model item foto & video hasil dokumentasi
├── services/
│   ├── location_service.dart          # Pelacakan GPS presisi tinggi & reverse geocoding offline-tolerant
│   ├── map_tile_service.dart          # Pengunduh tile OpenStreetMap & generator peta taktis offline
│   ├── watermark_burner.dart          # Engine pencetakan watermark ke file JPEG menggunakan Canvas dart:ui
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

## 🚀 Cara Menjalankan & Build APK

### 1. Menjalankan di Perangkat Android / Emulator
Pastikan perangkat Android terhubung via USB dengan USB Debugging aktif:
```bash
flutter run
```

### 2. Membangun File APK (Debug / Release)
Untuk menghasilkan file installer APK yang siap diinstal di ponsel Android:

- **Debug APK**:
  ```bash
  flutter build apk --debug
  ```
  File APK tersimpan di: `build/app/outputs/flutter-apk/app-debug.apk`

- **Release APK**:
  ```bash
  flutter build apk --release
  ```
  File APK tersimpan di: `build/app/outputs/flutter-apk/app-release.apk`
