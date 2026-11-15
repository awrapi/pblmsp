# 🍅 TomatoSim - Dashboard Simulasi Model Pertanian Tanaman Tomat
**Tugas Project-Based Learning (PBL) - Model Simulasi Pertanian (MSP) 2026**  
*Departemen Geofisika dan Meteorologi, IPB University*  
**Dosen Pembimbing:** Impron, M. Sc. & Yon Sugiarto, M. Sc.  
**Kelompok 4:**
- G2401241011 - Ekane Susiana
- G2401241012 - Nurul Wardah
- G2401241020 - Muhammad Habib Ismail Ilham
- G2401241029 - Hanifah Quratu Aini Suwarno
- G2401241044 - Diva Khaerunnisa
- G2401241049 - Celine Alecia Tanasha
- G2401241060 - Puput Dwiyanti Nurhayadi
- G2401241063 - Kezia Regina
- G2401241070 - Arrafi Radityo Jatmiko
- G2401241074 - Annisa Eka Ardani

---

## 🌟 Apa yang Baru di TomatoSim?
Dibandingkan versi awal R Shiny (`dasbord.R`) yang kaku dan memerlukan instalasi R:
1. **Desain UI Modern *"Playful Professional"***:
   - Terinspirasi dari konsep UI PinHome/modern Dribbble dengan *curved tab notch*, palet hijau daun tomat (`#0C745E`), aksen merah tomat masak (`#E11D48`), dan kartu-kartu berbayang halus.
   - Tetap memiliki nilai ilmiah yang sangat tinggi dan presisi.
2. **Dukungan Dataset Eksternal Dinamis**:
   - Pengguna bisa mengunggah dataset iklim sendiri (misal: **tahun 1999–2020** atau tahun lain) dalam format `.xlsx` atau `.csv`.
   - Sistem secara cerdas mendeteksi kolom secara otomatis (*smart column mapping*), membersihkan data, dan menyesuaikan pilihan tanggal tanam secara instan.
3. **Validasi Model vs Data Observasi Riil**:
   - Memanfaatkan data observasi lapangan dari file `DATA IKLIM  2016-2025.xlsx`:
     - **Sheet `DATA BIOMASSA`**: Validasi bobot organ (Daun, Batang, Buah, Akar).
     - **Sheet `LUAS PANEN` & `PRODUKSI`**: Tren statistik riil Kabupaten Garut & Bogor.
4. **Uji Sensitivitas Iklim Interaktif**:
   - Slider real-time untuk melihat dampak kenaikan suhu udara (+ΔT), kelembaban (+ΔRH), dan curah hujan (+ΔCH).
5. **Ekspor Data & Laporan**:
   - Unduh hasil simulasi harian dan ringkasan KPI dalam format **Excel (.xlsx)** atau **CSV (.csv)**.

---

## 🚀 Cara Menjalankan Aplikasi Secara Lokal

### Cara Termudah:
Cukup klik ganda file **`start.bat`** di folder ini!  
Browser akan otomatis membuka `http://127.0.0.1:8000`.

### Cara Terminal / Command Line:
1. Buka PowerShell / Terminal di folder `MSP`:
   ```bash
   pip install -r requirements.txt
   python app.py
   ```
2. Buka browser di:
   ```
   http://127.0.0.1:8000
   ```

---

## 🌐 Cara Deploy Gratis ke Web (Tanpa Perlu Codingan Lokal)

Aplikasi ini sudah siap di-deploy ke berbagai platform cloud gratis sehingga dosen atau pengguna lain cukup membuka link web dari browser (laptop maupun smartphone):

### Opsi 1: Render.com (Sangat Direkomendasikan - Gratis)
1. Buat akun di [Render.com](https://render.com).
2. Upload folder ini ke repository GitHub Anda.
3. Di Render, pilih **New +** $\rightarrow$ **Web Service** $\rightarrow$ hubungkan dengan repo GitHub.
4. Konfigurasi:
   - **Environment**: `Python 3`
   - **Build Command**: `pip install -r requirements.txt`
   - **Start Command**: `uvicorn app:app --host 0.0.0.0 --port $PORT`
5. Klik **Create Web Service**. Dalam 1-2 menit, Anda akan mendapatkan link publik gratis (contoh: `https://tomatosim-pbl.onrender.com`).

### Opsi 2: Railway.app / Koyeb
- Cukup hubungkan repository GitHub dan biarkan platform mendeteksi `requirements.txt` dan menjalankan `uvicorn app:app --host 0.0.0.0 --port $PORT`.

---

## 📂 Struktur File di Folder MSP

```
MSP/
├── app.py                     # Backend server FastAPI & controller simulasi
├── model_simulasi.py          # Engine matematika & biofisik simulasi tomat
├── templates/
│   └── index.html             # Tampilan dashboard modern (Tailwind + Chart.js)
├── start.bat                  # Script 1-klik untuk menjalankan dashboard lokal
├── requirements.txt           # Dependensi Python untuk deployment
├── DATA IKLIM  2016-2025.xlsx # Dataset iklim Garut, Bogor, & data validasi riil
├── dasbord.R                  # File R Shiny bawaan sebelumnya
└── README.md                  # Dokumentasi panduan lengkap
```
