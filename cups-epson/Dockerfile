ARG BUILD_FROM
FROM ${BUILD_FROM}

ARG ESCPR2_URL="https://github.com/hanxi/cups-web/releases/download/cups-driver/epson-inkjet-printer-escpr2_1.2.39-1_amd64.deb"

RUN set -eux; \
    curl -fsSL -o /tmp/escpr2.deb "${ESCPR2_URL}"; \
    dpkg -i /tmp/escpr2.deb || apt-get install -y --no-install-recommends -f; \
    rm -f /tmp/escpr2.deb; \
    test -x /opt/epson-inkjet-printer-escpr2/cups/lib/filter/epson-escpr2; \
    test -f /opt/epson-inkjet-printer-escpr2/ppds/Epson/Epson-ET-8550_Series-epson-inkjet-printer-escpr2.ppd.gz
