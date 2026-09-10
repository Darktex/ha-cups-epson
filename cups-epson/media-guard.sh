#!/bin/bash
# media-guard: wrapper around the CUPS `ipp` backend (also reached via the
# http/https/ipps symlinks).
#
# WHY: the Epson ET-8550 does not error on print jobs whose (media size, media
# type) pair matches no paper registration on the printer's panel. Instead the
# firmware silently holds the job for 30-130 minutes, then rescales the single
# page ~2-3x and tiles it across 2-3 sheets (while reporting one successful
# impression). Root-caused 2026-07-09/11. The only safe behavior is to refuse
# mismatched jobs up front, before any data reaches the printer.
#
# Behavior: compares the job's requested media size + media type against the
# printer's live media-col-ready. Exact match (size within 0.5 mm, identical
# IPP media-type keyword) -> hand off to the real backend. No match -> cancel
# the job (exit 5 = CUPS_BACKEND_CANCEL) with an ERROR naming what IS
# registered. Fails OPEN (passes through) if anything is unparseable or the
# printer can't be queried, so the guard can never brick normal printing.
#
# SECOND RULE (2026-09-09): printer-side scaling is always disabled. The host
# pipeline (cups-filters pdftopdf) already applies the job's print-scaling, so
# forwarding it to the printer is redundant — and on the ET-8550 any value
# other than 'none' engages the firmware scaler, which accepts data at a few
# bytes per minute (paper advancing one band per minute) and, in July 2026,
# produced the 2-3x magnified, tiled output. The guard rewrites print-scaling
# to 'none' (or adds it) before handing the job to the real backend.
#
# Bypass:  touch /etc/cups/no_media_guard   (persistent)
#          touch /tmp/no_media_guard        (until addon restart)
# Dry run: MEDIA_GUARD_DRYRUN=1 <this script> <argv...>  (prints verdict; no
#          data is sent and the real backend is never invoked)
# NOTE: runs as user `lp` (0755 backend), so the flag cannot live in /config.

REAL=/usr/lib/cups/backend/ipp.real
ATTRTEST=/usr/share/cups/ipptool/get-printer-attributes.test

ARGS=("$@")

run_real() {
    if [ -n "$MEDIA_GUARD_DRYRUN" ]; then
        echo "DRYRUN PASS: $1"
        exit 0
    fi
    exec "$REAL" "${ARGS[@]}"
}

# Discovery mode (no args) or malformed invocation: not a job, pass through.
[ ${#ARGS[@]} -lt 5 ] && run_real "not a job invocation"
for BYPASS in /etc/cups/no_media_guard /tmp/no_media_guard; do
    [ -e "$BYPASS" ] && run_real "bypass file $BYPASS present"
done

OPTS="${ARGS[4]}"
PPDFILE="/etc/cups/ppd/${PRINTER}.ppd"

# ---- requested media type -> IPP keyword ------------------------------------
# Prefer an explicit IPP keyword (media-type=..., also found inside media-col),
# then the PPD-style choice (MediaType=CamelCase), then the PPD default.
ppd_choice_to_keyword() {
    sed -e 's/\([A-Z]\)/-\l\1/g' -e 's/^-//' <<<"$1"
}

REQ_TYPE=$(grep -oE '(^| )media-type=[^ }]+' <<<"$OPTS" | head -1 | cut -d= -f2)
if [ -z "$REQ_TYPE" ]; then
    CHOICE=$(grep -oE '(^| )MediaType=[^ ]+' <<<"$OPTS" | head -1 | cut -d= -f2)
    [ -z "$CHOICE" ] && [ -r "$PPDFILE" ] && \
        CHOICE=$(sed -n 's/^\*DefaultMediaType: *//p' "$PPDFILE" | tr -d '\r')
    [ -n "$CHOICE" ] && REQ_TYPE=$(ppd_choice_to_keyword "$CHOICE")
fi

# ---- requested media size -> 1/100 mm ---------------------------------------
# From a PWG self-describing name (na_letter_8.5x11in), from x-/y-dimension in
# a media-col string, or from the PPD PaperDimension of a PageSize choice.
REQ_X=""; REQ_Y=""
pts_to_100mm() { awk -v p="$1" 'BEGIN{printf "%d", p*2540/72+0.5}'; }

ppd_size_lookup() {
    local name="$1" dims
    [ -r "$PPDFILE" ] || return
    dims=$(grep -m1 "^\*PaperDimension ${name}:" "$PPDFILE" | grep -oE '"[0-9. ]+"' | tr -d '"')
    if [ -n "$dims" ]; then
        REQ_X=$(pts_to_100mm "${dims%% *}")
        REQ_Y=$(pts_to_100mm "${dims##* }")
    fi
}

MEDIA_NAME=$(grep -oE '(^| )media=[^ ]+' <<<"$OPTS" | head -1 | cut -d= -f2)
if [ -n "$MEDIA_NAME" ]; then
    SEG=${MEDIA_NAME##*_}
    if [[ $SEG =~ ^([0-9.]+)x([0-9.]+)(in|mm)$ ]]; then
        W=${BASH_REMATCH[1]}; H=${BASH_REMATCH[2]}; U=${BASH_REMATCH[3]}
        if [ "$U" = in ]; then
            REQ_X=$(awk -v v="$W" 'BEGIN{printf "%d", v*2540+0.5}')
            REQ_Y=$(awk -v v="$H" 'BEGIN{printf "%d", v*2540+0.5}')
        else
            REQ_X=$(awk -v v="$W" 'BEGIN{printf "%d", v*100+0.5}')
            REQ_Y=$(awk -v v="$H" 'BEGIN{printf "%d", v*100+0.5}')
        fi
    else
        ppd_size_lookup "$MEDIA_NAME"
    fi
fi
if [ -z "$REQ_X" ]; then
    # media-col carries explicit dimensions
    REQ_X=$(grep -oE 'x-dimension=[0-9]+' <<<"$OPTS" | head -1 | cut -d= -f2)
    REQ_Y=$(grep -oE 'y-dimension=[0-9]+' <<<"$OPTS" | head -1 | cut -d= -f2)
fi
if [ -z "$REQ_X" ] && [ -r "$PPDFILE" ]; then
    DEFSIZE=$(sed -n 's/^\*DefaultPageSize: *//p' "$PPDFILE" | tr -d '\r')
    [ -n "$DEFSIZE" ] && ppd_size_lookup "$DEFSIZE"
fi

if [ -z "$REQ_X" ] || [ -z "$REQ_Y" ] || [ -z "$REQ_TYPE" ]; then
    echo "WARNING: [media-guard] could not determine job media (size='$REQ_X x $REQ_Y' type='$REQ_TYPE'); letting job through unchecked" >&2
    run_real "unparseable job media"
fi

# ---- live tray registrations from the printer -------------------------------
READY=$(ipptool -T 10 -tv "$DEVICE_URI" "$ATTRTEST" 2>/dev/null | grep -m1 'media-col-ready')
if [ -z "$READY" ]; then
    echo "WARNING: [media-guard] could not query media-col-ready from $DEVICE_URI; letting job through unchecked" >&2
    run_real "printer not queryable"
fi

hundredths_to_in() { awk -v v="$1" 'BEGIN{printf "%.4g", v/2540}'; }

MATCHED=0
REGISTERED=""
while read -r ENTRY; do
    EX=$(grep -oE 'x-dimension=[0-9]+' <<<"$ENTRY" | head -1 | cut -d= -f2)
    EY=$(grep -oE 'y-dimension=[0-9]+' <<<"$ENTRY" | head -1 | cut -d= -f2)
    ET=$(grep -oE 'media-type=[^ }]+' <<<"$ENTRY" | head -1 | cut -d= -f2)
    ES=$(grep -oE 'media-source=[^ }]+' <<<"$ENTRY" | head -1 | cut -d= -f2)
    [ -z "$EX" ] || [ -z "$EY" ] || [ -z "$ET" ] && continue
    DESC="${ES:-?}=$(hundredths_to_in "$EX")x$(hundredths_to_in "$EY")in/${ET}"
    case "$REGISTERED" in *"$DESC"*) ;; *) REGISTERED="${REGISTERED:+$REGISTERED, }$DESC" ;; esac
    DX=$((REQ_X - EX)); DX=${DX#-}
    DY=$((REQ_Y - EY)); DY=${DY#-}
    if [ "$DX" -le 50 ] && [ "$DY" -le 50 ] && [ "$ET" = "$REQ_TYPE" ]; then
        MATCHED=1
    fi
done < <(tr '{' '\n' <<<"$READY" | grep 'x-dimension')

if [ "$MATCHED" = 1 ]; then
    # Normalize print-scaling for the printer: host-side scaling is already
    # applied; the ET-8550 firmware scaler must not be engaged.
    PS=$(grep -oE '(^| )print-scaling=[^ ]+' <<<"$OPTS" | head -1 | cut -d= -f2)
    if [ -z "$PS" ]; then
        OPTS="$OPTS print-scaling=none"
        echo "INFO: [media-guard] print-scaling absent -> none (scaling is done host-side; ET-8550 firmware scaler stalls)" >&2
    elif [ "$PS" != none ]; then
        OPTS=$(sed -E 's/(^| )print-scaling=[^ ]+/\1print-scaling=none/' <<<"$OPTS")
        echo "INFO: [media-guard] print-scaling=$PS -> none (scaling is done host-side; ET-8550 firmware scaler stalls)" >&2
    fi
    ARGS[4]="$OPTS"
    [ -n "$MEDIA_GUARD_DRYRUN" ] && echo "DRYRUN effective options: ${ARGS[4]}"
    run_real "media matches registered tray"
fi

MSG="[media-guard] REFUSING job: requested $(hundredths_to_in "$REQ_X")x$(hundredths_to_in "$REQ_Y")in type '$REQ_TYPE' matches NO tray registered on the printer panel (registered: ${REGISTERED:-none}). On the ET-8550 this mismatch causes an hours-long silent hold and the page being rescaled and tiled across sheets. Fix the printer LCD paper registration or the job's PageSize/MediaType. Emergency bypass: touch /etc/cups/no_media_guard in the addon container"
echo "ERROR: $MSG" >&2
if [ -n "$MEDIA_GUARD_DRYRUN" ]; then
    echo "DRYRUN FAIL (would cancel job)"
fi
exit 5  # CUPS_BACKEND_CANCEL
