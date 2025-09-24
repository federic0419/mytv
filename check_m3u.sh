#!/usr/bin/env bash
set -e

# === CONFIGURAZIONE LISTA IPTV ===
M3U_URL="https://raw.githubusercontent.com/federic0419/mytv/main/channels.m3u"   # lista fissa
OUTDIR="."
TIMEOUT=10

# === CONFIGURAZIONE EMAIL ===
MAIL_TO="fede20022004@gmail.com"          # destinatario
MAIL_FROM="rinaldi.f.work@gmail.com"      # mittente (account Gmail usato)
MAIL_SUBJECT="Report IPTV M3U"
SMTP_ACCOUNT="gmail"                      # account configurato in msmtprc

# === PREPARAZIONE ===
mkdir -p "$OUTDIR"
M3U_PATH="$OUTDIR/lista.m3u"
REPORT="$OUTDIR/report.csv"
GOODM3U="$OUTDIR/working.m3u"

# scarica la lista
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
        code=$(curl -I -m $TIMEOUT -A "Mozilla/5.0" -s -o /dev/null -w "%{http_code}" "$url" || true)
        if [[ "$code" =~ ^2|3 ]]; then
            ok="True"; method="HEAD"
        else
            # Fallback GET range
            code=$(curl --range 0-0 -m $TIMEOUT -A "Mozilla/5.0" -s -o /dev/null -w "%{http_code}" "$url" || true)
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

# === PREPARA LISTA FALLIMENTI ===
FAILED="$OUTDIR/failed.txt"
grep 'False' "$REPORT" > "$FAILED" || true

# === INVIA EMAIL (solo testo, no allegati) ===
if command -v msmtp >/dev/null 2>&1; then
    {
        echo "From: $MAIL_FROM"
        echo "To: $MAIL_TO"
        echo "Subject: $MAIL_SUBJECT"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo
        if [[ -s "$FAILED" ]]; then
            echo "❌ Canali NON raggiungibili:"
            echo
            awk -F',' '{print "- " $2 " -> " $3}' "$FAILED"
        else
            echo "✅ Tutti i canali risultano OK"
        fi
    } | msmtp -a "$SMTP_ACCOUNT" "$MAIL_TO"
else
    echo "msmtp non disponibile, stampo fallimenti nel log:"
    if [[ -s "$FAILED" ]]; then
        awk -F',' '{print "- " $2 " -> " $3}' "$FAILED"
    else
        echo "✅ Tutti i canali risultano OK"
    fi
fi
