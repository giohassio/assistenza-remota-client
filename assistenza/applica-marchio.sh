#!/usr/bin/env bash
# Applica un marchio ai sorgenti di RustDesk prima della compilazione:
# server, chiave e console scritti dentro il programma, logo e icone.
# Uso: bash assistenza/applica-marchio.sh <marchio>   (cartella in assistenza/marchi)
# Lo lancia la CI subito dopo il checkout; in locale lascia i file modificati.
set -euo pipefail

MARCHIO=${1:?"uso: applica-marchio.sh <marchio>"}
QUI=$(cd "$(dirname "$0")" && pwd)
M="$QUI/marchi/$MARCHIO"
[ -f "$M/marchio.conf" ] || { echo "marchio sconosciuto: $MARCHIO"; exit 1; }
# shellcheck disable=SC1091
. "$QUI/server.conf"
# shellcheck disable=SC1090
. "$M/marchio.conf"
cd "$(dirname "$QUI")"

# --- server e chiave (in hbb_common da RustDesk 1.5 non si passano più per variabile d'ambiente)
perl -pi -e "s|&\[\"rs-ny\.rustdesk\.com\"\]|&[\"$HOST\"]|; s|^pub const RS_PUB_KEY: &str = \"[^\"]*\";|pub const RS_PUB_KEY: &str = \"$KEY\";|" \
  libs/hbb_common/src/config.rs
# --- console: è l'API usata quando nelle impostazioni non c'è un server personalizzato
perl -pi -e "s|\"https://admin\.rustdesk\.com\"\.to_owned\(\)|\"$API\".to_owned()|" src/common.rs

grep -q "\"$HOST\"" libs/hbb_common/src/config.rs || { echo "server non applicato"; exit 1; }
grep -q "\"$KEY\"" libs/hbb_common/src/config.rs || { echo "chiave non applicata"; exit 1; }
grep -q "\"$API\".to_owned()" src/common.rs || { echo "console non applicata"; exit 1; }

# --- niente token verso il server ID: con un utente collegato il client chiede uno scambio
#     di chiavi che hbbs open source non fa ("Failed to secure tcp: deadline has elapsed").
#     Rubrica e storico passano dalla console in HTTPS, non da questa connessione.
perl -pi -e 's|^(\s*)let token = LocalConfig::get_option\("access_token"\);|${1}let token = String::new(); // assistenza: niente token al server ID|' \
  src/ui_session_interface.rs
grep -q 'let token = String::new(); // assistenza' src/ui_session_interface.rs || { echo "token non tolto"; exit 1; }
# --- sempre via relay: la via diretta attraverso le reti mobili si apre e cade dopo ~40 s (errore 10054)
perl -pi -e 's|config::option2bool\("force-always-relay", &self\.get_option\("force-always-relay"\)\)|true /* assistenza: sempre relay */|' \
  src/client.rs
grep -q 'true /\* assistenza: sempre relay \*/' src/client.rs || { echo "relay non forzato"; exit 1; }

# --- grafica: logo nella finestra (max 300x60) e icone
I="$M/icone"
cp "$M/logo.png" flutter/assets/logo.png
cp "$I/icona-256.png" flutter/assets/icon.png
cp "$I/icona-1024.png" res/icon.png
cp "$I/icona-1024.png" res/mac-icon.png
cp "$I/icona-32.png" res/32x32.png
cp "$I/icona-64.png" res/64x64.png
cp "$I/icona-128.png" res/128x128.png
cp "$I/icona-256.png" res/128x128@2x.png
cp "$I/icona.ico" res/icon.ico
cp "$I/icona.ico" flutter/windows/runner/resources/app_icon.ico

# --- icona del Mac (.icns): iconutil esiste solo su macOS
if command -v iconutil >/dev/null; then
  SET=$(mktemp -d)/AppIcon.iconset
  mkdir -p "$SET"
  for l in 16 32 128 256 512; do
    cp "$I/icona-$l.png" "$SET/icon_${l}x${l}.png"
    cp "$I/icona-$((l * 2)).png" "$SET/icon_${l}x${l}@2x.png"
  done
  iconutil -c icns -o flutter/macos/Runner/AppIcon.icns "$SET"
fi

echo "marchio $MARCHIO applicato: $NOME, server $HOST"
