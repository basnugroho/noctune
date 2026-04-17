# NOC Tune Mobile

Flutter mobile app untuk NOC Tune. Fokus utama versi mobile saat ini adalah Android distribution via APK, dengan fitur test jaringan yang mengikuti pengalaman utama NOC Tune.

## Release APK

File APK yang siap dibagikan ke user Android ada di:

- `../releases/v1.0.0/mobile/noctune-mobile-v1.0.0-android.apk`

APK tersebut adalah build release dan cocok untuk distribusi manual ke user lain.

## Install untuk End User

1. Kirim file APK ke perangkat Android user.
2. Buka file APK dari perangkat.
3. Jika diminta, aktifkan izin install dari sumber luar Play Store.
4. Lanjutkan proses install sampai selesai.

Catatan:

- File `app-debug.apk` tidak disarankan untuk distribusi umum.
- APK hanya berlaku untuk Android. Untuk iPhone/iOS perlu build terpisah.

## Build APK Release

Jalankan dari folder `mobile`:

```bash
flutter pub get
flutter build apk --release
```

Prasyarat minimum:

- Flutter SDK terpasang dan tersedia di PATH.
- Android SDK terpasang.
- Device Android terhubung atau emulator aktif jika ingin `flutter run`.
- File `android/local.properties` akan dibuat otomatis oleh Flutter/Android SDK di mesin masing-masing dan tidak perlu disimpan di git.

Hasil build default Flutter ada di:

- `build/app/outputs/flutter-apk/app-release.apk`

Jika ingin menyiapkan file distribusi repo yang rapi, salin hasil build itu ke folder release project:

```bash
cp build/app/outputs/flutter-apk/app-release.apk ../releases/v1.0.0/mobile/noctune-mobile-v1.0.0-android.apk
```

## Run untuk Development

```bash
flutter pub get
flutter run
```

Untuk install build debug langsung ke device Android yang terhubung:

```bash
flutter install --debug
```

## File yang Perlu Masuk Git

Untuk clone/fork yang bersih dan tetap bisa dibuild, commit folder sumber dan konfigurasi project berikut:

- `lib/`
- `assets/`
- `android/`, `ios/`, `macos/`, `linux/`, `windows/`, `web/`
- `pubspec.yaml`
- `pubspec.lock`
- `analysis_options.yaml`
- `.metadata`
- `README.md`

Khusus Android, file Gradle wrapper juga harus ikut tersimpan:

- `android/gradlew`
- `android/gradlew.bat`
- `android/gradle/wrapper/gradle-wrapper.jar`
- `android/gradle/wrapper/gradle-wrapper.properties`

## File yang Jangan Di-commit

Jangan push file generated, file besar hasil build, atau file lokal mesin:

- `.dart_tool/`
- `build/`
- `.idea/`
- `*.iml`
- `android/.gradle/`
- `android/local.properties`
- `ios/Pods/`
- `ios/Flutter/Generated.xcconfig`
- `ios/Flutter/flutter_export_environment.sh`
- `macos/Pods/`
- file signing seperti `key.properties`, `*.jks`, `*.keystore`

## Struktur Singkat

- `lib/main.dart` untuk entry point dan bottom navigation.
- `lib/features` untuk layar fitur seperti TTFB, Ping, DNS, dan Settings.
- `lib/services` untuk network test logic dan storage.
- `lib/providers` untuk state management berbasis Provider.

## Referensi

README utama project ada di `../README.md`.
