# ==============================================================================
# CSS STİLLƏRİ — bütün modul UI-ları bu stili istifadə edir
# ==============================================================================

STIL <- "
:root {
  --grafit:#0e1620; --polad:#17222f; --xett:#2a3b4d;
  --yasil:#5bd08a; --kehreba:#f5a524; --qirmizi:#e5695f;
  --teal:#2dd4bf;  --mavi:#5aa9e6;   --boz:#64748b;
  --kagiz:#f6f4ef; --murekkeb:#1a222c;
}

/* BORU XƏTTİ */
.boru      { padding:18px 24px 10px; }
.boru-sira { display:flex; align-items:center; gap:0; flex-wrap:wrap; }
.merhele {
  display:flex; flex-direction:column; align-items:center;
  padding:10px 16px; border-radius:10px; min-width:110px;
  background:#fff; border:1px solid #e2ddd6; gap:3px;
}
.merhele.ok           { border-color:#5bd08a; background:#f0fdf4; }
.merhele.xeberdarliq  { border-color:#f5a524; background:#fffbeb; }
.merhele.kritik       { border-color:#e5695f; background:#fef2f2; }
.merhele.bilinmir     { border-color:#e2ddd6; }
.lampa {
  width:10px; height:10px; border-radius:50%; background:var(--boz);
}
.lampa.ok           { background:var(--yasil); box-shadow:0 0 6px #5bd08a88; }
.lampa.xeberdarliq  { background:var(--kehreba); }
.lampa.kritik       { background:var(--qirmizi); animation:yanir 1s infinite; }
@keyframes yanir {
  0%,100% { box-shadow:0 0 4px #e5695f; }
  50%      { box-shadow:0 0 12px #e5695f; }
}
.merhele .ad  { font-size:11px; font-weight:700; color:#374151; text-align:center; }
.merhele .req { font-size:22px; font-family:Oswald,sans-serif; font-weight:600; color:#0d9488; }
.merhele .et  { font-size:10px; color:#6b7280; text-align:center; }
.merhele .dt  { font-size:10px; color:#9ca3af; text-align:center; max-width:140px; line-height:1.3; }
.seqment {
  width:36px; height:3px; flex-shrink:0;
  position:relative; margin:0 4px;
  background:linear-gradient(90deg, #5bd08a 0%, #9ef5c4 50%, #5bd08a 100%);
  background-size:72px 100%;
  animation:axim 1.1s linear infinite;
  overflow:visible;
}
.seqment.dur {
  background:linear-gradient(90deg, #e5695f 0%, #f4a49e 50%, #e5695f 100%);
  background-size:72px 100%;
}
.seqment::after {
  content:''; position:absolute;
  right:-7px; top:50%; transform:translateY(-50%);
  width:0; height:0;
  border-top:5px solid transparent;
  border-bottom:5px solid transparent;
  border-left:7px solid #5bd08a;
}
.seqment.dur::after { border-left-color:#e5695f; }
@keyframes axim {
  from { background-position:0 0; }
  to   { background-position:72px 0; }
}

/* BAŞLIQ */
.zavod-bas {
  display:flex; justify-content:space-between; align-items:center;
  padding:14px 24px; background:#fff; border-bottom:1px solid #e2ddd6;
}
.zavod-bas h1 { font-size:20px; margin:0; font-weight:600; }
.zavod-bas .alt { font-size:12px; color:#6b7280; font-family:ui-monospace,monospace; }
.xal-qutu { text-align:right; }
.xal { font-size:32px; font-family:Oswald,sans-serif; font-weight:700; line-height:1; }
.xal-etiket { font-size:12px; color:#6b7280; }

/* PROBLEMLƏR */
.her-sey-yaxsi {
  text-align:center; padding:30px 20px;
  background:#f0fdf4; border-radius:10px; border:1px solid #bbf7d0;
}
.her-sey-yaxsi .b { font-size:20px; font-weight:700; color:#166534; }
.problem { padding:16px 18px; border-radius:8px; margin-bottom:12px; border-left:4px solid; }
.problem.kritik      { background:#fef2f2; border-color:#e5695f; }
.problem.xeberdarliq { background:#fffbeb; border-color:#f5a524; }
.problem.melumat     { background:#f0f9ff; border-color:#5aa9e6; }
.problem h4 { margin:0 0 6px; font-size:15px; display:flex; align-items:center; gap:8px; }
.problem .ne   { font-size:13.5px; color:#374151; margin-bottom:6px; }
.problem .niye { font-size:13px; color:#6b7280; margin-bottom:8px; }
.problem ol    { margin:0; padding-left:18px; font-size:13px; }
.rozet {
  font-size:11px; padding:2px 8px; border-radius:20px;
  font-weight:700; text-transform:uppercase;
}
.rozet.kritik      { background:#fee2e2; color:#991b1b; }
.rozet.xeberdarliq { background:#fef3c7; color:#92400e; }
.rozet.melumat     { background:#dbeafe; color:#1e40af; }

/* CİHAZ KARTLARI */
.cihaz {
  display:inline-flex; flex-direction:column; align-items:center;
  padding:14px 18px; margin:6px; border-radius:10px; min-width:130px;
  background:#fff; border:1px solid #e2ddd6;
}
.cihaz.susur { border-color:#f5a524; background:#fffbeb; }
.cihaz.xarab { border-color:#e5695f; background:#fef2f2; }
.cihaz .deyer { font-size:28px; font-family:Oswald,sans-serif; font-weight:600; color:#0d9488; }
.cihaz .vahid { font-size:14px; font-weight:400; color:#6b7280; }
.cihaz .kod   { font-size:11px; font-weight:700; color:#374151; }
.cihaz .tip   { font-size:11px; color:#9ca3af; text-align:center; }

/* CƏDVƏL */
.cdv-sar { overflow-x:auto; }
.cdv { width:100%; border-collapse:collapse; font-size:13px; }
.cdv th { padding:8px 12px; text-align:left; background:#f6f4ef; border-bottom:2px solid #e2ddd6; font-weight:600; }
.cdv td { padding:7px 12px; border-bottom:1px solid #f0ede7; }
.cdv tr:hover td { background:#fafaf8; }
.cdv tr.kritik td { background:#fef2f2; }
.cdv tr.xeber td  { background:#fffbeb; }

/* LOG */
.log-qutu {
  background:#0e1620; color:#e2e8f0;
  font-family:ui-monospace,Menlo,monospace; font-size:12px;
  padding:14px; border-radius:8px; overflow-y:auto; max-height:440px;
  white-space:pre-wrap; word-break:break-all;
}

/* AI */
.ai-sual { background:#f0f9ff; padding:10px 14px; border-radius:8px; margin-bottom:6px; font-size:13.5px; }
.ai-cavab { background:#fff; padding:12px 14px; border:1px solid #e2ddd6; border-radius:8px; font-size:13.5px; line-height:1.65; white-space:pre-wrap; }

/* İDARƏETMƏ */
.btn-idare { display:block; width:100%; margin-bottom:8px; text-align:left; }

/* SƏNƏD MODULUNUN STİLLƏRİ */
.sened-kart {
  background:#fff; border:1px solid #e2ddd6; border-radius:10px;
  padding:14px 16px; margin-bottom:10px;
  transition:border-color .15s;
}
.sened-kart:hover { border-color:#0d9488; cursor:pointer; }
.sened-kart .sened-nov  { font-size:11px; font-weight:700; color:#0d9488; text-transform:uppercase; }
.sened-kart .sened-nom  { font-size:15px; font-weight:600; margin:2px 0; }
.sened-kart .sened-trf  { font-size:13px; color:#6b7280; }
.sened-kart .sened-meta { font-size:11px; color:#9ca3af; margin-top:4px; }
.sened-status-qaralama     { color:#64748b; }
.sened-status-tesdiq_gozleyir { color:#f5a524; }
.sened-status-tesdiqlendi  { color:#5bd08a; }
.sened-status-redd_edildi  { color:#e5695f; }

/* AI TƏKLİFLƏR */
.ai-emlik-yuksek  { background:#f0fdf4 !important; }
.ai-emlik-orta    { background:#fffbeb !important; }
.ai-emlik-asagi   { background:#fef2f2 !important; }
.tesdig-panel {
  display:flex; gap:18px; align-items:flex-start;
}
.tesdig-sol { flex:0 0 50%; }
.tesdig-sag { flex:1; }

/* ANBAR */
.anbar-kart {
  padding:12px 16px; border-radius:8px; margin-bottom:8px;
  border:1px solid #e2ddd6; background:#fff;
}
.anbar-kart.asagi  { border-color:#e5695f; background:#fef2f2; }
.anbar-kart.normal { border-color:#5bd08a; background:#f0fdf4; }
.qaliq-reqem { font-size:24px; font-family:Oswald,sans-serif; font-weight:700; }
"
