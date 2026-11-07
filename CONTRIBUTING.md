# Panduan Kontribusi (Contributing Guidelines)

Terima kasih atas minat Anda untuk berkontribusi pada proyek **Geo Map Camera**! Kami menyambut baik segala bentuk kontribusi dari komunitas, baik berupa perbaikan bug, penambahan fitur baru, perbaikan dokumentasi, maupun pelaporan kendala.

Proyek ini berlisensi di bawah **GNU General Public License v3.0 (GPL-3.0)**. Dengan berkontribusi pada proyek ini, Anda menyetujui bahwa kode Anda akan dilisensikan di bawah ketentuan yang sama.

---

## 🛠️ Persyaratan Lingkungan Pengembangan

Sebelum mulai mengembangkan, pastikan perangkat Anda telah terpasang:
- **Flutter SDK**: Versi `^3.13` atau yang lebih baru (disarankan channel `stable`).
- **Dart SDK**: Terintegrasi otomatis bersama Flutter.
- **Android Studio / Android SDK**: Dengan platform tools dan build tools terbaru (Compile/Target SDK 36).
- **Perangkat Fisik Android**: Disarankan untuk pengujian kamera perangkat keras, sensor kompas/akselerometer, dan koordinat GPS riil.

---

## 🚀 Alur Kerja Berkontribusi (Workflow)

1. **Fork Repositori**:
   Buat salinan repositori ini ke akun GitHub Anda melalui tombol **Fork**.

2. **Clone Salinan Fork Anda**:
   ```bash
   git clone https://github.com/USERNAME_ANDA/geo-map-camera.git
   cd geo-map-camera
   ```

3. **Buat Branch Fitur Baru**:
   Gunakan nama branch yang deskriptif:
   ```bash
   # Untuk fitur baru
   git checkout -b feat/nama-fitur

   # Untuk perbaikan bug
   git checkout -b fix/deskripsi-bug
   ```

4. **Instal Dependensi**:
   ```bash
   flutter pub get
   ```

5. **Terapkan Perubahan Anda**:
   - Tulis kode yang rapi, modular, dan mudah dipahami.
   - Pertahankan arsitektur layanan (*service-oriented architecture*) yang sudah ada di folder `lib/services/`.
   - Hindari hardcode nilai rahasia atau izin yang tidak diperlukan.

6. **Jalankan Verifikasi & Pengujian Kualitas**:
   Sebelum melakukan commit, pastikan seluruh pengujian lolos:
   ```bash
   # Analisis statis kode (wajib 0 issues)
   flutter analyze

   # Jalankan seluruh unit test
   flutter test
   ```

7. **Commit Perubahan**:
   Gunakan format **Conventional Commits**:
   - `feat: deskripsi fitur baru`
   - `fix: perbaikan bug tertentu`
   - `docs: pembaruan dokumentasi`
   - `refactor: restrukturisasi kode tanpa mengubah fungsionalitas`

8. **Push ke Branch Fork Anda**:
   ```bash
   git push origin feat/nama-fitur
   ```

9. **Buka Pull Request (PR)**:
   - Buat Pull Request baru ke branch `main` repositori resmi: `rafli1326/geo-map-camera`.
   - Jelaskan latar belakang masalah, solusi yang dibuat, dan hasil pengujian yang dilakukan.

---

## 🐛 Melaporkan Masalah (Bug Reports)

Jika menemukan kendala atau perilaku tidak terduga pada aplikasi:
1. Buka tab **[Issues](https://github.com/rafli1326/geo-map-camera/issues)** di repositori.
2. Periksa apakah isu serupa sudah pernah dilaporkan sebelumnya.
3. Buat issue baru dengan menyertakan:
   - Tipe perangkat dan versi Android (contoh: *itel P661N, Android 12*).
   - Langkah-langkah untuk mereproduksi masalah (*steps to reproduce*).
   - Tangkapan layar (*screenshot*) atau log error bila ada.

---

## 💡 Mengajukan Ide & Fitur Baru (Feature Requests)

Punya ide untuk menyempurnakan Geo Map Camera? Kami sangat terbuka untuk berdiskusi! Silakan buat issue baru dengan label `enhancement` dan jelaskan bagaimana fitur tersebut bermanfaat untuk kegiatan survei atau dokumentasi lapangan.
