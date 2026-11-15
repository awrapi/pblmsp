@echo off
title TomatoSim - Model Pertanian Tomat (PBL MSP)
echo ========================================================
echo        TomatoSim - Model Simulasi Tanaman Tomat
echo        Kelompok 3 - PBL Model Simulasi Pertanian
echo ========================================================
echo Membuka browser di http://127.0.0.1:8000 ...
timeout /t 2 >nul
start http://127.0.0.1:8000
python app.py
pause
