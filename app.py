"""
TomatoSim Web Application - FastAPI Server
Model Simulasi Pertanian (PBL MSP - Tanaman Tomat)
Kelompok 3 - Departemen GFM, IPB University
"""

import io
import os
import uvicorn
import pandas as pd
from datetime import datetime
from typing import Dict, Any, Optional
from fastapi import FastAPI, UploadFile, File, HTTPException, Query
from fastapi.responses import HTMLResponse, StreamingResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

import model_simulasi as ms

app = FastAPI(title="TomatoSim - Agro-Meteorological Crop Simulation")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
EXCEL_PATH = os.path.join(BASE_DIR, "DATA IKLIM  2016-2025.xlsx")

# In-memory storage for datasets & last simulation
PRESET_DATASETS = {}
CUSTOM_DATASET = None
LAST_SIMULATION_RESULT = None
LAST_SUMMARY = None

def init_datasets():
    """Memuat dataset bawaan Garut dan Bogor ke memory saat aplikasi mulai."""
    global PRESET_DATASETS
    if os.path.exists(EXCEL_PATH):
        try:
            df_garut, _ = ms.siapkan_data(EXCEL_PATH, sheet_name="DATA IKLIM GARUT")
            PRESET_DATASETS["garut"] = df_garut
            df_bogor, _ = ms.siapkan_data(EXCEL_PATH, sheet_name="DATA IKLIM BOGOR")
            PRESET_DATASETS["bogor"] = df_bogor
            print("Berhasil memuat dataset Garut (", len(df_garut), "hari) dan Bogor (", len(df_bogor), "hari).")
        except Exception as e:
            print("Peringatan saat inisialisasi data:", e)

init_datasets()


class SimulationRequest(BaseModel):
    source: str = "garut"
    tgl_tanam: str = "2015-01-01"
    psuhu: float = 0.0
    prh: float = 0.0
    pch: float = 0.0
    params: Optional[Dict[str, Any]] = None


@app.get("/", response_class=HTMLResponse)
async def serve_index():
    """Melayani antarmuka dashboard utama."""
    html_file = os.path.join(BASE_DIR, "templates", "index.html")
    if not os.path.exists(html_file):
        raise HTTPException(status_code=404, detail="File index.html tidak ditemukan")
    with open(html_file, "r", encoding="utf-8") as f:
        return f.read()


@app.post("/api/simulate")
async def run_simulation_api(req: SimulationRequest):
    """Menjalankan simulasi biofisik model tomat."""
    global LAST_SIMULATION_RESULT, LAST_SUMMARY

    # Pilih sumber dataset
    if req.source == "custom":
        if CUSTOM_DATASET is None:
            raise HTTPException(status_code=400, detail="Belum ada dataset custom yang diunggah.")
        df_cuaca = CUSTOM_DATASET
    elif req.source == "bogor":
        df_cuaca = PRESET_DATASETS.get("bogor")
    else:
        df_cuaca = PRESET_DATASETS.get("garut")

    if df_cuaca is None:
        raise HTTPException(status_code=500, detail="Dataset cuaca tidak tersedia.")

    # Atur parameter
    user_params = req.params or {}
    # Koordinat otomatis sesuai lokasi jika tidak di-override
    if req.source == "bogor" and "Alt" not in user_params:
        user_params["Alt"] = 260.0
        user_params["Lat"] = -6.5950
    elif req.source == "garut" and "Alt" not in user_params:
        user_params["Alt"] = 717.0
        user_params["Lat"] = -7.3895

    try:
        df_hasil, summary = ms.simulasi_tomat(
            P=user_params,
            df_cuaca=df_cuaca,
            tgl_tanam=req.tgl_tanam,
            ps=req.psuhu,
            prh=req.prh,
            pch=req.pch
        )

        # Baseline komparasi jika ada skenario perubahan iklim
        baseline_summary = None
        baseline_daily = None
        if req.psuhu != 0.0 or req.prh != 0.0 or req.pch != 0.0:
            try:
                df_base, baseline_summary = ms.simulasi_tomat(
                    P=user_params,
                    df_cuaca=df_cuaca,
                    tgl_tanam=req.tgl_tanam,
                    ps=0.0,
                    prh=0.0,
                    pch=0.0
                )
                baseline_daily = {
                    "HST": df_base["HST"].tolist(),
                    "Buah": [None if pd.isna(x) else x for x in df_base["ProdBuah_tonBK_ha"].tolist()],
                    "Total": [None if pd.isna(x) else x for x in df_base["ProdTotal_tonBK_ha"].tolist()],
                    "LAI": [None if pd.isna(x) else x for x in df_base["LAI"].tolist()],
                    "ETa": [None if pd.isna(x) else x for x in df_base["ETa"].tolist()],
                }
            except Exception:
                baseline_summary = None
                baseline_daily = None

    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

    LAST_SIMULATION_RESULT = df_hasil
    LAST_SUMMARY = summary

    # Bersihkan NaN agar valid JSON
    clean_dict = {
        col: [None if pd.isna(x) else x for x in df_hasil[col].tolist()]
        for col in df_hasil.columns
    }
    clean_summary = {
        k: (None if pd.isna(v) else v)
        for k, v in summary.items()
    }
    clean_baseline = (
        {k: (None if pd.isna(v) else v) for k, v in baseline_summary.items()}
        if baseline_summary else None
    )

    return {
        "status": "success",
        "summary": clean_summary,
        "baseline_summary": clean_baseline,
        "baseline_daily": baseline_daily,
        "daily": clean_dict
    }


@app.post("/api/upload")
async def upload_custom_dataset(file: UploadFile = File(...)):
    """Menerima unggahan dataset iklim eksternal (1999 s.d. 2020 / bebas)."""
    global CUSTOM_DATASET

    contents = await file.read()
    filename = file.filename.lower()

    try:
        if filename.endswith((".xlsx", ".xls")):
            raw_df = pd.read_excel(io.BytesIO(contents))
        elif filename.endswith(".csv"):
            raw_df = pd.read_csv(io.BytesIO(contents))
        else:
            raise HTTPException(status_code=400, detail="Format harus berupa Excel (.xlsx/.xls) atau CSV (.csv)")

        clean_df, imputed_info = ms.siapkan_data(raw_df)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Gagal memproses file: {str(e)}")

    CUSTOM_DATASET = clean_df

    date_min = clean_df["tgl"].min().strftime("%Y-%m-%d")
    date_max = clean_df["tgl"].max().strftime("%Y-%m-%d")

    return {
        "status": "success",
        "filename": file.filename,
        "rows": len(clean_df),
        "date_min": date_min,
        "date_max": date_max,
        "imputed": imputed_info
    }


@app.get("/api/validation")
async def get_validation_data():
    """Mengambil data riil observasi biomassa dan statistik produksi historis."""
    historical = []
    if os.path.exists(EXCEL_PATH):
        try:
            df_panen = pd.read_excel(EXCEL_PATH, sheet_name="LUAS PANEN ").dropna(subset=["Tahun"])
            df_prod = pd.read_excel(EXCEL_PATH, sheet_name="PRODUKSI").dropna(subset=["Tahun"])

            merged = pd.merge(df_panen, df_prod, on="Tahun")
            for _, r in merged.iterrows():
                historical.append({
                    "tahun": int(r["Tahun"]),
                    "garut_ha": float(r.get("Garut( ha)", 0)),
                    "garut_ton": float(r.get("Garut (ton)", 0)),
                    "bogor_ha": float(r.get("Bogor (ha)", 0)),
                    "bogor_ton": float(r.get("Bogor (ton)", 0)),
                })
        except Exception as e:
            print("Gagal membaca data historis:", e)

    return {
        "benchmarks": {
            "Daun": {"min": 152.1, "max": 177.2, "unit": "g"},
            "Batang": {"min": 88.6, "max": 112.2, "unit": "g"},
            "Buah": {"min": 217.5, "max": 249.8, "unit": "g"},
            "Akar": {"min": 0.009, "max": 0.352, "unit": "g"},
        },
        "historical": historical
    }


@app.get("/api/export/excel")
async def export_excel():
    """Export hasil simulasi aktif ke file Excel dengan 2 sheet."""
    global LAST_SIMULATION_RESULT, LAST_SUMMARY
    if LAST_SIMULATION_RESULT is None:
        raise HTTPException(status_code=400, detail="Belum ada simulasi yang dijalankan.")

    output = io.BytesIO()
    with pd.ExcelWriter(output, engine="openpyxl") as writer:
        LAST_SIMULATION_RESULT.to_excel(writer, sheet_name="Hasil_Harian_HST", index=False)
        if LAST_SUMMARY:
            df_sum = pd.DataFrame(list(LAST_SUMMARY.items()), columns=["Parameter", "Nilai"])
            df_sum.to_excel(writer, sheet_name="Ringkasan_KPI", index=False)

    output.seek(0)
    filename = f"simulasi_tomat_{datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
    return StreamingResponse(
        output,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )


@app.get("/api/export/csv")
async def export_csv():
    """Export hasil simulasi aktif ke CSV."""
    global LAST_SIMULATION_RESULT
    if LAST_SIMULATION_RESULT is None:
        raise HTTPException(status_code=400, detail="Belum ada simulasi yang dijalankan.")

    csv_data = LAST_SIMULATION_RESULT.to_csv(index=False)
    filename = f"simulasi_tomat_harian_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    return StreamingResponse(
        io.StringIO(csv_data),
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )


if __name__ == "__main__":
    print("[TomatoSim] Menjalankan Server di http://127.0.0.1:8000 ...")
    uvicorn.run("app:app", host="127.0.0.1", port=8000, reload=True)
