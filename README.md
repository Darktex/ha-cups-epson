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
