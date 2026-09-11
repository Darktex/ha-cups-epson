#!/bin/bash
# Configure a Mac to print to the Epson ET-8550 through the Home Assistant
# CUPS add-on (media-guard). Idempotent; safe to re-run.
#   1. removes stale queues for this printer (old escpr2/dnssd bindings)
#   2. adds the queue over IPPS by its stable Bonjour hostname (waitjob=false)
#   3. defaults: Ultra Glossy, High quality, tray Auto (printer picks by paper)
#   4. installs the print-dialog presets (tools/setup-mac-presets.sh)
set -euo pipefail
QUEUE="EPSON_ET_8550_via_HomeAssistant"
DESC="EPSON ET-8550 via HomeAssistant"
INSTANCE="EPSON ET-8550 via HomeAssistant @ 97a3f4ca-cups-epson"
UUID="83654271-59cd-322a-4275-8a1da7585e98"
HOSTURI="ipps://97a3f4ca-cups-epson.local:631/printers/EPSON_ET-8550_HomeAssistant"

echo "== 1. removing stale queues for this printer"
for q in $(lpstat -v 2>/dev/null | awk -F'[ :]' '/EPSON.*8550|97a3f4ca|192.168.0.201/ {print $3}'); do
  cancel -a "$q" 2>/dev/null || true
  lpadmin -x "$q" && echo "   removed $q"
done

echo "== 2. adding $QUEUE (IPPS by stable hostname, IPP Everywhere)"
# waitjob=false: hand each job to the HA server and return immediately, so a whole
# batch spools on HA within seconds and the Mac can sleep (default: the Mac waits
# for each job to finish printing before transferring the next one).
lpadmin -p "$QUEUE" -E -v "${HOSTURI}?waitjob=false&waitprinter=false" -m everywhere -D "$DESC" -L "Home Assistant CUPS (media-guard on)"

echo "== 3. defaults: Ultra Glossy / High / tray Auto"
lpadmin -p "$QUEUE" -o MediaType=PhotographicHighGloss -o cupsPrintQuality=High -o InputSlot=Auto
# paper-out / offline: keep retrying instead of stopping the queue (macOS default stop-printer
# silently parks every following job until someone clicks Resume)
lpadmin -p "$QUEUE" -o printer-error-policy=retry-job
lpoptions -p "$QUEUE" -l | grep -E "InputSlot|MediaType|cupsPrintQuality" | grep -oE "^[^/]+|\*[^ ]+" | paste - - | sed 's/^/   /'

echo "== 4. presets (Foto 4x6 / 5x7 / Letter, Documento Letter)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$HERE" ] && [ -x "$HERE/setup-mac-presets.sh" ]; then
  "$HERE/setup-mac-presets.sh"
else
  curl -fsSL https://raw.githubusercontent.com/Darktex/ha-cups-epson/main/tools/setup-mac-presets.sh | bash
fi
killall cfprefsd 2>/dev/null || true
echo "== done. Queue '$QUEUE' -> $(lpstat -v "$QUEUE" | sed 's/.*: //')"
