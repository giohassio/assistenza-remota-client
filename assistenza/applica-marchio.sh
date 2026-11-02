#!/usr/bin/env bash
# Applica un marchio ai sorgenti di RustDesk prima della compilazione:
# server, chiave e console scritti dentro il programma, logo e icone.
# Uso: bash assistenza/applica-marchio.sh <marchio> [windows]   (cartella in assistenza/marchi)
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
# --- rubrica sincronizzata con le sessioni recenti già di default: ogni PC a cui ci si collega
#     entra nella rubrica del tecnico (ID, nome del PC, utente). Spegnerla salva "N", non "".
perl -pi -e "s|return bind\.mainGetLocalOption\(key: syncAbOption\) == 'Y';|return bind.mainGetLocalOption(key: syncAbOption) != 'N'; // assistenza: acceso di default|; s|key: syncAbOption, value: v \? 'Y' : defaultOptionNo\)|key: syncAbOption, value: v ? 'Y' : 'N')|" \
  flutter/lib/models/ab_model.dart
grep -q "!= 'N'; // assistenza: acceso di default" flutter/lib/models/ab_model.dart || { echo "rubrica dai recenti non accesa"; exit 1; }
grep -q "key: syncAbOption, value: v ? 'Y' : 'N')" flutter/lib/models/ab_model.dart || { echo "spegnimento rubrica dai recenti non applicato"; exit 1; }

# --- nome del programma: decide servizio, cartella, eseguibile e titolo.
#     Windows e Android: NOME_APP. Mac: NOME_APP_MAC (pacchetto <nome>.app al posto di RustDesk.app).
#     RustDesk ammette solo [A-Za-z0-9-] nel nome (validate_install_app_name).
SISTEMA=${2:-mac}
if [ "$SISTEMA" = "mac" ]; then NOME_PROG=${NOME_APP_MAC:-}; else NOME_PROG=${NOME_APP:-}; fi
[[ "$NOME_PROG" =~ ^[A-Za-z0-9-]+$ ]] || { echo "nome del programma: solo lettere, numeri e trattini"; exit 1; }
perl -pi -e "s|(APP_NAME: RwLock<String> = RwLock::new\()\"RustDesk\"|\$1\"$NOME_PROG\"|" libs/hbb_common/src/config.rs
grep -q "RwLock::new(\"$NOME_PROG\".to_owned())" libs/hbb_common/src/config.rs || { echo "nome non applicato"; exit 1; }
if [ "$SISTEMA" = "windows" ]; then
  # l'eseguibile deve chiamarsi come l'app: l'installatore registra servizio e icone su <NOME_APP>.exe
  perl -pi -e "s|^set\(BINARY_NAME \"rustdesk\"\)|set(BINARY_NAME \"$NOME_PROG\")|" flutter/windows/CMakeLists.txt
  grep -q "^set(BINARY_NAME \"$NOME_PROG\")" flutter/windows/CMakeLists.txt || { echo "nome dell'eseguibile non applicato"; exit 1; }
elif [ "$SISTEMA" = "android" ]; then
  # id proprio: col com.carriez.flutter_hbb di RustDesk le due app non convivrebbero sul telefono
  ID_ANDROID="it.giovannimarchese.$(echo "$NOME_PROG" | tr 'A-Z-' 'a-z_')"
  perl -pi -e "s|applicationId \"com\.carriez\.flutter_hbb\"|applicationId \"$ID_ANDROID\"|" flutter/android/app/build.gradle
  grep -q "applicationId \"$ID_ANDROID\"" flutter/android/app/build.gradle || { echo "id Android non applicato"; exit 1; }
  perl -pi -e "s|android:label=\"RustDesk( Input)?\"|android:label=\"$NOME_PROG\$1\"|g" flutter/android/app/src/main/AndroidManifest.xml
  grep -q "android:label=\"$NOME_PROG\"" flutter/android/app/src/main/AndroidManifest.xml || { echo "nome Android non applicato"; exit 1; }
  # icone: classiche a tutta superficie, adattive col simbolo nel 66% centrale (zona sicura)
  command -v convert >/dev/null || { echo "serve ImageMagick (convert) per le icone Android"; exit 1; }
  R=flutter/android/app/src/main/res
  for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
    n=${d#*:}; f=$((n * 9 / 4)); in=$((f * 61 / 100))
    convert "$M/icone/icona-1024.png" -resize "${n}x${n}" "$R/mipmap-${d%%:*}/ic_launcher.png"
    cp "$R/mipmap-${d%%:*}/ic_launcher.png" "$R/mipmap-${d%%:*}/ic_launcher_round.png"
    convert "$M/icone/icona-1024.png" -resize "${in}x${in}" -background none -gravity center -extent "${f}x${f}" "$R/mipmap-${d%%:*}/ic_launcher_foreground.png"
  done
else
  perl -pi -e "s|^PRODUCT_NAME = RustDesk(?=\s*\$)|PRODUCT_NAME = $NOME_PROG|" flutter/macos/Runner/Configs/AppInfo.xcconfig
  grep -q "^PRODUCT_NAME = $NOME_PROG[[:space:]]*\$" flutter/macos/Runner/Configs/AppInfo.xcconfig || { echo "nome del pacchetto Mac non applicato"; exit 1; }
  perl -pi -e "s|RustDesk\.app|$NOME_PROG.app|g" build.py
fi
# alla CI serve il nome per impacchettare (exe da avviare, .app del dmg, apk)
[ -n "${GITHUB_ENV:-}" ] && echo "NOME_PROG=$NOME_PROG" >> "$GITHUB_ENV"

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
