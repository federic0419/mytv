#!/usr/bin/env bash
set -e

# === CONFIGURAZIONE LISTA IPTV ===
M3U_URL="https://raw.githubusercontent.com/federic0419/mytv/main/channels.m3u"   # <<-- link fisso della tua lista
OUTDIR="/app/out"
TIMEOUT=10

# === CONFIGURAZIONE EMAIL ===
MAIL_TO="fede20022004@gmail.com"          # destinatario
MAIL_FROM="rinaldi.f.work@gmail.com"      # mittente (account Gmail usato)
MAIL_SUBJECT="Report IPTV M3U"

# SMTP tramite msmtp
SMTP_ACCOUNT="gmail"


# === PREPARAZIONE ===
mkdir -p "$OUTDIR"
M3U_PATH="$OUTDIR/lista.m3u"
REPORT="$OUTDIR/report.csv"
GOODM3U="$OUTDIR/working.m3u"

# scarica la lista fissa
curl -s -L "$M3U_URL" -o "$M3U_PATH"

echo "CheckedAt,ChannelName,Url,Reachable,StatusCode,Method" > "$REPORT"
echo "#EXTM3U" > "$GOODM3U"

current_extinf=""
while IFS= read -r line; do
    trim="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    if [[ "$trim" =~ ^#EXTINF ]]; then
        current_extinf="$trim"
        name="${trim##*,}"
    elif [[ "$trim" =~ ^https?:// ]]; then
        url="$trim"
        extinf="${current_extinf:-"#EXTINF:-1,$url"}"
        cname="${name:-$url}"
        current_extinf=""

        # Test HEAD
        code=$(curl -I -m $TIMEOUT -A "Mozilla/5.0" -s -o /dev/null -w "%{http_code}" "$url")
        if [[ "$code" =~ ^2|3 ]]; then
            ok="True"; method="HEAD"
        else
            # Fallback GET range
            code=$(curl --range 0-0 -m $TIMEOUT -A "Mozilla/5.0" -s -o /dev/null -w "%{http_code}" "$url")
            if [[ "$code" =~ ^2|3 ]]; then
                ok="True"; method="GET(range)"
            else
                ok="False"; method="Error"
                code=""
            fi
        fi

        ts=$(date +"%Y-%m-%d %H:%M:%S")
        echo "[$ok] $cname -> $url ($method)"

        # Aggiungi a CSV
        echo "$ts,\"$cname\",\"$url\",$ok,$code,$method" >> "$REPORT"

        # Se valido, aggiungi a M3U
        if [[ "$ok" == "True" ]]; then
            echo "$extinf" >> "$GOODM3U"
            echo "$url" >> "$GOODM3U"
        fi
    fi
done < "$M3U_PATH"

# === INVIA EMAIL CON REPORT VIA SMTP (msmtp) ===
if command -v msmtp >/dev/null 2>&1; then
    BOUNDARY="=====MULTIPART_BOUNDARY====="
    {
        echo "From: $MAIL_FROM"
        echo "To: $MAIL_TO"
        echo "Subject: $MAIL_SUBJECT"
        echo "MIME-Version: 1.0"
        echo "Content-Type: multipart/mixed; boundary=\"$BOUNDARY\""
        echo
        echo "--$BOUNDARY"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo
        echo "Controllo completato."
        echo "In allegato trovi il report CSV con l’esito del check."
        echo
        echo "--$BOUNDARY"
        echo "Content-Type: text/csv; name=\"report.csv\""
        echo "Content-Disposition: attachment; filename=\"report.csv\""
        echo "Content-Transfer-Encoding: base64"
        echo
        base64 "$REPORT"
        echo "--$BOUNDARY--"
    } | msmtp -a "$SMTP_ACCOUNT" "$MAIL_TO"
else
    echo "msmtp non disponibile, stampo report nel log:"
    cat "$REPORT"
fi
