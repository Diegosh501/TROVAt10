# TROVAT1O

**Non perderti più una partita.** La prima versione aiuta a trovare e organizzare calcio amatoriale a 5, 8 e 11; il marchio è pronto ad allargarsi ad altri eventi.

## Preview pubblica

[Apri TROVAT1O su Cloudflare](https://trovato.diegolucentedesign.workers.dev/)

La preview gratuita usa asset statici su `workers.dev`, senza dominio acquistato. È pensata per provare la UI e i flussi sul dispositivo. Account, eventi e notifiche restano locali; non inserire dati personali. La release correttiva 2.0.2 è stata pubblicata il 10 novembre 2026; identificativi e correzioni sono registrati in [RELEASES.md](RELEASES.md).

## Avvio locale su Mac

```sh
# Dalla cartella di progetto che contiene index.html:
python3 -m http.server 4173 --bind 127.0.0.1
```

Apri [http://127.0.0.1:4173](http://127.0.0.1:4173). Ferma il server con `Ctrl+C`. Questo indirizzo funziona solo sul Mac. Per provarla da altri dispositivi sulla stessa Wi-Fi occorre avviare il server sull’indirizzo di rete del Mac e consentire la connessione nel firewall.

## Verifiche automatiche

```sh
node tests/smoke.cjs
node tests/ux-v2-smoke.cjs
node tests/responsive-smoke.cjs
node tests/brand-smoke.cjs
node tests/interactions-smoke.cjs
node tests/security-smoke.cjs
node tests/cloud-integration-smoke.cjs
node tests/runtime-regressions.cjs
node tests/service-worker-runtime.cjs
```

I test controllano UI e responsive, collegamenti e handler, regole privacy nel codice, configurazione sicura e collegamenti previsti con le funzioni cloud. Non sostituiscono prove con account distinti su un backend online.

## Stato cloud verificato il 10 novembre 2026

- Il progetto Supabase `TROVAT1O` è attivo. Schema V2, policy RLS e funzioni transazionali sono state applicate; le tabelle applicative sono vuote.
- Il client resta in modalità preview: `onlineReady: false`. La registrazione online non è attiva e non ci sono Edge Functions pubblicate.
- Supabase Auth richiede SMTP personalizzato per consegnare conferme e recupero password. Turnstile non è configurato. La verifica SMS richiede Twilio Verify e può avere un costo.
- Le notifiche locali funzionano nella demo; push in background e pagamenti Premium non sono attivi.

L’accesso al database degli eventi è chiuso al client: la ricerca usa il feed filtrato, che nasconde il campo privato agli utenti non ammessi. Le modifiche passano da funzioni server con controlli sul proprietario. I controlli Supabase hanno trovato avvisi generici su funzioni di accesso intenzionali e indici appena creati su un database senza righe; il controllo salute non ha segnalato problemi. Prima di attivare utenti reali servono comunque test con sessioni/account separati.

## Pubblicazione gratuita della preview

La cartella [TROVAT1O-Cloudflare-Deploy](TROVAT1O-Cloudflare-Deploy/) contiene i file pubblici e la configurazione del Worker. Dalla root sincronizza i pacchetti e gli archivi:

```sh
bash scripts/package-release.sh
```

Poi pubblica il Worker:

```sh
cd TROVAT1O-Cloudflare-Deploy
npm ci
npx wrangler deploy
```

Questo pubblica solo la preview statica: non attiva account condivisi o il backend. `trovat10.app` si potrà collegare in seguito quando sarà acquistato e configurato. Non mettere chiavi service-role, segreti Turnstile, credenziali Twilio o chiavi Stripe nei file pubblici o nel repository.

## File di riferimento

- `index.html`: interfaccia mobile-first e flussi locali/cloud.
- `assets/brand/`: logo e icone PNG approvati.
- `config.js`: impostazioni sicure della preview, senza credenziali e con cloud spento.
- `supabase/schema.sql`: schema e policy attualmente applicati al progetto.
- `supabase/functions/`: sorgenti locali delle funzioni, non ancora pubblicate.
- `privacy.html`, `cookie.html`, `termini.html`, `politiche.html`: informative della preview. Prima della registrazione pubblica vanno aggiornate con provider, retention e contatti effettivi. Non sono una certificazione legale.
- `SECURITY.md` e `DEPLOY-READINESS.md`: impostazioni, limiti e passaggi che restano per la beta online.

## Audit e ripristino

Consulta [AUDIT-PREDEPLOY.md](AUDIT-PREDEPLOY.md) per controlli eseguiti, prove non disponibili e criticità aperte; [RELEASES.md](RELEASES.md) contiene la procedura verificata di pubblicazione e rollback.


## Sorgenti ufficiali e CI

Repository scelto dal titolare: [Diegosh501/TROVAt10](https://github.com/Diegosh501/TROVAt10). Il repository precedente trovato conserva il vecchio pacchetto di bootstrap. Il sito usa un deploy diretto Wrangler e mantiene lo stesso indirizzo workers.dev.

Il workflow in .github/workflows/ci.yml controlla test, installazione da lockfile, pacchetti e dry-run senza pubblicare né usare segreti cloud. Lo stato aggiornato è nella [pagina Actions](https://github.com/Diegosh501/TROVAt10/actions).

## Verifica prestazioni e PWA

Sul rilascio HTTPS 2.0.2, Lighthouse mobile 13.5.0 ha misurato LCP 2,142 s, CLS 0, prestazioni 96/100 e accessibilità 100/100. In una sessione interattiva distinta con CPU 4× rallentata, INP 120 ms. Sono misure di laboratorio/sessione, non statistiche degli utenti reali. Ricaricamento offline da service worker, ricerca e apertura dei dettagli sono stati provati in Chrome; rete e CPU sono state ripristinate al termine.
