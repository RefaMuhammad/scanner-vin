# 📱 Panduan & Dokumentasi Aplikasi Scanner VIN

Selamat datang di proyek **Aplikasi Scanner VIN**.

Dokumen ini berisi panduan lengkap mulai dari instalasi aplikasi untuk pengguna, petunjuk bagi developer untuk menjalankan proyek, hingga penjelasan teknis mengenai model Kecerdasan Buatan (AI) yang bekerja di balik aplikasi.

---

# 📥 1. Panduan Instalasi APK (Untuk Pengguna/Klien)

Di dalam folder distribusi tersedia beberapa file APK. Pemisahan APK ini bertujuan agar ukuran aplikasi yang diunduh menjadi lebih kecil dan sesuai dengan arsitektur perangkat Android yang digunakan.

## File APK yang Tersedia

| File APK | Ukuran | Peruntukan |
|----------|---------|------------|
| ⭐ **app-arm64-v8a-release.apk** | **38.8 MB** | **Sangat direkomendasikan** untuk hampir semua HP Android modern (2016 ke atas) seperti Samsung, Xiaomi, Oppo, Vivo, Poco, Infinix, Realme, dll. |
| **app-release.apk** | 98.6 MB | Versi Universal. Dapat diinstal di seluruh perangkat Android. Gunakan apabila tidak mengetahui arsitektur perangkat atau versi ARM64 gagal diinstal. |
| **app-armeabi-v7a-release.apk** | 28.8 MB | Khusus perangkat Android lama yang masih menggunakan arsitektur 32-bit. |
| **app-x86_64-release.apk** | 40 MB | Khusus Emulator Android pada PC/Laptop (Android Studio Emulator, Bluestacks, Nox, dll). Jangan digunakan pada HP fisik. |

---

## ⚙️ Cara Instalasi

1. Unduh file APK yang direkomendasikan (**app-arm64-v8a-release.apk**).
2. Buka file APK melalui **File Manager** atau **Browser**.
3. Jika muncul peringatan **Unknown Sources**, buka **Settings** kemudian aktifkan **Allow from this source**.
4. Jika muncul peringatan **Google Play Protect**, pilih:
   - **More Details**
   - **Install Anyway**
5. Tunggu hingga proses instalasi selesai.
6. Aplikasi siap digunakan.

---

# 💻 2. Menjalankan Project (Developer)

Panduan ini ditujukan bagi developer yang ingin melakukan pengembangan, debugging, maupun pengujian aplikasi menggunakan source code Flutter.

---

## Prasyarat

Pastikan perangkat pengembangan telah memiliki:

- Flutter SDK (versi stabil terbaru)
- Android Studio
- Android SDK
- Android NDK
- Perangkat Android dengan:
  - Developer Options aktif
  - USB Debugging aktif

---

## Langkah Menjalankan Project

### 1. Hubungkan perangkat

Hubungkan perangkat Android menggunakan kabel USB atau jalankan Android Emulator.

---

### 2. Masuk ke folder project

```bash
cd path/ke/folder/scanner_vin
```

---

### 3. Install seluruh dependency

```bash
flutter pub get
```

---

### 4. Bersihkan cache build

Langkah ini **sangat disarankan** agar tidak terjadi error kompilasi terutama pada library native seperti MLKit maupun ScanKit.

```bash
flutter clean
flutter pub get
```

---

### 5. Jalankan aplikasi

```bash
flutter run
```

---

### Catatan

Build pertama biasanya membutuhkan waktu lebih lama karena:

- Gradle mengunduh library native
- Android SDK melakukan proses linking
- R8 Shrinker melakukan optimisasi
- Kompilasi native library

---

# 🧠 3. Penjelasan Model Kecerdasan Buatan (TensorFlow Lite)

Aplikasi Scanner VIN tidak hanya menggunakan OCR biasa.

Aplikasi dilengkapi model **Deep Learning** yang berjalan **sepenuhnya secara offline** untuk mengekstraksi sekaligus memvalidasi Nomor Identifikasi Kendaraan (**Vehicle Identification Number / VIN**) dari hasil OCR.

---

## Arsitektur Model

Model menggunakan kombinasi:

- **BiGRU (Bidirectional Gated Recurrent Unit)**
- **Conditional Random Field (CRF)**

Diagram sederhananya:

```text
OCR
 │
 ▼
Raw Text
 │
 ▼
Preprocessing
(Tokenization)
 │
 ▼
BiGRU
 │
 ▼
CRF
 │
 ▼
Valid VIN
```

---

## BiGRU (Bidirectional GRU)

BiGRU membaca karakter dari **dua arah sekaligus**:

- kiri → kanan
- kanan → kiri

Pendekatan ini membuat model memahami konteks karakter.

Contoh:

OCR menghasilkan:

```
MHGCM82633AOO4352
```

Padahal VIN sebenarnya:

```
MHGCM82633A004352
```

Model mampu memperkirakan bahwa huruf **O** seharusnya merupakan angka **0** berdasarkan pola karakter di sekitarnya.

---

## Conditional Random Field (CRF)

CRF merupakan lapisan akhir yang bertugas melakukan validasi urutan karakter.

Fungsinya antara lain:

- memastikan urutan karakter tetap logis
- mengurangi prediksi karakter yang salah
- memperbaiki hasil inferensi menggunakan probabilitas transisi

---

# 📂 File Asset AI

Seluruh model AI berada pada folder:

```
assets/
```

Terdiri dari tiga file utama.

---

## 1. model_bigru_crf.tflite

Model TensorFlow Lite yang telah dilatih.

Berisi:

- Bobot (Weights)
- Struktur jaringan BiGRU
- Lapisan output

Model ini digunakan saat proses inferensi pada smartphone.

---

## 2. vocab_config_vin.json

Merupakan kamus karakter (Vocabulary).

Contoh:

```json
{
  "A": 1,
  "B": 2,
  "C": 3,
  "0": 27,
  "1": 28
}
```

Fungsinya:

- mengubah teks menjadi token angka
- melakukan tokenisasi sebelum masuk ke model

---

## 3. transition_matrix.json

Digunakan oleh lapisan CRF.

Berisi matriks probabilitas perpindahan label yang digunakan oleh algoritma **Viterbi** saat proses decoding.

Fungsinya:

- memilih prediksi karakter terbaik
- memperbaiki hasil inferensi
- menjaga konsistensi format VIN

---

# 🔄 Pipeline Ekstraksi VIN

Proses kerja sistem secara keseluruhan adalah sebagai berikut.

```text
Kamera
   │
   ▼
Huawei ScanKit / Google ML Kit OCR
   │
   ▼
Raw Text
   │
   ▼
Preprocessing
   │
(Tokenization menggunakan vocab_config_vin.json)
   │
   ▼
TensorFlow Lite
(model_bigru_crf.tflite)
   │
   ▼
Output Label
   │
   ▼
Viterbi + CRF
(transition_matrix.json)
   │
   ▼
Valid VIN (17 Karakter)
```

---

## Tahapan Pipeline

### 1. Input (Kamera)

Huawei ScanKit atau Google ML Kit melakukan pendeteksian teks pada kendaraan kemudian menghasilkan **raw text**.

---

### 2. Preprocessing

Raw text dibersihkan kemudian diubah menjadi token angka menggunakan:

```
vocab_config_vin.json
```

---

### 3. Inferensi

Token angka diproses oleh:

```
model_bigru_crf.tflite
```

Inferensi dijalankan langsung pada CPU maupun NPU perangkat tanpa membutuhkan koneksi internet.

Estimasi waktu inferensi:

> **< 50 ms**

---

### 4. Post-processing

Output model kemudian diproses menggunakan:

- Algoritma Viterbi
- Transition Matrix (CRF)

Tahap ini bertugas memilih urutan karakter yang memiliki probabilitas tertinggi sehingga diperoleh **VIN sepanjang 17 karakter** yang paling valid.

---

# 📌 Ringkasan Teknologi

| Komponen | Teknologi |
|----------|-----------|
| Framework Mobile | Flutter |
| OCR | Huawei ScanKit / Google ML Kit |
| AI Model | BiGRU + CRF |
| AI Runtime | TensorFlow Lite |
| Tokenizer | Vocabulary JSON |
| Decoder | Viterbi Algorithm |
| Post-processing | Conditional Random Field (CRF) |
| Koneksi Internet | Tidak diperlukan (Offline) |

---

# 📄 Penutup

Aplikasi Scanner VIN dirancang agar mampu melakukan ekstraksi Nomor Identifikasi Kendaraan (**VIN**) secara cepat, akurat, dan sepenuhnya **offline**.

Dengan memanfaatkan kombinasi OCR, model **BiGRU-CRF**, serta TensorFlow Lite, aplikasi mampu melakukan identifikasi dan validasi VIN dalam waktu kurang dari **50 ms** tanpa memerlukan koneksi internet.
