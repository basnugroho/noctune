# Changelog

## 2026-04-15

- Tambah mode CLI: `python main.py --run`.
- Tambah argumen CLI untuk lokasi, target, sample, delay, ping, DNS, dan contribute.
- Tambah custom DNS default `8.8.8.8, 8.8.4.4` tanpa ubah DNS OS.
- Tambah input koordinat manual di UI dan status `Manual Input`.
- Tampilkan Test DNS dan System DNS di UI.
- Perjelas diagnostic prerequisite dan interpreter aktif.
- Pindah tombol utama run ke tengah dan ubah label jadi `Jalankan Tes Sekarang`.
- Tambah `dig @server domain +trace` otomatis setiap sample TTFB.
- Tambah field baru: `resolved_ip`, `dig_output`, `dig_query_time_ms`.
- Update unique key include `dns_primary` untuk multi-DNS scenario.