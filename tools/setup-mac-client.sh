#!/bin/bash
# Configure a Mac to print to the Epson ET-8550 through the Home Assistant
# CUPS add-on (media-guard). Idempotent; safe to re-run.
#   1. removes stale queues for this printer (old escpr2/dnssd bindings)
#   2. adds the queue via Bonjour/IPPS exactly like System Settings does
#   3. defaults: Ultra Glossy, High quality, tray Auto (printer picks by paper)
#   4. rewrites/creates the "Foto 4x6" and "Foto 5x7" presets for the driverless PPD
set -euo pipefail
QUEUE="EPSON_ET_8550_via_HomeAssistant"
DESC="EPSON ET-8550 via HomeAssistant"
INSTANCE="EPSON ET-8550 via HomeAssistant @ 97a3f4ca-cups-epson"
UUID="83654271-59cd-322a-4275-8a1da7585e98"
DNSSD="dnssd://$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$INSTANCE")._ipps._tcp.local./?uuid=${UUID}"
FALLBACK="ipps://97a3f4ca-cups-epson.local:631/printers/EPSON_ET-8550_HomeAssistant"

echo "== 1. removing stale queues for this printer"
for q in $(lpstat -v 2>/dev/null | awk -F'[ :]' '/EPSON.*8550|97a3f4ca|192.168.0.201/ {print $3}'); do
  cancel -a "$q" 2>/dev/null || true
  lpadmin -x "$q" && echo "   removed $q"
done

echo "== 2. adding $QUEUE via Bonjour (IPPS, IPP Everywhere)"
if ! lpadmin -p "$QUEUE" -E -v "$DNSSD" -m everywhere -D "$DESC" -L "Home Assistant CUPS (media-guard on)" 2>/dev/null; then
  echo "   Bonjour resolve failed, binding by hostname instead"
  lpadmin -p "$QUEUE" -E -v "$FALLBACK" -m everywhere -D "$DESC" -L "Home Assistant CUPS (media-guard on)"
fi

echo "== 3. defaults: Ultra Glossy / High / tray Auto"
lpadmin -p "$QUEUE" -o MediaType=PhotographicHighGloss -o cupsPrintQuality=High -o InputSlot=Auto
lpoptions -p "$QUEUE" -l | grep -E "InputSlot|MediaType|cupsPrintQuality" | grep -oE "^[^/]+|\*[^ ]+" | paste - - | sed 's/^/   /'

echo "== 4. presets (Foto 4x6, Foto 5x7) for the driverless option names"
python3 - <<'PY'
import plistlib, os, copy, glob
G=os.path.expanduser("~/Library/Preferences/com.apple.print.custompresets.plist")
g=plistlib.load(open(G,"rb")) if os.path.exists(G) else {}
def paper(size_name, code, w, h):
    return {"paperInfo":{"com.apple.print.PaperInfo.PMCustomPaper":False,
        "com.apple.print.PaperInfo.PMPaperName":size_name,
        "com.apple.print.PaperInfo.PMUnadjustedPageRect":[0,0,h,w],
        "com.apple.print.PaperInfo.PMUnadjustedPaperRect":[0,0,h,w],
        "com.apple.print.PaperInfo.ppd.PMPaperName":code,
        "com.apple.print.ticket.APIVersion":"01.00",
        "com.apple.print.ticket.type":"com.apple.print.PaperInfoTicket",
        "PMPPDPaperCodeName":code,"PMPPDTranslationStringPaperName":size_name,"PMTiogaPaperName":code}}
def sub(size_name, code, w, h):
    return {"com.apple.print.PaperInfo.PMPaperName":size_name,
        "com.apple.print.PaperInfo.PMPPDPaperDimension":[0,0,w,h],
        "com.apple.print.PaperInfo.PMUnadjustedPageRect":[0,0,h,w],
        "com.apple.print.PaperInfo.PMUnadjustedPaperRect":[0,0,h,w],
        "com.apple.print.PaperInfo.ppd.PMPaperName":code,
        "com.apple.print.ticket.type":"com.apple.print.PaperInfoTicket",
        "PMPPDPaperCodeName":code,"PMPPDTranslationStringPaperName":size_name,"PMTiogaPaperName":code}
def preset(name, size_name, code, w, h, slot):
    return {"com.apple.print.preset.behavior":0,"com.apple.print.preset.id":name,
        "com.apple.print.preset.settings":{
            "com.apple.print.PageToPaperMappingAllowScalingUp":True,
            "com.apple.print.PageToPaperMappingMediaName":code,
            "com.apple.print.preset.displayName":size_name,
            "com.apple.print.preset.PaperInfo":paper(size_name,code,w,h),
            "com.apple.print.PrintSettings.PMDuplexing":1,
            "com.apple.print.subTicket.paper_info_ticket":sub(size_name,code,w,h),
            "Ink":"COLOR","InputSlot":slot,"MediaType":"PhotographicHighGloss","PaperInfoIsSuggested":False}}
g["Foto 4x6"]=preset("Foto 4x6","4 x 6 in (Borderless)","4x6.Borderless",288,432,"Auto")
g["Foto 5x7"]=preset("Foto 5x7","13 x 18 cm (5 x 7 in) (Borderless)","5x7.Borderless",360,504,"Auto")
g.pop("vendorDefaultSettings",None)
info=[i for i in g.get("com.apple.print.customPresetsInfo",[]) if i.get("PresetName") not in ("Foto 4x6","Foto 5x7")]
info+= [{"PresetBehavior":0,"PresetName":"Foto 4x6"},{"PresetBehavior":0,"PresetName":"Foto 5x7"}]
g["com.apple.print.customPresetsInfo"]=info
plistlib.dump(g,open(G,"wb"),fmt=plistlib.FMT_BINARY)
for f in glob.glob(os.path.expanduser("~/Library/Preferences/com.apple.print.custompresets.forprinter.EPSON_ET_8550*.plist")):
    os.remove(f)   # stale per-printer last-used settings (escpr2 codes)
print("   presets written: Foto 4x6, Foto 5x7")
PY
killall cfprefsd 2>/dev/null || true
echo "== done. Queue '$QUEUE' -> $(lpstat -v "$QUEUE" | sed 's/.*: //')"
