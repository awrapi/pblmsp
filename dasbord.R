
# shiny::runApp("~/Sem 5/MSP/PBL/app.R")
# Dashboard Model Simulasi Tomat (disesuaikan dengan kodingan model Praktikan)
# Paket: install.packages(c("shiny","shinydashboard","plotly","readxl","openxlsx"))
library(shiny); library(shinydashboard); library(plotly); library(readxl); library(openxlsx)

kol <- c("tgl","suhu","rh","ch","Rs","angin")

# ---------- Helper UI ----------
mk <- function(spec) lapply(spec, function(s) numericInput(s[1], s[2], as.numeric(s[3])))
ref <- function(txt) p(HTML(paste0("<ol><ul style='padding:0;'><p style='text-indent:-40px;text-align:Justify;'>",txt,"</p></ul></ol>")))
nxt <- function(id) actionButton(id, "Next", icon = icon("arrow-right"))

# Partisi default: baris = fase 1-5, kolom = daun, batang, akar, buah
part0 <- rbind(c(.40,.35,.25,0), c(.40,.35,.25,0), c(.30,.30,.20,.20),
               c(.15,.20,.15,.50), c(.05,.10,.10,.75))
grid_partisi <- lapply(1:5, function(i) fluidRow(
  column(2, strong(paste("Fase", i))),
  lapply(1:4, function(j) column(2, numericInput(paste0("p",i,j), NULL, part0[i,j], step = .05)))))

# ---------- Helper model ----------
siapkan_data <- function(path, ext, header = TRUE, sep = ",") {
  d <- if (grepl("^xlsx?$", ext, ignore.case = TRUE)) as.data.frame(read_excel(path))
  else read.csv(path, header = header, sep = sep, check.names = FALSE)
  if (all(kol %in% names(d))) d <- d[, kol]
  else if (ncol(d) >= 7) { d <- d[, 2:7]; names(d) <- kol }
  else if (ncol(d) == 6) names(d) <- kol
  else stop("Data harus memiliki 6 kolom: tgl, suhu, rh, ch, Rs, angin (atau layout B:G).")
  d$tgl <- if (inherits(d$tgl, "POSIXt")) as.Date(d$tgl)
  else if (is.numeric(d$tgl)) as.Date(d$tgl, origin = "1899-12-30")
  else as.Date(as.character(d$tgl))
  for (nm in kol[-1]) d[[nm]] <- suppressWarnings(as.numeric(d[[nm]]))
  for (nm in c("suhu","rh","Rs","angin")) {         # imputasi: rerata valid
    d[[paste0(nm,"_diimputasi")]] <- is.na(d[[nm]])
    r <- mean(d[[nm]], na.rm = TRUE)
    if (!is.finite(r)) stop("Tidak ada nilai valid untuk ", nm)
    d[[nm]][is.na(d[[nm]])] <- r
  }
  d$CH_diimputasi <- is.na(d$ch); d$ch[is.na(d$ch)] <- 0   # CH NA -> 0
  if (anyNA(d$tgl) || anyDuplicated(d$tgl)) stop("Tanggal tidak valid atau duplikat.")
  d[order(d$tgl), , drop = FALSE]
}

simulasi_tomat <- function(P, data0, tgl_tanam, ps = 0, prh = 0, pch = 0) {
  list2env(P, environment())
  param <- P[setdiff(names(P), c("kc_fase","bobot_fase","partisi"))]
  kosong <- names(param)[!vapply(param, function(x) is.numeric(x) && length(x)==1 && is.finite(x), logical(1))]
  if (length(kosong)) stop("Isi parameter ini: ", paste(kosong, collapse = ", "))
  if (length(tgl_tanam)!=1 || is.na(tgl_tanam)) stop("Isi tanggal tanam.")
  if (anyNA(partisi) || any(partisi<0) || any(abs(rowSums(partisi)-1)>1e-9))
    stop("Partisi: semua >=0 dan jumlah tiap baris (fase) = 1.")
  if (length(kc_fase)!=4 || anyNA(kc_fase) || any(kc_fase<=0)) stop("Isi 4 nilai Kc positif.")
  if (anyNA(bobot_fase) || any(bobot_fase<0) || abs(sum(bobot_fase)-1)>1e-9)
    stop("Bobot indeks s harus 4 nilai, jumlahnya = 1.")
  if (any(c(tu1,tu2,tu3,tu4,tu5,k,sla,rue,Zr,U,alpha,reset_hujan)<=0) ||
      kg<0 || kg>=1 || km<0 || LAI_awal<=0 || wbatang_awal<0 || wakar_awal<0 ||
      TLP<0 || TLP>KATawal || KATawal>KL || KL>=1 || runoff_frac<0 || runoff_frac>=1 ||
      coef_Ic<0 || Lat< -90 || Lat>90 || Alt< -400 || Alt>=5000 ||
      tinggi_angin<=0.2 || tinggi_angin>=25)
    stop("Ada parameter di luar batas; cek satuan dan kondisi awal.")
  
  # Skenario perubahan iklim (parameter tambahan)
  ps <- ifelse(is.na(ps),0,ps); prh <- ifelse(is.na(prh),0,prh); pch <- ifelse(is.na(pch),0,pch)
  data0$suhu <- data0$suhu + ps
  data0$rh   <- pmin(100, pmax(0, data0$rh + prh))
  data0$ch   <- pmax(0, data0$ch + pch)
  data0 <- data0[data0$tgl >= tgl_tanam, , drop = FALSE]
  if (nrow(data0) < 2) stop("Data setelah tanggal tanam tidak mencukupi.")
  
  # Loop 1: perkembangan (satuan panas)
  tu <- c(tu1,tu2,tu3,tu4,tu5); batas <- c(0,cumsum(tu))
  TU_hari <- pmax(data0$suhu-tb,0); TU_kumul <- c(0,cumsum(TU_hari[-1]))
  idx_matang <- which(TU_kumul >= sum(tu))[1]
  if (is.na(idx_matang)) stop("Kemasakan belum tercapai: data cuaca kurang panjang atau nilai TU terlalu besar.")
  data <- data0[seq_len(idx_matang), , drop = FALSE]; TU_kumul <- TU_kumul[seq_len(idx_matang)]
  if (any(diff(as.numeric(data$tgl))!=1)) stop("Ada tanggal yang hilang pada musim simulasi.")
  if (any(data$ch<0 | data$rh<0 | data$rh>100 | data$Rs<0 | data$angin<0)) stop("Rentang cuaca tidak valid.")
  n <- nrow(data); HST <- seq_len(n)
  fase_idx <- pmin(4L, findInterval(TU_kumul, batas, rightmost.closed = TRUE))
  fase <- paste0("Fase-", fase_idx)
  awal_s <- c(0, cumsum(bobot_fase))
  prop_fase <- pmin(1, pmax(0, (TU_kumul-batas[fase_idx])/tu[fase_idx]))
  s <- awal_s[fase_idx] + bobot_fase[fase_idx]*prop_fase; s[n] <- 1
  ds <- c(0, diff(s))
  
  # Inisialisasi
  v <- function() numeric(n)
  Rs<-v(); ETo<-v(); kc<-v(); etc<-v(); em<-v(); tm<-v(); ea<-v(); ta<-v(); Rs[1] <- data$Rs[1]
  ic<-v(); ch_ef<-v(); ro<-v(); infiltrasi<-v(); pc<-v(); wdf<-v(); S<-v()
  Qint<-v(); dW<-v(); Ba<-v(); Rg<-v(); Rm<-v(); lai<-v()
  wdaun<-v(); wbatang<-v(); wakar<-v(); wbuah<-v(); wtot<-v(); residu_air<-v(); residu_biomassa<-v()
  lai[1] <- LAI_awal; wdaun[1] <- lai[1]*10000/sla
  wbatang[1] <- wbatang_awal; wakar[1] <- wakar_awal; wtot[1] <- wdaun[1]+wbatang[1]+wakar[1]
  S[1] <- KATawal*Zr; wdf[1] <- pmin(1, pmax(0,(KATawal-TLP)/(KL-TLP)))
  E1_kumul <- 0; hari_tahap2 <- 0L
  
  # Loop 2: radiasi/ETo, neraca air, biomassa
  for (i in 2:n) {
    T <- data$suhu[i]; RH <- data$rh[i]; CH <- data$ch[i]
    J <- as.integer(format(data$tgl[i], "%j"))
    dr <- 1+.033*cos(2*pi*J/365); delta <- .409*sin(2*pi*J/365-1.39); phi <- Lat*pi/180
    ws <- acos(pmax(-1, pmin(1, -tan(phi)*tan(delta))))
    Ra <- (24*60/pi)*.082*dr*(ws*sin(phi)*sin(delta)+cos(phi)*cos(delta)*sin(ws))
    Rs[i] <- data$Rs[i]; Rso <- (.75+2e-5*Alt)*Ra
    es <- .6108*exp(17.27*T/(T+237.3)); eakt <- RH/100*es
    Delta <- 4098*es/(T+237.3)^2
    Pat <- 101.3*((293-.0065*Alt)/293)^5.26; gamma <- .000665*Pat
    Rns <- .77*Rs[i]
    Rnl <- 4.903e-9*(T+273.16)^4*(.34-.14*sqrt(eakt))*pmax(0, 1.35*pmin(1,Rs[i]/Rso)-.35)
    Rn <- Rns-Rnl
    u2 <- data$angin[i]*4.87/log(67.8*tinggi_angin-5.42)
    ETo[i] <- max(0, (.408*Delta*Rn+gamma*(900/(T+273))*u2*(es-eakt))/(Delta+gamma*(1+.34*u2)))
    kc[i] <- kc_fase[fase_idx[i]]; etc[i] <- kc[i]*ETo[i]
    
    lailama <- lai[i-1]
    ic[i] <- min(CH, if (lailama<=3) coef_Ic*lailama else Ic_maks)
    ch_ef[i] <- CH-ic[i]; ro[i] <- runoff_frac*ch_ef[i]; infiltrasi[i] <- ch_ef[i]-ro[i]
    
    S_fc <- KL*Zr; S_wp <- TLP*Zr
    setelah_hujan <- S[i-1]+infiltrasi[i]
    pc[i] <- max(0, setelah_hujan-S_fc); tersedia <- setelah_hujan-pc[i]
    em[i] <- etc[i]*exp(-k*lailama); tm[i] <- max(0, etc[i]-em[i])
    if (infiltrasi[i] >= reset_hujan) { E1_kumul <- 0; hari_tahap2 <- 0L }
    if (E1_kumul < U) { Ea_pot <- em[i] } else {
      hari_tahap2 <- hari_tahap2+1L
      Ea_pot <- min(em[i], alpha*(sqrt(hari_tahap2)-sqrt(hari_tahap2-1)))
    }
    air_bisa_diambil <- max(0, tersedia-S_wp)
    ea[i] <- min(Ea_pot, air_bisa_diambil)
    if (E1_kumul < U) E1_kumul <- E1_kumul+ea[i]
    faktor_air <- pmin(1, pmax(0, air_bisa_diambil/(S_fc-S_wp)))
    ta[i] <- min(tm[i]*faktor_air, max(0, air_bisa_diambil-ea[i]))
    wdf[i] <- if (tm[i] > 1e-12) ta[i]/tm[i] else 1
    S[i] <- tersedia-ea[i]-ta[i]
    residu_air[i] <- S[i]-(S[i-1]+CH-ic[i]-ro[i]-pc[i]-ea[i]-ta[i])
    
    Qint[i] <- Rs[i]*(1-exp(-k*lailama)); dW[i] <- rue*Qint[i]
    Ba[i] <- dW[i]*wdf[i]; Rg[i] <- kg*Ba[i]; Bnet <- Ba[i]-Rg[i]
    Q10 <- 2^((T-20)/10)
    Wlama <- c(wdaun[i-1], wbatang[i-1], wakar[i-1], wbuah[i-1])
    alokasi <- Bnet*partisi[fase_idx[i], ]
    resp <- pmin(km*Q10*Wlama, Wlama+alokasi)
    baru <- Wlama+alokasi-resp
    wdaun[i]<-baru[1]; wbatang[i]<-baru[2]; wakar[i]<-baru[3]; wbuah[i]<-baru[4]
    Rm[i] <- sum(resp); wtot[i] <- sum(baru); lai[i] <- sla*wdaun[i]/10000
    residu_biomassa[i] <- (wtot[i]-wtot[i-1])-(Bnet-Rm[i])
  }
  
  h <- data.frame(Tanggal=data$tgl, HST=HST, Fase=fase, s=s, ds=ds,
                  Suhu=data$suhu, RH=data$rh, CH=data$ch, Radiasi=Rs, ETo=ETo, ETc=etc, Em=em, Ea=ea,
                  Tm=tm, Ta=ta, ETa=ea+ta, Intersepsi=ic, CH_ef=ch_ef, Runoff=ro, Infiltrasi=infiltrasi,
                  Perkolasi=pc, SimpananAir_mm=S, KAT=S/Zr, WDF=wdf, Qint=Qint, Bp=dW, Ba=Ba, Rg=Rg, Rm=Rm,
                  Daun=wdaun, Batang=wbatang, Akar=wakar, Buah=wbuah, Total=wtot, LAI=lai,
                  ProdBuah_tonBK_ha=0.01*wbuah, ProdDaun_tonBK_ha=0.01*wdaun, ProdBatang_tonBK_ha=0.01*wbatang,
                  ProdAkar_tonBK_ha=0.01*wakar, ProdTotal_tonBK_ha=0.01*wtot,
                  ResiduAir_mm=residu_air, ResiduBiomassa_gm2=residu_biomassa)
  if (any(!is.finite(h$LAI)) || max(abs(residu_air))>1e-7 || max(abs(residu_biomassa))>1e-7)
    stop("Pemeriksaan hasil gagal; cek input dan persamaan.")
  h$WUE_gL <- c(NA_real_, ifelse((ea+ta)[-1]>0.01, diff(wtot)/(ea+ta)[-1], NA_real_))
  h
}

plot_multi <- function(d, ys, judul, ylab) {
  p <- plot_ly()
  for (lb in names(ys)) p <- add_lines(p, x = d$HST, y = d[[ys[[lb]]]], name = lb)
  layout(p, title = judul, xaxis = list(title = "HST"), yaxis = list(title = ylab),
         legend = list(orientation = "h"))
}

# ---------- UI ----------
ui <- dashboardPage(skin = "blue",
                    dashboardHeader(title = "Model Simulasi Tomat"),
                    dashboardSidebar(sidebarMenu(id = "menuItems",
                                                 menuItem("Home", tabName = "home", icon = icon("home")),
                                                 menuItem("Data", tabName = "inputdata", icon = icon("database"),
                                                          menuSubItem("Data Iklim", tabName = "dataiklim", icon = icon("earth")),
                                                          menuSubItem("Parameter Tanaman", tabName = "partanaman", icon = icon("leaf")),
                                                          menuSubItem("Parameter Tanah & Air", tabName = "parneracaair", icon = icon("water")),
                                                          menuSubItem("Parameter Tambahan", tabName = "partambahan", icon = icon("thermometer")),
                                                          menuSubItem("Geografis", tabName = "geo", icon = icon("earth-americas")),
                                                          menuSubItem("Waktu Tanam", tabName = "waktutanam", icon = icon("calendar"))),
                                                 menuItem("Hasil", tabName = "hasil", icon = icon("square-poll-vertical"),
                                                          menuSubItem("Tabel Hasil Model", tabName = "tabelHST", icon = icon("table")),
                                                          menuSubItem("Grafik Produktivitas", tabName = "plotproduk", icon = icon("chart-line")),
                                                          menuSubItem("Grafik LAI", tabName = "plotLAI", icon = icon("chart-line")),
                                                          menuSubItem("Grafik Biomassa", tabName = "plotbiomassa", icon = icon("chart-line")),
                                                          menuSubItem("Grafik Kadar Air Tanah", tabName = "plotKAT", icon = icon("chart-column")),
                                                          menuSubItem("Grafik Evapotranspirasi", tabName = "plotevapotranspirasi", icon = icon("chart-column"))))),
                    dashboardBody(tabItems(
                      tabItem("home", fluidPage(
                        h3(HTML("Selamat datang di <b>Aplikasi Pemodelan Simulasi Tanaman Tomat!</b>")),
                        p(HTML("<p align='Justify'>Aplikasi ini membantu pengguna memahami dinamika pertumbuhan dan produktivitas tomat melalui simulasi berbasis data iklim yang interaktif.</p>")),
                        h4(HTML("<b>Tahukah Kamu!</b>")),
                        p(HTML("<p align='Justify'>Tomat (<i>Solanum lycopersicum</i> L.) adalah tanaman bernilai gizi tinggi yang tumbuh optimal pada suhu 20-28 °C, tanah gembur, dan curah hujan sedang (Azizah <i>et al.</i> 2025). Model simulasi tomat memprediksi pertumbuhan dan hasil panen berdasarkan faktor iklim dan lingkungan, sehingga membantu pengambilan keputusan budidaya yang lebih tepat. Simulasi pada aplikasi ini menggunakan data iklim Kabupaten Garut.</p>")),
                        p(HTML("<p align='Justify'>Fase pertumbuhan tomat terdiri dari persemaian, vegetatif, generatif, dan panen. Fase vegetatif ditandai peningkatan tinggi tanaman, jumlah daun, dan diameter batang. Fase generatif dimulai saat pembungaan pertama, ditandai jumlah bunga, jumlah buah, dan bobot buah (Hasanuddin dan Yuliana 2025).</p>")),
                        h4(HTML("<b>Mengapa Aplikasi Ini Penting?</b>")),
                        p(HTML("<p align='Justify'>Fitur utama: simulasi pertumbuhan tomat dari bibit berdaun hingga masak, visualisasi biomassa, LAI, produktivitas buah, serta neraca air tanah dan evapotranspirasi.</p>")),
                        p(HTML("<i>Selamat berselancar!</i>")), br(),
                        h5(HTML("<b>Referensi</b>")),
                        ref("Azizah S, Vauzia V, Chatri M, Putri ILE. 2025. Phenology of flowering time and flowering duration of tomato plants (<i>Solanum lycopersicum</i> L.) in Kamang Magek district and Padang City. <i>Jurnal Biologi Tropis</i>. 25(2):1721-1726."),
                        ref("Hasanuddin F, Yuliana Y. 2025. Pertumbuhan dan produksi tanaman tomat (<i>Solanum lycopersicum</i> L.) menggunakan kombinasi media tanam dan kompos kotoran kambing. <i>AGROVITAL</i>. 10(2):204-212"),
                        br(), h5(HTML("Salam dari kami, <b>Kelompok 4!</b>")),
                        tags$ul(
                          tags$li("G2401241011 - Ekane Susiana"),
                          tags$li("G2401241012 - Nurul Wardah"),
                          tags$li("G2401241020 - Muhammad Habib Ismail Ilham"),
                          tags$li("G2401241029 - Hanifah Quratu Aini Suwarno"),
                          tags$li("G2401241044 - Diva Khaerunnisa"),
                          tags$li("G2401241049 - Celine Alecia Tanasha"),
                          tags$li("G2401241060 - Puput Dwiyanti Nurhayadi"),
                          tags$li("G2401241063 - Kezia Regina"),
                          tags$li("G2401241070 - Arrafi Radityo Jatmiko"),
                          tags$li("G2401241074 - Annisa Eka Ardani")),
                        h3(HTML("</br><b>Terima Kasih</b>")), h5(HTML("<b>Dosen Pembimbing</b>")),
                        tags$ul(tags$li("Impron, M. Sc."), tags$li("Yon Sugiarto, M. Sc.")),
                        p(HTML("</br><b>©2026, <i>Project-Based Learning</i> (PBL) Model Simulasi Pertanian</b>")))),
                      
                      tabItem("dataiklim", fluidPage(titlePanel("Data Iklim"),
                                                     p("Kolom: tanggal, suhu (°C), RH (%), CH (mm), Rs (MJ/m2/hari), angin (m/s). Format Excel (layout B:G) atau CSV."),
                                                     fluidRow(
                                                       column(4, fileInput("datainput", "Input file Excel/CSV", accept = c(".xlsx",".xls",".csv"))),
                                                       column(2, checkboxInput("header", "Header (CSV)", TRUE)),
                                                       column(2, radioButtons("sep", "Separator (CSV)", c(Comma=",", Semicolon=";", Tab="\t"))),
                                                       column(2, radioButtons("disp", "Display", c(Head="head", All="all")))),
                                                     fluidRow(column(8, div(style = "overflow-x:auto;", tableOutput("tabeldata"))),
                                                              column(2, nxt("menujupartanaman"))))),
                      
                      tabItem("partanaman", fluidPage(titlePanel("Parameter Tanaman Tomat"),
                                                      fluidRow(
                                                        column(3, mk(list(c("k","k (koefisien pemadaman)",.67), c("sla","SLA (cm2/g)",203),
                                                                          c("rue","RUE (g/MJ radiasi global)",1.05), c("tb","Suhu dasar (°C)",10),
                                                                          c("kg","Koef. respirasi pertumbuhan",.7), c("km","Koef. respirasi pemeliharaan",.00042)))),
                                                        column(3, mk(list(c("tu1","TU fase 1",324), c("tu2","TU fase 2",250), c("tu3","TU fase 3",323),
                                                                          c("tu4","TU fase 4",298), c("tu5","TU fase 5",361)))),
                                                        column(3, mk(list(c("LAI_awal","LAI awal",1.2), c("wbatang_awal","Bobot batang awal (g BK/m2)",112.2),
                                                                          c("wakar_awal","Bobot akar awal (g BK/m2)",9.9))),
                                                               strong("Bobot indeks s per fase (jumlah = 1)"),
                                                               mk(list(c("bw1","Fase 1",.15), c("bw2","Fase 2",.25), c("bw3","Fase 3",.15), c("bw4","Fase 4",.45))))),
                                                      h4("Partisi biomassa per fase (urutan: daun, batang, akar, buah; jumlah tiap baris = 1)"),
                                                      fluidRow(column(2, ""), column(2, strong("Daun")), column(2, strong("Batang")),
                                                               column(2, strong("Akar")), column(2, strong("Buah"))),
                                                      grid_partisi, nxt("menujuparneracaair"))),
                      
                      tabItem("parneracaair", fluidPage(titlePanel("Parameter Tanah dan Neraca Air"),
                                                        fluidRow(
                                                          column(4, mk(list(c("KATawal","KAT awal (fraksi volume)",.13), c("KL","Kapasitas lapang KL (fraksi volume)",.343),
                                                                            c("TLP","Titik layu permanen TLP (fraksi volume)",.1108),
                                                                            c("Zr","Kedalaman akar efektif (mm)",700),
                                                                            c("runoff_frac","Fraksi limpasan (0-1)",.15)))),
                                                          column(4, mk(list(c("coef_Ic","Koefisien intersepsi",.2), c("Ic_maks","Intersepsi maks. (mm)",3),
                                                                            c("U","Ambang evaporasi Ritchie tahap 1 (mm)",8),
                                                                            c("alpha","Koef. Ritchie tahap 2 (mm/akar hari)",3.5),
                                                                            c("reset_hujan","Infiltrasi reset pengeringan (mm)",5)))),
                                                          column(4, strong("Kc per fase"),
                                                                 mk(list(c("kc1","Kc fase 1",.6), c("kc2","Kc fase 2",1.15), c("kc3","Kc fase 3",.7), c("kc4","Kc fase 4",.7))))),
                                                        nxt("menujupartambahan"))),
                      
                      tabItem("partambahan", fluidPage(titlePanel("Parameter Tambahan (Skenario Iklim)"),
                                                       p("Nilai ditambahkan ke data harian. Isi 0 untuk kondisi aktual."),
                                                       fluidRow(column(4, mk(list(c("psuhu","Peningkatan suhu udara (°C)",0),
                                                                                  c("prh","Peningkatan kelembaban relatif (%)",0),
                                                                                  c("pch","Peningkatan curah hujan (mm/hari)",0))))),
                                                       nxt("menujugeo"))),
                      
                      tabItem("geo", fluidPage(titlePanel("Kondisi Geografis"),
                                               fluidRow(column(4, mk(list(c("Alt","Ketinggian wilayah (m)",717), c("Lat","Latitude wilayah (°)",-7.3895),
                                                                          c("tinggi_angin","Tinggi pengukuran angin (m)",2))))),
                                               nxt("menujuwaktutanam"))),
                      
                      tabItem("waktutanam", fluidPage(titlePanel("Waktu Tanam"),
                                                      fluidRow(column(4, dateInput("mulaitanam", "Tanggal mulai simulasi (bibit berdaun)", value = as.Date("2015-01-01")),
                                                                      actionButton("tombolproses", "Run Model", icon = icon("rocket")))))),
                      
                      tabItem("tabelHST", fluidPage(titlePanel("Tabel Hasil Model Tanaman Tomat"),
                                                    verbatimTextOutput("ringkasan"),
                                                    downloadButton("unduh_xlsx", "Unduh Excel"), downloadButton("unduh_csv", "Unduh CSV"), br(), br(),
                                                    div(style = "height:450px;overflow:scroll;background:white;", tableOutput("tabelhasil")))),
                      tabItem("plotproduk", fluidPage(titlePanel("Grafik Produktivitas"), plotlyOutput("produktivitasplot"))),
                      tabItem("plotLAI", fluidPage(titlePanel("Grafik LAI"), plotlyOutput("LAIplot"))),
                      tabItem("plotbiomassa", fluidPage(titlePanel("Grafik Biomassa"), plotlyOutput("biomassaplot"))),
                      tabItem("plotKAT", fluidPage(titlePanel("Grafik Kadar Air Tanah"), plotlyOutput("KATplot"))),
                      tabItem("plotevapotranspirasi", fluidPage(titlePanel("Grafik Curah Hujan & Evapotranspirasi"),
                                                                fluidRow(box(width = 12, title = "Curah Hujan", status = "primary", solidHeader = TRUE, plotlyOutput("plotch", height = "300px"))),
                                                                fluidRow(box(width = 12, title = "Evapotranspirasi", status = "primary", solidHeader = TRUE, plotlyOutput("plotet", height = "300px")))))
                    )))

# ---------- Server ----------
server <- function(input, output, session) {
  dataset <- reactive({
    req(input$datainput)
    tryCatch(siapkan_data(input$datainput$datapath, tools::file_ext(input$datainput$name), input$header, input$sep),
             error = function(e) { showNotification(conditionMessage(e), type = "error", duration = NULL); NULL })
  })
  output$tabeldata <- renderTable({
    d <- dataset(); req(d)
    d <- d[, kol]; d$tgl <- as.character(d$tgl)
    if (input$disp == "head") head(d) else d
  })
  
  hasil <- eventReactive(input$tombolproses, {
    req(dataset())
    nm <- c("k","sla","rue","tb","tu1","tu2","tu3","tu4","tu5","kg","km","LAI_awal","wbatang_awal","wakar_awal",
            "KATawal","KL","TLP","Zr","runoff_frac","coef_Ic","Ic_maks","U","alpha","reset_hujan",
            "Lat","Alt","tinggi_angin")
    P <- setNames(lapply(nm, function(n) input[[n]]), nm)
    P$kc_fase <- sapply(1:4, function(j) input[[paste0("kc", j)]])
    P$bobot_fase <- sapply(1:4, function(j) input[[paste0("bw", j)]])
    P$partisi <- matrix(unlist(lapply(1:5, function(i) sapply(1:4, function(j) input[[paste0("p", i, j)]]))),
                        5, 4, byrow = TRUE, dimnames = list(paste0("Fase-", 1:5), c("daun","batang","akar","buah")))
    h <- tryCatch(simulasi_tomat(P, dataset(), input$mulaitanam, input$psuhu, input$prh, input$pch),
                  error = function(e) { showNotification(conditionMessage(e), type = "error", duration = NULL); NULL })
    if (!is.null(h)) updateTabItems(session, "menuItems", "tabelHST")
    h
  })
  
  ringkasan_df <- reactive({
    h <- hasil(); req(h)
    data.frame(Parameter = c("HST panen","Buah (ton BK/ha)","Daun (ton BK/ha)","Batang (ton BK/ha)",
                             "Akar (ton BK/ha)","Total (ton BK/ha)","LAI maksimum","Total CH (mm)","Total ETa (mm)"),
               Nilai = c(max(h$HST), tail(h$ProdBuah_tonBK_ha,1), tail(h$ProdDaun_tonBK_ha,1),
                         tail(h$ProdBatang_tonBK_ha,1), tail(h$ProdAkar_tonBK_ha,1), tail(h$ProdTotal_tonBK_ha,1),
                         max(h$LAI), sum(h$CH), sum(h$ETa)))
  })
  output$ringkasan <- renderText({
    r <- ringkasan_df()
    paste0(r$Parameter, ": ", round(r$Nilai, 3), collapse = "\n")
  })
  output$tabelhasil <- renderTable({ h <- hasil(); req(h); h$Tanggal <- as.character(h$Tanggal); h }, digits = 3)
  
  output$unduh_xlsx <- downloadHandler(
    filename = function() "hasil_simulasi_tomat.xlsx",
    content = function(file) write.xlsx(list(Hasil_Harian = hasil(), Ringkasan = ringkasan_df()), file))
  output$unduh_csv <- downloadHandler(
    filename = function() "hasil_harian.csv",
    content = function(file) write.csv(hasil(), file, row.names = FALSE))
  
  output$produktivitasplot <- renderPlotly({
    h <- hasil(); req(h)
    plot_multi(h, c(Buah="ProdBuah_tonBK_ha", Daun="ProdDaun_tonBK_ha", Batang="ProdBatang_tonBK_ha",
                    Akar="ProdAkar_tonBK_ha", Total="ProdTotal_tonBK_ha"),
               "Produktivitas Biomassa Kering Tomat", "Biomassa (ton BK/ha)")
  })
  output$LAIplot <- renderPlotly({ h <- hasil(); req(h)
  plot_multi(h, c(LAI="LAI"), "Leaf Area Index (LAI) Tanaman Tomat", "LAI") })
  output$biomassaplot <- renderPlotly({ h <- hasil(); req(h)
  plot_multi(h, c(Daun="Daun", Batang="Batang", Akar="Akar", Buah="Buah", Total="Total"),
             "Pertumbuhan Biomassa Tanaman Tomat", "Biomassa (g BK/m2)") })
  output$KATplot <- renderPlotly({
    h <- hasil(); req(h)
    plot_ly(h, x = ~Tanggal) %>%
      add_bars(y = ~CH, name = "CH (mm)", yaxis = "y2", marker = list(color = "skyblue")) %>%
      add_lines(y = ~KAT*100, name = "KAT (% vol)", line = list(color = "blue")) %>%
      layout(title = "Hubungan KAT dan Curah Hujan", yaxis = list(title = "KAT (% volume)"),
             yaxis2 = list(title = "Curah Hujan (mm)", overlaying = "y", side = "right", autorange = "reversed"),
             legend = list(orientation = "h"))
  })
  output$plotch <- renderPlotly({
    h <- hasil(); req(h)
    plot_ly(h, x = ~HST, y = ~CH, type = "bar", name = "CH") %>%
      layout(title = "Time Series Curah Hujan", xaxis = list(title = "HST"), yaxis = list(title = "Curah Hujan (mm)"))
  })
  output$plotet <- renderPlotly({ h <- hasil(); req(h)
  plot_multi(h, c(ETo="ETo", ETc="ETc", ETa="ETa"), "Time Series Evapotranspirasi", "mm/hari") })
  
  # Tombol Next
  alur <- list(menujupartanaman = "partanaman", menujuparneracaair = "parneracaair",
               menujupartambahan = "partambahan", menujugeo = "geo", menujuwaktutanam = "waktutanam")
  lapply(names(alur), function(b) observeEvent(input[[b]], updateTabItems(session, "menuItems", alur[[b]])))
}

shinyApp(ui, server)

