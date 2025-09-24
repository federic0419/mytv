# Usa un'immagine leggera ma completa
FROM alpine:3.20

# Installa pacchetti necessari
RUN apk add --no-cache bash curl msmtp ca-certificates coreutils tzdata busybox-extras

# Imposta timezone (opzionale, es. Roma)
ENV TZ=Europe/Rome

# Crea directory di lavoro
WORKDIR /app

# Copia script e config
COPY check_m3u.sh /app/check_m3u.sh
COPY msmtprc /etc/msmtprc

# Rendi eseguibile lo script
RUN chmod +x /app/check_m3u.sh

# Variabile di ambiente per password SMTP (verrà settata su Render)
ENV SMTP_PASS=""

# Comando di default
CMD ["/app/check_m3u.sh"]
