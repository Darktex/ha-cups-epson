ARG BUILD_FROM
FROM ${BUILD_FROM}

ARG ESCPR2_URL="https://github.com/hanxi/cups-web/releases/download/cups-driver/epson-inkjet-printer-escpr2_1.2.39-1_amd64.deb"

RUN set -eux; \
    curl -fsSL -o /tmp/escpr2.deb "${ESCPR2_URL}"; \
    dpkg -i /tmp/escpr2.deb || apt-get install -y --no-install-recommends -f; \
    rm -f /tmp/escpr2.deb; \
    test -x /opt/epson-inkjet-printer-escpr2/cups/lib/filter/epson-escpr2; \
    test -f /opt/epson-inkjet-printer-escpr2/ppds/Epson/Epson-ET-8550_Series-epson-inkjet-printer-escpr2.ppd.gz

# media-guard: wrap the ipp backend (and its http/https/ipps symlinks) to
# refuse jobs whose media size+type matches no tray registered on the printer
# panel — the ET-8550 firmware otherwise stalls for hours, then rescales the
# page and tiles it across multiple sheets. See media-guard.sh for details.
COPY media-guard.sh /tmp/media-guard.sh
RUN set -eux; \
    mv /usr/lib/cups/backend/ipp /usr/lib/cups/backend/ipp.real; \
    install -m 0755 -o root -g root /tmp/media-guard.sh /usr/lib/cups/backend/ipp; \
    rm /tmp/media-guard.sh

# mDNS: the add-on runs on the host network next to Home Assistant's own
# system-wide mDNS reflector (hassio_multicast). The base image's avahi is
# ALSO configured as a reflector, so the two echo each other's records: the
# add-on's avahi hears its own hostname come back with different data,
# declares a conflict and renames itself (-2, -3, ...). That breaks Bonjour
# "Add Printer" on macOS/iOS because the advertised host no longer matches
# the TLS certificate (valid for <hostname>.local only). Fix: be a plain
# responder (one reflector per host), confined to the LAN interface, IPv4.
ARG MDNS_INTERFACE=enp1s0
RUN set -eux; \
    f=/etc/avahi/avahi-daemon.conf; \
    sed -i \
        -e 's/^enable-reflector=.*/enable-reflector=no/' \
        -e 's/^use-ipv6=.*/use-ipv6=no/' \
        -e "s/^\[server\]/[server]\nallow-interfaces=${MDNS_INTERFACE}/" \
        "$f"; \
    grep -qE '^allow-interfaces=' "$f"; \
    grep -qE '^enable-reflector=no' "$f"
