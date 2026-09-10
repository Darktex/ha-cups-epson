#!/bin/bash
# Install the macOS print-dialog presets for the ET-8550 via the HA CUPS queue.
# Each preset pins paper size + paper type + quality together so a preset can
# never produce a tray mismatch (which the add-on's media-guard would refuse).
# Idempotent: presets with these names are replaced, others are left alone.
set -euo pipefail
python3 - <<'PY'
import plistlib, os, glob

G = os.path.expanduser("~/Library/Preferences/com.apple.print.custompresets.plist")
g = plistlib.load(open(G, "rb")) if os.path.exists(G) else {}

# name, paper display name, PPD PageSize code, width pt, height pt, borderless, MediaType, quality
PRESETS = [
    ("Foto 4x6",                  "4 x 6 in (Borderless)",             "4x6.Borderless",    288, 432, True,  "PhotographicHighGloss", "High"),
    ("Foto 4x6 (con bordo)",      "4 x 6 in",                          "4x6",               288, 432, False, "PhotographicHighGloss", "High"),
    ("Foto 5x7",                  "13 x 18 cm (5 x 7 in) (Borderless)","5x7.Borderless",    360, 504, True,  "PhotographicHighGloss", "High"),
    ("Foto 5x7 (con bordo)",      "13 x 18 cm (5 x 7 in)",             "5x7",               360, 504, False, "PhotographicHighGloss", "High"),
    ("Foto Letter",               "US Letter",                         "Letter",            612, 792, False, "PhotographicHighGloss", "High"),
    ("Foto Letter (senza bordo)", "US Letter (Borderless)",            "Letter.Borderless", 612, 792, True,  "PhotographicHighGloss", "High"),
    ("Documento Letter",          "US Letter",                         "Letter",            612, 792, False, "Stationery",            "Normal"),
]
MARGIN = 8.5  # pt, = 3 mm hardware margin for bordered sizes

def paper_ticket(size_name, code, w, h, borderless):
    m = 0 if borderless else MARGIN
    page = [m, m, h - m, w - m]          # PMRect: top, left, bottom, right
    paper = [0, 0, h, w]
    return {"paperInfo": {
        "com.apple.print.PaperInfo.PMCustomPaper": False,
        "com.apple.print.PaperInfo.PMPaperName": size_name,
        "com.apple.print.PaperInfo.PMUnadjustedPageRect": page,
        "com.apple.print.PaperInfo.PMUnadjustedPaperRect": paper,
        "com.apple.print.PaperInfo.ppd.PMPaperName": code,
        "com.apple.print.ticket.APIVersion": "01.00",
        "com.apple.print.ticket.type": "com.apple.print.PaperInfoTicket",
        "PMPPDPaperCodeName": code,
        "PMPPDTranslationStringPaperName": size_name,
        "PMTiogaPaperName": code}}

def sub_ticket(size_name, code, w, h, borderless):
    m = 0 if borderless else MARGIN
    return {
        "com.apple.print.PaperInfo.PMPaperName": size_name,
        "com.apple.print.PaperInfo.PMPPDPaperDimension": [0, 0, w, h],
        "com.apple.print.PaperInfo.PMUnadjustedPageRect": [m, m, h - m, w - m],
        "com.apple.print.PaperInfo.PMUnadjustedPaperRect": [0, 0, h, w],
        "com.apple.print.PaperInfo.ppd.PMPaperName": code,
        "com.apple.print.ticket.type": "com.apple.print.PaperInfoTicket",
        "PMPPDPaperCodeName": code,
        "PMPPDTranslationStringPaperName": size_name,
        "PMTiogaPaperName": code}

def preset(name, size_name, code, w, h, borderless, media, quality):
    return {"com.apple.print.preset.behavior": 0, "com.apple.print.preset.id": name,
            "com.apple.print.preset.settings": {
                "com.apple.print.PageToPaperMappingAllowScalingUp": True,
                "com.apple.print.PageToPaperMappingMediaName": code,
                "com.apple.print.preset.displayName": size_name,
                "com.apple.print.preset.PaperInfo": paper_ticket(size_name, code, w, h, borderless),
                "com.apple.print.PrintSettings.PMDuplexing": 1,
                "com.apple.print.subTicket.paper_info_ticket": sub_ticket(size_name, code, w, h, borderless),
                "Ink": "COLOR", "Duplex": "None",
                "InputSlot": "Auto", "MediaType": media, "cupsPrintQuality": quality,
                "PaperInfoIsSuggested": False}}

names = [p[0] for p in PRESETS]
for p in PRESETS:
    g[p[0]] = preset(*p)
g.pop("vendorDefaultSettings", None)                      # stale escpr2-era vendor defaults
lus = g.get("Last Used Settings", {}).get("com.apple.print.preset.settings", {})
for k in ("MediaType", "InputSlot", "cupsPrintQuality"):   # let queue defaults apply until a preset is chosen
    lus.pop(k, None)
info = [i for i in g.get("com.apple.print.customPresetsInfo", []) if i.get("PresetName") not in names]
info += [{"PresetBehavior": 0, "PresetName": n} for n in names]
g["com.apple.print.customPresetsInfo"] = info
plistlib.dump(g, open(G, "wb"), fmt=plistlib.FMT_BINARY)
for f in glob.glob(os.path.expanduser("~/Library/Preferences/com.apple.print.custompresets.forprinter.EPSON_ET_8550*.plist")):
    os.remove(f)                                          # per-printer last-used settings with old option codes
print("presets installed:", ", ".join(names))
PY
killall cfprefsd 2>/dev/null || true
echo "done — presets appear the next time a print dialog is opened."
