# Monitoring ESP32

Aplikasi mobile berbasis Flutter untuk melakukan monitoring perangkat ESP32 secara real-time. Aplikasi ini dirancang untuk menampilkan data sensor, status perangkat, serta informasi operasional lainnya yang dikirimkan oleh ESP32 melalui jaringan internet maupun lokal.

## ✨ Fitur

- Monitoring data ESP32 secara real-time
- Menampilkan status koneksi perangkat
- Dashboard monitoring yang responsif
- Riwayat data monitoring
- Notifikasi status perangkat
- Multi-device monitoring
- Dukungan Android dan iOS
- Refresh data otomatis
- Visualisasi data menggunakan chart dan statistik
- Manajemen perangkat ESP32

## 📱 Screenshot

Tambahkan screenshot aplikasi pada folder `docs/images` dan tampilkan di sini.

```md
![Dashboard](docs/images/dashboard.png)
![Device Detail](docs/images/device-detail.png)
```

## 🏗️ Tech Stack

- Flutter
- Dart
- REST API
- WebSocket (Opsional)
- MQTT (Opsional)
- ESP32
- Firebase (Opsional)
- Provider / Riverpod / Bloc (Sesuai implementasi)

## 📂 Struktur Project

```text
lib/
├── core/
│   ├── constants/
│   ├── services/
│   ├── network/
│   └── utils/
│
├── models/
│
├── features/
│   ├── dashboard/
│   ├── monitoring/
│   ├── devices/
│   └── settings/
│
├── widgets/
│
└── main.dart
```

## 🚀 Instalasi

### 1. Clone Repository

```bash
git clone https://github.com/username/monitoring-esp32.git
cd monitoring-esp32
```

### 2. Install Dependency

```bash
flutter pub get
```

### 3. Konfigurasi Environment

Buat file konfigurasi sesuai kebutuhan project.

Contoh:

```env
API_URL=https://api.example.com
MQTT_HOST=broker.example.com
MQTT_PORT=1883
```

### 4. Jalankan Project

```bash
flutter run
```

## 🔧 Build Release

### Android APK

```bash
flutter build apk --release
```

### Android App Bundle

```bash
flutter build appbundle --release
```

### iOS

```bash
flutter build ios --release
```

## 📡 Arsitektur Sistem

```text
+-------------+
|    ESP32    |
+-------------+
       |
       |
       ▼
+-------------+
| API / MQTT  |
|   Broker    |
+-------------+
       |
       ▼
+-------------+
| Flutter App |
+-------------+
```

## 📊 Data Monitoring

Contoh data yang dapat ditampilkan:

- Temperatur
- Kelembapan
- Tegangan
- Arus listrik
- Daya
- Status Relay
- Status Sensor
- Status Koneksi
- Lokasi Perangkat
- Uptime Device

## 🔐 Keamanan

- HTTPS Communication
- API Authentication
- Device Authentication
- Token-based Authorization
- Secure Storage untuk penyimpanan credential

## 🧪 Testing

Menjalankan unit test:

```bash
flutter test
```

Menjalankan integration test:

```bash
flutter test integration_test
```

## 📦 Deployment

Pastikan konfigurasi release telah disiapkan:

- Android Keystore
- Firebase Configuration
- Environment Production
- API Endpoint Production

Build aplikasi:

```bash
flutter build appbundle --release
```

## 📝 Roadmap

- [ ] Real-time MQTT Monitoring
- [ ] Push Notification
- [ ] Device Grouping
- [ ] OTA Update Monitoring
- [ ] Export Data CSV/Excel
- [ ] Dark Mode
- [ ] Offline Cache
- [ ] Multi User Access

## 🤝 Kontribusi

1. Fork repository
2. Buat branch baru

```bash
git checkout -b feature/nama-fitur
```

3. Commit perubahan

```bash
git commit -m "Add new feature"
```

4. Push ke branch

```bash
git push origin feature/nama-fitur
```

5. Buat Pull Request

## 📄 License

Project ini dibuat untuk kebutuhan monitoring perangkat ESP32 menggunakan Flutter.

---

**Monitoring ESP32**
Built with ❤️ using Flutter & ESP32