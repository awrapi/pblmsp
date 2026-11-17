"""
Model Simulasi Tanaman Tomat (Solanum lycopersicum L.)
Porting dari model R (PBL Model Simulasi Pertanian / MSP)
Departemen Geofisika dan Meteorologi - IPB University
"""

import numpy as np
import pandas as pd
from datetime import datetime

DEFAULT_PARAMS = {
    # Parameter Tanaman
    "k": 0.67,             # Koefisien pemadaman tajuk
    "sla": 203.0,          # Specific Leaf Area (cm2/g)
    "rue": 1.05,           # Radiation Use Efficiency (g/MJ)
    "tb": 10.0,            # Suhu dasar (°C)
    "kg": 0.70,            # Koefisien respirasi pertumbuhan
    "km": 0.00042,         # Koefisien respirasi pemeliharaan
    "tu1": 324.0,          # Thermal Units Fase 1 (Bibit)
    "tu2": 250.0,          # Thermal Units Fase 2 (Vegetatif cepat)
    "tu3": 323.0,          # Thermal Units Fase 3 (Pembungaan)
    "tu4": 298.0,          # Thermal Units Fase 4 (Pembesaran buah)
    "tu5": 361.0,          # Thermal Units Fase 5 (Pematangan)
    "LAI_awal": 1.2,       # Leaf Area Index awal
    "wbatang_awal": 112.2, # Bobot batang awal (g BK/m2)
    "wakar_awal": 9.9,     # Bobot akar awal (g BK/m2)
    "bobot_fase": [0.15, 0.25, 0.15, 0.45], # Bobot indeks perkembangan s (4 fase)
    "partisi": [
        [0.40, 0.35, 0.25, 0.00], # Fase 1: Daun, Batang, Akar, Buah
        [0.40, 0.35, 0.25, 0.00], # Fase 2
        [0.30, 0.30, 0.20, 0.20], # Fase 3
        [0.15, 0.20, 0.15, 0.50], # Fase 4
        [0.05, 0.10, 0.10, 0.75]  # Fase 5
    ],
    # Parameter Tanah & Neraca Air
    "KATawal": 0.13,       # Kadar air tanah awal (fraksi volume)
    "KL": 0.343,           # Kapasitas Lapang (fraksi volume)
    "TLP": 0.1108,         # Titik Layu Permanen (fraksi volume)
    "Zr": 700.0,           # Kedalaman perakaran efektif (mm)
    "runoff_frac": 0.15,   # Fraksi limpasan permukaan (0-1)
    "coef_Ic": 0.2,        # Koefisien intersepsi tajuk
    "Ic_maks": 3.0,        # Intersepsi maksimum (mm)
    "U": 8.0,              # Ambang evaporasi Ritchie tahap 1 (mm)
    "alpha": 3.5,          # Koefisien Ritchie tahap 2 (mm/akar hari)
    "reset_hujan": 5.0,    # Infiltrasi minimal pengeringan reset (mm)
    "kc_fase": [0.60, 1.15, 0.70, 0.70], # Kc untuk 4 fase
    # Parameter Geografis (Default Garut)
    "Alt": 717.0,          # Ketinggian tempat (m dpl)
    "Lat": -7.3895,        # Lintang wilayah (derajat)
    "tinggi_angin": 2.0    # Ketinggian anemometer (m)
}

COL_ALIASES = {
    "tgl": ["tgl", "tanggal", "date", "time", "datetime", "waktu"],
    "suhu": ["suhu", "temp", "temperature", "tavg", "t2m", "suhu_rata"],
    "rh": ["rh", "kelembaban", "humidity", "rh2m", "kelembaban_relatif"],
    "ch": ["ch", "curah_hujan", "rain", "precip", "precipitation", "hujan"],
    "Rs": ["rs", "radiasi", "solar_rad", "radiation", "penyinaran", "radiasisurya"],
    "angin": ["angin", "wind", "wind_speed", "kecepatan_angin", "u2", "ff"]
}


def siapkan_data(source, sheet_name=None):
    """
    Membaca data iklim dari file (Excel/CSV) atau DataFrame.
    Mendukung deteksi kolom otomatis, imputasi missing values, dan validasi tanggal.
    """
    if isinstance(source, pd.DataFrame):
        df = source.copy()
    elif isinstance(source, str):
        if source.lower().endswith((".xlsx", ".xls")):
            df = pd.read_excel(source, sheet_name=sheet_name or 0)
        else:
            df = pd.read_csv(source)
    else:
        raise ValueError("Source harus berupa DataFrame atau path file (Excel/CSV).")

    # Pencocokan nama kolom fleksibel
    col_map = {}
    lower_cols = {str(c).strip().lower(): c for c in df.columns}

    for target, aliases in COL_ALIASES.items():
        matched = None
        for alias in aliases:
            if alias.lower() in lower_cols:
                matched = lower_cols[alias.lower()]
                break
        if matched:
            col_map[matched] = target

    if len(col_map) == 6:
        df = df[list(col_map.keys())].rename(columns=col_map)
    elif df.shape[1] >= 6:
        # Fallback layout posisi: Kolom 1..6 jika nama kolom berbeda
        sub = df.iloc[:, :6].copy()
        sub.columns = ["tgl", "suhu", "rh", "ch", "Rs", "angin"]
        df = sub
    else:
        raise ValueError(
            f"Data harus memiliki 6 kolom iklim: tgl, suhu, rh, ch, Rs, angin. Ditemukan: {list(df.columns)}"
        )

    # Parsing Tanggal
    df["tgl"] = pd.to_datetime(df["tgl"], errors="coerce")
    if df["tgl"].isna().any():
        df = df.dropna(subset=["tgl"])
    df = df.sort_values("tgl").drop_duplicates(subset=["tgl"]).reset_index(drop=True)

    # Konversi numerik & Imputasi
    imputed_info = {}
    for col in ["suhu", "rh", "Rs", "angin"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")
        null_count = df[col].isna().sum()
        imputed_info[col] = int(null_count)
        if null_count > 0:
            mean_val = df[col].mean()
            if np.isnan(mean_val):
                raise ValueError(f"Tidak ada nilai valid untuk kolom {col}.")
            df[col] = df[col].fillna(mean_val)

    # Imputasi curah hujan: NA -> 0
    df["ch"] = pd.to_numeric(df["ch"], errors="coerce")
    imputed_info["ch"] = int(df["ch"].isna().sum())
    df["ch"] = df["ch"].fillna(0.0)

    return df, imputed_info


def simulasi_tomat(P, df_cuaca, tgl_tanam, ps=0.0, prh=0.0, pch=0.0):
    """
    Eksekusi model biofisik simulasi tanaman tomat.
    Mengembalikan: DataFrame hasil harian (HST 1 s.d. Panen) dan dict ringkasan performa.
    """
    params = DEFAULT_PARAMS.copy()
    params.update(P)

    tgl_tanam = pd.to_datetime(tgl_tanam)
    data0 = df_cuaca[df_cuaca["tgl"] >= tgl_tanam].copy().reset_index(drop=True)
    if len(data0) < 2:
        raise ValueError("Data iklim setelah tanggal tanam tidak mencukupi (minimal 2 hari).")

    # Skenario perubahan iklim
    ps = float(ps) if not np.isnan(ps) else 0.0
    prh = float(prh) if not np.isnan(prh) else 0.0
    pch = float(pch) if not np.isnan(pch) else 0.0

    data0["suhu"] = data0["suhu"] + ps
    data0["rh"] = np.clip(data0["rh"] + prh, 0.0, 100.0)
    data0["ch"] = np.maximum(0.0, data0["ch"] + pch)

    # Loop 1: Akumulasi Satuan Panas (Thermal Units / TU)
    tu = np.array([params["tu1"], params["tu2"], params["tu3"], params["tu4"], params["tu5"]], dtype=float)
    tu_total = tu.sum()
    batas = np.concatenate(([0.0], np.cumsum(tu)))

    tu_hari = np.maximum(data0["suhu"].values - params["tb"], 0.0)
    # R script: TU_kumul <- c(0, cumsum(TU_hari[-1]))
    tu_kumul = np.zeros(len(data0), dtype=float)
    if len(data0) > 1:
        tu_kumul[1:] = np.cumsum(tu_hari[1:])

    idx_matang_candidates = np.where(tu_kumul >= tu_total)[0]
    if len(idx_matang_candidates) == 0:
        raise ValueError(
            f"Kemasakan belum tercapai! Panjang data iklim ({len(data0)} hari) belum cukup "
            f"untuk mencapai target satuan panas ({tu_total:.0f} °C hari). Perlu tanggal tanam lebih awal atau data lebih panjang."
        )

    idx_matang = idx_matang_candidates[0] + 1  # 1-indexed count in R
    data = data0.iloc[:idx_matang].copy().reset_index(drop=True)
    tu_kumul = tu_kumul[:idx_matang]
    n = len(data)
    HST = np.arange(1, n + 1)

    # Penentuan Fase (1-indexed fase 1-5, di R: pmin(4L, findInterval(TU_kumul, batas, rightmost.closed=TRUE)))
    # Di R, findInterval(TU_kumul, batas, rightmost.closed=TRUE) menghasilkan interval index 1..5
    fase_idx_raw = np.searchsorted(batas, tu_kumul, side="right")  # 1..5
    fase_idx = np.clip(fase_idx_raw, 1, 4)  # 1..4 untuk indeks parameter 4-fase
    fase_display = np.clip(fase_idx_raw, 1, 5)

    bobot_fase = np.array(params["bobot_fase"], dtype=float)
    awal_s = np.concatenate(([0.0], np.cumsum(bobot_fase)))

    # Indeks perkembangan s (0..1)
    fase_zero = fase_idx - 1
    prop_fase = np.clip((tu_kumul - batas[fase_zero]) / tu[fase_zero], 0.0, 1.0)
    s = awal_s[fase_zero] + bobot_fase[fase_zero] * prop_fase
    s[-1] = 1.0
    ds = np.concatenate(([0.0], np.diff(s)))

    # Parameter ekstraksi
    partisi = np.array(params["partisi"], dtype=float)
    kc_fase = np.array(params["kc_fase"], dtype=float)
    Lat = float(params["Lat"])
    Alt = float(params["Alt"])
    tinggi_angin = float(params["tinggi_angin"])
    k_ext = float(params["k"])
    sla = float(params["sla"])
    rue = float(params["rue"])
    kg = float(params["kg"])
    km = float(params["km"])
    Zr = float(params["Zr"])
    KATawal = float(params["KATawal"])
    KL = float(params["KL"])
    TLP = float(params["TLP"])
    runoff_frac = float(params["runoff_frac"])
    coef_Ic = float(params["coef_Ic"])
    Ic_maks = float(params["Ic_maks"])
    U = float(params["U"])
    alpha = float(params["alpha"])
    reset_hujan = float(params["reset_hujan"])

    # Inisialisasi array harian
    v = lambda: np.zeros(n, dtype=float)
    Rs, ETo, kc, etc, em, tm, ea, ta = v(), v(), v(), v(), v(), v(), v(), v()
    ic, ch_ef, ro, infiltrasi, pc, wdf, S = v(), v(), v(), v(), v(), v(), v()
    Qint, dW, Ba, Rg, Rm, lai = v(), v(), v(), v(), v(), v()
    wdaun, wbatang, wakar, wbuah, wtot = v(), v(), v(), v(), v()
    residu_air, residu_biomassa = v(), v()

    Rs[0] = data["Rs"].iloc[0]
    lai[0] = float(params["LAI_awal"])
    wdaun[0] = lai[0] * 10000.0 / sla
    wbatang[0] = float(params["wbatang_awal"])
    wakar[0] = float(params["wakar_awal"])
    wtot[0] = wdaun[0] + wbatang[0] + wakar[0]
    S[0] = KATawal * Zr
    wdf[0] = np.clip((KATawal - TLP) / (KL - TLP), 0.0, 1.0)

    E1_kumul = 0.0
    hari_tahap2 = 0

    # Konstanta radiasi astronomis
    phi = Lat * np.pi / 180.0
    Pat = 101.3 * (((293.0 - 0.0065 * Alt) / 293.0) ** 5.26)
    gamma = 0.000665 * Pat
    Rso_factor = 0.75 + 2e-5 * Alt
    u2_factor = 4.87 / np.log(67.8 * tinggi_angin - 5.42)
    S_fc = KL * Zr
    S_wp = TLP * Zr

    # Loop 2: Radiasi, ETo, Neraca Air, dan Asimilasi Biomassa
    for i in range(1, n):
        T = float(data["suhu"].iloc[i])
        RH = float(data["rh"].iloc[i])
        CH = float(data["ch"].iloc[i])
        date_i = data["tgl"].iloc[i]
        J = int(date_i.strftime("%j"))

        # 1. Radiasi Ekstraterestrial (Ra) & Bersih (Rn) - FAO-56
        dr = 1.0 + 0.033 * np.cos(2.0 * np.pi * J / 365.0)
        delta = 0.409 * np.sin(2.0 * np.pi * J / 365.0 - 1.39)
        val_ws = -np.tan(phi) * np.tan(delta)
        ws = np.arccos(np.clip(val_ws, -1.0, 1.0))
        Ra = (24.0 * 60.0 / np.pi) * 0.082 * dr * (
            ws * np.sin(phi) * np.sin(delta) + np.cos(phi) * np.cos(delta) * np.sin(ws)
        )
        Rs[i] = float(data["Rs"].iloc[i])
        Rso = Rso_factor * Ra
        es = 0.6108 * np.exp(17.27 * T / (T + 237.3))
        eakt = (RH / 100.0) * es
        Delta = 4098.0 * es / ((T + 237.3) ** 2)
        Rns = 0.77 * Rs[i]
        cloud_factor = np.maximum(0.0, 1.35 * np.minimum(1.0, Rs[i] / Rso) - 0.35)
        Rnl = 4.903e-9 * ((T + 273.16) ** 4) * (0.34 - 0.14 * np.sqrt(eakt)) * cloud_factor
        Rn = Rns - Rnl

        # 2. Penman-Monteith Reference Evapotranspiration (ETo)
        u2 = float(data["angin"].iloc[i]) * u2_factor
        num_eto = 0.408 * Delta * Rn + gamma * (900.0 / (T + 273.0)) * u2 * (es - eakt)
        den_eto = Delta + gamma * (1.0 + 0.34 * u2)
        ETo[i] = max(0.0, num_eto / den_eto)

        current_fase_idx = fase_idx[i] - 1  # 0..3
        kc[i] = kc_fase[current_fase_idx]
        etc[i] = kc[i] * ETo[i]

        # 3. Neraca Air Tanah (Ritchie Model)
        lailama = lai[i - 1]
        ic[i] = min(CH, coef_Ic * lailama if lailama <= 3.0 else Ic_maks)
        ch_ef[i] = CH - ic[i]
        ro[i] = runoff_frac * ch_ef[i]
        infiltrasi[i] = ch_ef[i] - ro[i]

        setelah_hujan = S[i - 1] + infiltrasi[i]
        pc[i] = max(0.0, setelah_hujan - S_fc)
        tersedia = setelah_hujan - pc[i]

        em[i] = etc[i] * np.exp(-k_ext * lailama)
        tm[i] = max(0.0, etc[i] - em[i])

        if infiltrasi[i] >= reset_hujan:
            E1_kumul = 0.0
            hari_tahap2 = 0

        if E1_kumul < U:
            Ea_pot = em[i]
        else:
            hari_tahap2 += 1
            Ea_pot = min(em[i], alpha * (np.sqrt(hari_tahap2) - np.sqrt(hari_tahap2 - 1)))

        air_bisa_diambil = max(0.0, tersedia - S_wp)
        ea[i] = min(Ea_pot, air_bisa_diambil)
        if E1_kumul < U:
            E1_kumul += ea[i]

        faktor_air = np.clip(air_bisa_diambil / (S_fc - S_wp), 0.0, 1.0)
        ta[i] = min(tm[i] * faktor_air, max(0.0, air_bisa_diambil - ea[i]))
        wdf[i] = (ta[i] / tm[i]) if tm[i] > 1e-12 else 1.0

        S[i] = tersedia - ea[i] - ta[i]
        residu_air[i] = S[i] - (S[i - 1] + CH - ic[i] - ro[i] - pc[i] - ea[i] - ta[i])

        # 4. Asimilasi Radiasi & Biomassa
        Qint[i] = Rs[i] * (1.0 - np.exp(-k_ext * lailama))
        dW[i] = rue * Qint[i]
        Ba[i] = dW[i] * wdf[i]
        Rg[i] = kg * Ba[i]
        Bnet = Ba[i] - Rg[i]

        Q10 = 2.0 ** ((T - 20.0) / 10.0)
        Wlama = np.array([wdaun[i - 1], wbatang[i - 1], wakar[i - 1], wbuah[i - 1]])
        partisi_fase = partisi[current_partisi_idx]
        alokasi = Bnet * partisi_fase
        resp = np.minimum(km * Q10 * Wlama, Wlama + alokasi)
        baru = Wlama + alokasi - resp

        wdaun[i] = baru[0]
        wbatang[i] = baru[1]
        wakar[i] = baru[2]
        wbuah[i] = baru[3]
        Rm[i] = resp.sum()
        wtot[i] = baru.sum()
        lai[i] = sla * wdaun[i] / 10000.0
        residu_biomassa[i] = (wtot[i] - wtot[i - 1]) - (Bnet - Rm[i])

    # DataFrame Hasil
    fase_names = [f"Fase-{idx}" for idx in fase_display]
    ETa = ea + ta

    # Water Use Efficiency (WUE)
    diff_wtot = np.diff(wtot)
    wue = np.full(n, np.nan, dtype=float)
    valid_et = ETa[1:] > 0.01
    wue[1:][valid_et] = diff_wtot[valid_et] / ETa[1:][valid_et]

    df_hasil = pd.DataFrame({
        "Tanggal": data["tgl"].dt.strftime("%Y-%m-%d"),
        "HST": HST,
        "Fase": fase_names,
        "s": s,
        "ds": ds,
        "Suhu": data["suhu"].round(2),
        "RH": data["rh"].round(2),
        "CH": data["ch"].round(2),
        "Radiasi": Rs.round(2),
        "ETo": ETo.round(3),
        "ETc": etc.round(3),
        "Em": em.round(3),
        "Ea": ea.round(3),
        "Tm": tm.round(3),
        "Ta": ta.round(3),
        "ETa": ETa.round(3),
        "Intersepsi": ic.round(3),
        "CH_ef": ch_ef.round(3),
        "Runoff": ro.round(3),
        "Infiltrasi": infiltrasi.round(3),
        "Perkolasi": pc.round(3),
        "SimpananAir_mm": S.round(2),
        "KAT": (S / Zr).round(4),
        "KAT_persen": (S / Zr * 100.0).round(2),
        "WDF": wdf.round(3),
        "Qint": Qint.round(3),
        "Bp": dW.round(3),
        "Ba": Ba.round(3),
        "Rg": Rg.round(3),
        "Rm": Rm.round(3),
        "Daun": wdaun.round(2),
        "Batang": wbatang.round(2),
        "Akar": wakar.round(2),
        "Buah": wbuah.round(2),
        "Total": wtot.round(2),
        "LAI": lai.round(3),
        "ProdBuah_tonBK_ha": (0.01 * wbuah).round(3),
        "ProdDaun_tonBK_ha": (0.01 * wdaun).round(3),
        "ProdBatang_tonBK_ha": (0.01 * wbatang).round(3),
        "ProdAkar_tonBK_ha": (0.01 * wakar).round(3),
        "ProdTotal_tonBK_ha": (0.01 * wtot).round(3),
        "WUE_gL": np.round(wue, 3),
        "ResiduAir_mm": residu_air.round(6),
        "ResiduBiomassa_gm2": residu_biomassa.round(6)
    })

    # Ringkasan Eksekutif
    ringkasan = {
        "hst_panen": int(HST[-1]),
        "tanggal_panen": str(data["tgl"].iloc[-1].strftime("%d %b %Y")),
        "prod_buah_ton_ha": float(np.round(0.01 * wbuah[-1], 3)),
        "prod_daun_ton_ha": float(np.round(0.01 * wdaun[-1], 3)),
        "prod_batang_ton_ha": float(np.round(0.01 * wbatang[-1], 3)),
        "prod_akar_ton_ha": float(np.round(0.01 * wakar[-1], 3)),
        "prod_total_ton_ha": float(np.round(0.01 * wtot[-1], 3)),
        "lai_maks": float(np.round(lai.max(), 3)),
        "total_ch_mm": float(np.round(data["ch"].sum(), 2)),
        "total_eta_mm": float(np.round(ETa.sum(), 2)),
        "rata_suhu": float(np.round(data["suhu"].mean(), 2)),
        "rata_wdf": float(np.round(wdf.mean(), 3)),
        "rata_wue": float(np.round(np.nanmean(wue), 3)),
        "biomassa_daun_g": float(np.round(wdaun[-1], 2)),
        "biomassa_batang_g": float(np.round(wbatang[-1], 2)),
        "biomassa_buah_g": float(np.round(wbuah[-1], 2)),
        "biomassa_akar_g": float(np.round(wakar[-1], 2)),
    }

    return df_hasil, ringkasan
