# Rancangan Produk & Desain: Rumpun

**Rumpun** adalah klien Fediverse desktop yang ramah pengguna, berfokus pada Linux, dan dibangun dengan Flutter. Filosofi intinya: menyederhanakan interaksi desentralisasi (Mastodon & ActivityPub) menjadi platform yang tenang, indah, berpusat pada percakapan manusiawi, tanpa jargon protokol.

---

## 1. Sasaran Pengguna & Prinsip Desain

### Sasaran Pengguna
1. **Pengguna Baru:** Tidak perlu memahami server/node/instance sebelum mulai membaca. Panduan server disajikan dengan bahasa sederhana (komunitas, bahasa, topik minat).
2. **Pengguna Linux Modern:** Antarmuka native, hemat memori, mendukung keyboard shortcuts lengkap, dark/light mode yang sinkron dengan preferensi sistem GNOME/KDE.
3. **Pengguna Fediverse Berpengalaman:** Kendali penuh atas Content Warning (CW), 4 tingkat visibilitas postingan, alt-text aksesibel untuk media, serta multi-server switching.

### Prinsip Desain (Design Principles)
- **Zero-Jargon Interface:** Tidak ada istilah rumit di UI utama. Gunakan "Server" menggantikan "Instance", "Bagikan Ulang" menggantikan "Boost", "Peringatan Konten" menggantikan "CW", dan "Tulis" menggantikan "Toot".
- **App-Owned Modern Chrome:** Mengganti status bar sistem yang terpisah dengan header aplikasi terpadu (*owned chrome*) setinggi 46px yang menyatu dengan kanvas latar belakang.
- **Tipografi Minimalis Cupertino:** Menggunakan font keluarga Apple SF Pro Text (`.SF Pro Text`) dengan tracking rapat, hierarchy yang tenang, serta fallback mulus ke font native Linux (Cantarell, Inter, Roboto).
- **Spatial Breadcrumb Navigation:** Navigasi rail adaptif di desktop lebar (>= 760px) dan bottom navigation bar di viewport compact (< 760px).
- **Safe & Intentional Publishing:** Peringatan visual sebelum mengirim jika postingan memiliki gambar tanpa alt-text atau berisi kata sensitif tanpa CW.

---

## 2. Struktur Layar Aplikasi (Screen Architecture)

Aplikasi memiliki 4 layar utama dan 2 lembar modal interaktif:

```
┌────────────────────────────────────────────────────────┐
│ [Hub] rumpun          ● ruang.id              [Avatar] │ <- App-Owned Chrome
├──────┬─────────────────────────────────────────────────┤
│ [🏠] │ LAYAR 1: BERANDA (Linimasa & Tabs)              │
│ [🔍] │ LAYAR 2: JELAJAH & CARI (Akun, Tagar, Post)     │
│ [🔔] │ LAYAR 3: AKTIVITAS (Sebutan, Suka, Boost)       │
│ [👤] │ LAYAR 4: PROFIL (Biodata, Post Saya, Pengikut)  │
└──────┴─────────────────────────────────────────────────┘
```

### 2.1 Layar Beranda (Timeline)
- **Pills Filter Linimasa:** Tab *Mengikuti* (beranda akun), *Lokal* (server ruang.id), dan *Federasi* (seluruh jagat fediverse).
- **Composer Compact Card:** Tombol cepat *"Apa yang ingin kamu bagikan?"* yang membuka Modal Compose penuh.
- **Feed Cards:** Menampilkan avatar pengirim, nama, handle federasi lengkap (`@user@server`), stempel waktu, badge CW bila ada, teks postingan, dan bar aksi (Balas, Suka, Bagikan, Salin/Bagikan).
- **Interaksi Thread:** Mengetuk sembarang kartu membuka lembar detail rantai percakapan (*Thread Modal*).

### 2.2 Layar Jelajah & Cari (Explore & Search)
- **Search Bar Modern:** Input pencarian terpadu untuk mencari akun (`@nama@domain`), tagar (`#topik`), atau konten post.
- **Pills Kategori:** Akun, Tagar, dan Postingan Terkini.
- **Daftar Tagar Tren:** Menampilkan tagar lokal dan global terpopuler beserta volume percakapan.

### 2.3 Layar Aktivitas (Notifications)
- **Filter Segmented:** *Semua*, *Sebutan* (Mentions), dan *Favorit/Boost*.
- **Item Notifikasi:** Kartu dengan ikon aksi spesifik (ikon bintang pink untuk suka, ikon loop hijau untuk boost, ikon balon percakapan biru untuk balasan).

### 2.4 Layar Profil Pengguna (User Profile)
- **Header Profil:** Avatar besar, nama lengkap, handle federasi, status koneksi server, dan statistik (Mengikuti, Pengikut, Postingan).
- **Biografi:** Teks bio dengan tautan federasi yang dapat diklik.
- **Tab Konten:** Postingan, Balasan, dan Media.

### 2.5 Modal Compose Lengkap (Interactive Composer)
- **Input Postingan:** Area pengetikan leluasa dengan penghitung karakter dinamis (500 batas default Fediverse).
- **CW Toggle:** Input spoiler teks yang otomatis menyembunyikan isi postingan di linimasa.
- **Visibilitas 4 Tingkat:** 
  1. *Publik* (Muncul di semua linimasa dan pencarian).
  2. *Tidak Terdaftar* (Bisa dilihat siapa saja tapi tidak masuk linimasa umum).
  3. *Hanya Pengikut* (Hanya akun yang disetujui yang dapat membaca).
  4. *Pesan Langsung* (Hanya akun yang di-mention).
- **Media & Alt-Text:** Pengingat pentingnya deskripsi gambar demi aksesibilitas tunanetra.

### 2.6 Lembar Percakapan (Thread Modal View)
- Menampilkan rantai hierarki: post induk -> post aktif yang disorot dengan bingkai hijau -> daftar balasan bertingkat dengan garis pandu vertikal.

---

## 3. Sistem Desain & Visual Tokens

| Token | Nilai Light Mode | Nilai Dark Mode | Deskripsi |
|---|---|---|---|
| **Primary Accent** | `#236B55` (Forest Teal) | `#83C9AE` (Mint Sage) | Tombol aksi utama, tab aktif |
| **Surface Canvas** | `#F7F8F6` (Warm Paper) | `#161918` (Deep Slate) | Background dasar aplikasi |
| **Surface Card** | `#FFFFFF` | `#202422` | Permukaan kartu feed & modal |
| **App Chrome** | `#FFFFFF` (opacity 96%) | `#202422` (opacity 96%) | Header bar terpadu |
| **Divider / Border** | Alpha 10% onText | Alpha 12% onText | Garis pemisah halus |
| **Status Connection** | `#38A979` (Active Green) | `#38A979` (Active Green) | Indikator live server Fediverse |
| **Text Primary** | `#1A201E` | `#EDF2EF` | Judul, isi bacaan |
| **Text Secondary** | `#6B7470` | `#9AA4A0` | Handle, waktu, placeholder |
| **Font Family** | `.SF Pro Text`, sans-serif | `.SF Pro Text`, sans-serif | Tipografi minimalis Cupertino |

---

## 4. Stack Teknis Terencana

- **Frontend Framework:** Flutter 3.x (Dart 3.x) dengan target Linux Desktop (GTK3 runner / Flatpak).
- **State Management:** Riverpod (Notifier & AsyncNotifier pattern).
- **Protokol / API:** Mastodon REST API v1/v2 & WebSockets Streaming.
- **Storage Aman:** Linux Secret Service via DBus (`libsecret`) untuk token OAuth.
- **Penyimpanan Lokal:** SQLite / Drift untuk draft offline & caching feed.

---

## 5. Rencana Penerimaan & Uji Desain (Acceptance Criteria)
1. Keempat layar (Beranda, Cari, Aktivitas, Profil) dapat diakses dan diuji navigasinya.
2. Filter linimasa (Mengikuti / Lokal / Federasi) responsif terhadap ketukan.
3. Komponen composer interaktif menampilkan opsi CW, Visibilitas, dan Alt-Text.
4. Thread modal dapat dibuka untuk membaca percakapan mendalam.
5. Seluruh alur divalidasi dengan suite `flutter test` otomatis.
