# TROVAT1O · Pacchetto di rilascio

Candidato sorgente **1.0.0-rc.7**. Questa cartella viene rigenerata da `bash scripts/package-release.sh`: il suo `public/config.js` predefinito resta una preview, con attivazioni spente. Non copiare chiavi server nei file pubblici.

Il collaudo cloud effettivo è [1.0.0-cloud-test.10](https://v1-check-trovato.diegolucentedesign.workers.dev/), Cloudflare `8ac772c9-508b-47db-8487-14b9d0946a2d`. Usa una configurazione separata, soli parametri pubblicabili e il progetto Supabase corretto. Il pacchetto del collaudo distribuito viene fornito separatamente dal sorgente locale.

Il sito principale resta [1.0.0-rc.1](https://trovato.diegolucentedesign.workers.dev/), anteprima locale. Un caricamento `wrangler versions upload` aggiorna una versione/alias di prova, non il traffico principale.

## Verifica senza pubblicare

Dalla root dei sorgenti:

```sh
bash scripts/package-release.sh
cd TROVAT1O-Cloudflare-Deploy
npm ci --ignore-scripts --no-audit --no-fund
./node_modules/.bin/wrangler deploy --dry-run
```

Prima del rilascio effettivo: chiudere i gate in V1-STATUS.md, predisporre configurazione, origine e redirect esatti, verificare servizi e permessi. Pubblicare una versione coordinata e riprovare i flussi sul medesimo URL. Conservare versione precedente e procedura di recupero; non confondere rollback frontend con ripristino dei dati.

Per navigare localmente, servire soltanto `public/`, mai l’intero progetto. Il dominio gratuito basta al collaudo; il futuro dominio acquistato richiederà aggiornamenti coerenti di link, OAuth, CORS e informative.
