# Assistenza remota — client col marchio

Fork di [RustDesk](https://github.com/rustdesk/rustdesk) (AGPL-3.0) usato per l'assistenza remota di Tecno Distribuzione e di Giovanni Marchese. Il codice di RustDesk non è toccato nel repo: le modifiche si applicano al momento della compilazione con `applica-marchio.sh`.

- `server.conf`: server, chiave pubblica e console scritti dentro il programma.
- `marchi/<nome>/`: nome, colori, logo e icone di ogni marchio.
- `.github/workflows/assistenza.yml`: compilazione su GitHub Actions, si lancia a mano scegliendo il marchio.

Il ramo `assistenza` parte dalla versione ufficiale 1.5.0.
