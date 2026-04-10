# NOC Tune

**Network Operations Center Tuning & Diagnostic Tool**

Tools untuk mengukur dan menganalisis kualitas jaringan secara komprehensif, dikembangkan berdasarkan metodologi troubleshooting TTFB.

## 📋 Daftar Fitur

| Fase | Fitur | Status |
|------|-------|--------|
| 1 | Time to First Byte (TTFB) | ✅ Available |
| 2 | Latency | 🔜 Coming Soon |
| 3 | Packet Loss | 🔜 Coming Soon |
| 4 | Download Speed | 🔜 Coming Soon |
| 5 | Upload Speed | 🔜 Coming Soon |

## 🎯 Tujuan

Berdasarkan analisis TTFB troubleshooting, tools ini membantu:
- Mengidentifikasi bottleneck DNS (target: Lookup < 30ms)
- Mengukur first-mile quality (jitter, packet loss)
- Membandingkan performa 2.4GHz vs 5GHz WiFi
- Menganalisis Connect/TCP jitter (target: < 50ms)
- Validasi performa ke berbagai CDN (Google, Akamai, Amazon)

## 🚀 Quick Start

### Pilih sistem operasi Anda:

<details>
<summary><b>🍎 macOS / 🐧 Linux</b></summary>

#### 1. Pastikan Python 3.8+ terinstall

```bash
python3 --version
```

Jika belum terinstall:
- **macOS**: `brew install python3`
- **Ubuntu/Debian**: `sudo apt install python3 python3-pip python3-venv`
- **Fedora**: `sudo dnf install python3 python3-pip`

#### 2. Pastikan dig dan curl tersedia

```bash
dig -v
curl --version
```

Jika belum:
- **macOS**: `brew install bind curl` (biasanya sudah ada)
- **Ubuntu/Debian**: `sudo apt install dnsutils curl`

#### 3. Setup Virtual Environment

```bash
# Masuk ke direktori project
cd noc_tune

# Buat virtual environment
python3 -m venv venv

# Aktivasi venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

#### 4. Jalankan Jupyter Notebook

```bash
jupyter notebook notebooks/
```

Buka file `phase1_ttfb_testing.ipynb`

</details>

<details>
<summary><b>🪟 Windows</b></summary>

#### 1. Install Python (jika belum ada)

1. **Download Python** dari [python.org/downloads](https://www.python.org/downloads/)
   - Pilih versi **Python 3.10+** (rekomendasi: 3.11 atau 3.12)
   - Download "Windows installer (64-bit)"

2. **Jalankan installer**:
   - ✅ **PENTING**: Centang **"Add Python to PATH"** di halaman pertama!
   - Klik "Install Now"
   - Tunggu hingga selesai

3. **Verifikasi instalasi** - Buka Command Prompt (cmd) atau PowerShell:
   ```cmd
   python --version
   pip --version
   ```

#### 2. Install Tools Tambahan (dig & curl)

**Opsi A: Menggunakan Chocolatey (Rekomendasi)**

1. Install Chocolatey (package manager untuk Windows):
   - Buka **PowerShell sebagai Administrator**
   - Jalankan:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
   ```

2. Install dig (BIND) dan curl:
   ```powershell
   choco install bind-toolsonly curl -y
   ```

**Opsi B: Download Manual**
- **curl**: Sudah include di Windows 10/11 terbaru. Cek dengan `curl --version`
- **dig**: Download BIND dari [ISC BIND](https://www.isc.org/download/) atau gunakan `nslookup` sebagai alternatif

#### 3. Setup Virtual Environment

Buka **Command Prompt** atau **PowerShell**:

```cmd
# Masuk ke direktori project
cd noc_tune

# Buat virtual environment
python -m venv venv

# Aktivasi venv
venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

> **Note**: Jika muncul error "running scripts is disabled", jalankan PowerShell sebagai Administrator dan ketik:
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

#### 4. Jalankan Jupyter Notebook

```cmd
jupyter notebook notebooks/
```

Buka file `phase1_ttfb_testing.ipynb` di browser yang terbuka otomatis.

#### Troubleshooting Windows

| Problem | Solution |
|---------|----------|
| `python` not recognized | Reinstall Python, pastikan centang "Add to PATH" |
| `dig` not found | Install via Chocolatey atau gunakan `nslookup` |
| Permission denied | Jalankan terminal sebagai Administrator |
| SSL Certificate error | `pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org -r requirements.txt` |

</details>

## 📁 Struktur Project

```
noc_tune/
├── README.md                       # Dokumentasi project
├── requirements.txt                # Dependencies Python
├── .gitignore                      # Git ignore rules
├── venv/                           # Virtual environment (gitignore)
├── notebooks/                      # 📓 Jupyter notebooks
│   └── phase1_ttfb_testing.ipynb   # Notebook Phase 1: TTFB Testing
├── results/                        # Output CSV hasil pengujian
│   └── noctune_*.csv               # Format: noctune_{type}_{timestamp}.csv
└── docs/                           # Dokumentasi tambahan
    └── TTFB_troubleshooting.pdf    # Referensi metodologi
```

> **📓 Notebooks terletak di folder `notebooks/`**

## 📊 Fase 1: TTFB Testing

### Fitur Notebook
- **Multi-sample testing**: Jalankan test N kali dengan delay yang dapat diatur
- **Multiple DNS servers**: Bandingkan Google DNS (8.8.8.8) vs ISP DNS
- **Multiple endpoints**: Instagram, GCP CDN, dan custom domain
- **Auto-export CSV**: Hasil langsung tersimpan dengan timestamp
- **Progress tracking**: Visualisasi progress testing

### Contoh Command yang Dijalankan
```bash
# DNS Lookup dengan trace
dig @8.8.8.8 www.instagram.com +trace
dig @8.8.8.8 qt-google-cloud-cdn.bronze.systems +trace
dig @<ISP_DNS> www.instagram.com +trace
dig @<ISP_DNS> qt-google-cloud-cdn.bronze.systems +trace

# TTFB measurement dengan curl
curl -o /dev/null -s -w "Lookup: %{time_namelookup}s\nConnect: %{time_connect}s\nAppConnect: %{time_appconnect}s\nTTFB: %{time_starttransfer}s\nTotal: %{time_total}s\n" https://www.instagram.com
```

### Parameter Testing
| Parameter | Default | Deskripsi |
|-----------|---------|-----------|
| `sample_count` | 5 | Jumlah pengulangan test |
| `delay_seconds` | 5 | Jeda antar test (detik) |
| `dns_servers` | ['8.8.8.8', 'ISP'] | Daftar DNS server |
| `endpoints` | ['www.instagram.com', 'qt-google-cloud-cdn.bronze.systems'] | Target domain |

### Metrik TTFB yang Diukur
- `time_namelookup`: DNS resolution time
- `time_connect`: TCP 3-way handshake completion
- `time_appconnect`: SSL/TLS negotiation completion  
- `time_starttransfer`: **TTFB** - waktu hingga byte pertama diterima
- `time_total`: Total transfer time
- `server_response`: TTFB - AppConnect (waktu respons server)

## 📈 Interpretasi Hasil

### TTFB Thresholds
| Range | Status | Aksi |
|-------|--------|------|
| < 600ms | 🟢 Good | Optimal |
| 600-800ms | 🟡 Needs Improvement | Monitor |
| > 800ms | 🔴 Poor | Troubleshoot |

### Root Cause Analysis
1. **DNS lambat** (Lookup > 30ms): Ganti ke public DNS (8.8.8.8 / 1.1.1.1)
2. **WiFi jitter** (Connect range besar): Pindah ke 5GHz, optimasi channel
3. **Path/CDN issue** (Server response tinggi): Cek peering, traceroute

## 🔧 Troubleshooting Steps

1. **Stabilkan DNS** - Ganti resolver, target Lookup < 30ms
2. **Ukur first-mile** - Ping 8.8.8.8, target 0% loss & jitter kecil
3. **Pisahkan 2.4G vs 5G** - A/B test Wi-Fi band
4. **Cek Connect jitter** - Target < 50ms dengan range sempit
5. **Analisis post-AppConnect** - Hitung TTFB - AppConnect
6. **Optimasi WiFi** - Channel manual, matikan Smart Connect
7. **Eskalasi** - pcap dan traceroute/mtr jika masih bermasalah

## 📝 Output CSV Format

```csv
timestamp,dns_server,endpoint,lookup_ms,connect_ms,appconnect_ms,ttfb_ms,total_ms,server_response_ms,status
2026-04-10 19:30:00,8.8.8.8,www.instagram.com,21,35,85,384,520,299,good
```

## 🧪 Requirements

### Software
- **Python 3.8+** (rekomendasi: 3.10 atau lebih baru)
- **pip** (biasanya sudah include dengan Python)
- **dig** (DNS lookup tool) - atau `nslookup` di Windows
- **curl** (HTTP client)

### Sistem Operasi
- ✅ macOS
- ✅ Linux (Ubuntu, Debian, Fedora, dll)
- ✅ Windows 10/11

### Koneksi
- Koneksi internet aktif untuk pengujian

## 📚 Referensi

- [OpenSignal Methodology](https://www.opensignal.com/)

## 🤝 Contributing

Kontribusi sangat diterima! Silakan buat issue atau pull request.

## 📄 License

MIT License

---
