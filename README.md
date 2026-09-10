# Tex's HA Add-ons

A single Home Assistant add-on: a thin wrapper around [MaxWinterstein's CUPS add-on](https://github.com/MaxWinterstein/homeassistant-addons) that adds Epson's official `epson-inkjet-printer-escpr2` driver (covering the ET-8550 and other 2018+ Epson EcoTank / Expression photo printers, which the upstream Debian `printer-driver-escpr` package does not include).

## Install

1. In HA: Settings → Add-ons → Add-on Store → ⋮ → Repositories
2. Add: `https://github.com/Darktex/ha-cups-epson`
3. Install **CUPS (Epson ESC/P-R 2)** from the new section
4. Start it. CUPS UI: `http://<ha-ip>:631` (default login `print` / `print`)
5. When adding the printer, pick the model entry with **"Epson Inkjet Printer Driver (ESC/P-R) for Linux"** (this is what the escpr2 PPDs register as)

## What this adds vs upstream

A single Dockerfile layer that pulls the Epson `epson-inkjet-printer-escpr2_1.2.39-1_amd64.deb` (mirrored at `hanxi/cups-web` on GitHub, since Epson's own CDN refuses scripted downloads) and `dpkg -i`'s it. Installs to `/opt/epson-inkjet-printer-escpr2/`, where the PPDs reference the driver's own filter binaries — works without any other config.

## Notes

- amd64 only. The Epson driver mirror doesn't ship an aarch64 build.
- Pinned to upstream version `4.2.3.4`. Bump `build.yaml` and `config.yaml` together to track newer upstream releases.

## mDNS / Bonjour notes

The add-on's avahi is configured as a plain responder confined to the LAN
interface (`MDNS_INTERFACE` build arg, default `enp1s0`) with the reflector
disabled — Home Assistant's `hassio_multicast` is already the host's reflector,
and running two makes the add-on's hostname drift (`-2`, `-3`, …), which breaks
IPPS/Bonjour printer discovery on macOS/iOS because the advertised host stops
matching the TLS certificate. If your LAN interface has a different name, set
the build arg accordingly.

The CUPS `ServerName` must match the mDNS host the share is advertised under
(`<container-hostname>.local`, i.e. `97a3f4ca-cups-epson.local` for this
install) so the TLS certificate cupsd presents on IPPS validates for Bonjour
clients. It is runtime server config (persisted in `/data/cups/cupsd.conf`):

    ServerName 97a3f4ca-cups-epson.local

CUPS 2.3 selects its TLS credential file by the hostname it derives from the
reverse DNS of its own address (here `homeassistant.botany`), not by
`ServerName`. The server therefore carries one self-signed certificate whose
SANs cover every name it is reachable by, installed under each of those
filenames in `/data/cups/ssl/`. To (re)generate it:

    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
      -subj "/CN=97a3f4ca-cups-epson.local/O=Home Assistant CUPS" \
      -addext "subjectAltName=DNS:97a3f4ca-cups-epson.local,DNS:97a3f4ca-cups-epson,DNS:homeassistant.botany,DNS:homeassistant.local,DNS:homeassistant,DNS:localhost,IP:192.168.0.201,IP:127.0.0.1" \
      -addext "extendedKeyUsage=serverAuth" -keyout cups-server.key -out cups-server.crt

then copy `cups-server.crt`/`.key` to `/data/cups/ssl/<name>.crt`/`.key` for
each SAN name and restart the add-on.
