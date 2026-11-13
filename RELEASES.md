# Stato autorevole — 13 novembre 2026

Questa sezione prevale sui checkpoint storici sottostanti.

- Pubblico aggiornato: **1.0.0-rc.1**, anteprima interattiva, https://trovato.diegolucentedesign.workers.dev/ . Versione Cloudflare `959a4c70-a070-4ee8-aa21-b306260b3165`, pubblicata l’11 novembre. Non è ancora V1.0 cloud.
- Nuova verifica HTTPS del 13 novembre: **17/17 asset identici**, intestazioni corrette, **5/5 percorsi riservati negati**. Ricevuta: `output/audit/2026-11-13/live-verification.json`.
- Supabase corretto `nrixslotansgrtrosaof`: **15 migrazioni**. Ciclo account applicato e **enabled=false, purge_enabled=false**. Nessun job installato, nessuna cancellazione attiva. Utenti/eventi reali ancora zero.
- Nuovo modulo `supabase/session-security.sql` applicato: sessione Auth esatta e viva, account valido, **10 policy RLS restrittive** con USING/WITH CHECK. Non annulla richieste già in corso o snapshot MVCC precedenti.
- Test locale aggiornato: **14 moduli SQL / 13 regressioni** con rollback, compresa session-security. Due controlli negativi rilevano un bypass intenzionale dei gate/RLS. Auth e JWT sono fixture, non login reali. Ultima esecuzione Node: **22/22**.
- Il tentativo Google del 13 novembre, dopo la conferma «Impostazione modificata», è ancora negato dalla regola salvata/gestita del browser. Nessun aggiramento. Provider Google non completato; frontend mantiene tutti i Ready=false.
- Master aggiornato: `output/handoff/OBIETTIVO-MASTER-R3.md`, **25 criteri V1 e 11 scenari reali** A–I,L,M. Nessuno scenario integralmente collaudato online: **0/11**. V2=PUBLIC BETA; V3=STABLE; V4=COMPLETE PLATFORM. Le vecchie barre 0/7 descrivono il precedente obiettivo.
- Cancellazione volontaria ancora mancante: audit `output/audit/2026-11-11/erasure-readiness-review.md`. Non equiparare scadenza Free a diritto di cancellazione. Conservazione Billing/dipendenze da risolvere prima del purge.
- Prossime priorità: Google–Supabase sul progetto corretto; Admin reale TOTP; due identità Host/Sportivo e persistenza; export/erasure/supporto e retention server; ripristino; poi collaudo V1. Push e apertura beta V2 successive. Premium/Stripe predisposti ma pagamenti spenti, tutti iniziano Free.
- Nessun nuovo costo, SMS, acquisto o account Admin creato. Il dominio acquistato resta futuro.

---

## Documento e checkpoint precedenti

# Checkpoint dell’11 novembre 2026

Nessun nuovo rilascio frontend: il pubblico resta 2.0.2, versione Cloudflare 79bbea69-3511-400e-8603-5de3c9acacdb. La nuova UI è solo nel candidato e negli archivi aggiornati.

Aggiornamento server eseguito: admin-console versione 2, verify_jwt=true, bundle SHA-256 9fafb5f00f143e58fb9a798469a6179ad2cfc1e2d11adf1c89ab6659c49bf4ee. Il sorgente letto dal servizio coincide con quello candidato. Richieste senza credenziali o con token falso:401; preflight origine autorizzata:204. Il sorgente precedente è conservato nell’audit privato per un ritorno controllato, non è un rollback eseguito.

Sincronizzazione sorgenti iniziale: commit 7c78c6277e7fd2d390c1267e21b220598aefc9a2 con CI verde. Le modifiche successive hanno un commit e una ricevuta separati. Nessun acquisto, nuovo Admin o cancellazione account attivati. Vedere V1-STATUS.md e ACCOUNT-LIFECYCLE.md.

## Cronologia dei rilasci frontend

# Registro rilasci TROVAT1O

## 10 novembre 2026 · 2.0.0 pubblicata prima dell’audit

- Ambiente: Worker Cloudflare `trovato`, asset statici in `TROVAT1O-Cloudflare-Deploy/public/`.
- URL: https://trovato.diegolucentedesign.workers.dev/
- Versione Cloudflare: `9dbc71ac-657a-4102-bfc3-7d2c8b547d12`.
- Procedura: `npx wrangler deploy` dalla cartella Cloudflare, nessuna modifica funzionale prima del rilascio.
- Esito: exit 0, HTTP 200; hash del documento scaricato uguale al documento caricato.
- SHA-256 index: `530bbd5ac1c53d25cc16aa28dcf4a99b74bd6b4d4ce99060723f1a98f9a33d4b`.
- Ora: circa 01:28 UTC / 02:28 Europe/Rome; verifica HTTP alle 01:29 UTC.
- Il rilascio è una demo locale ospitata su HTTPS: `onlineReady: false`, nessun account multiutente attivato.
- Evidenze e copia degli asset iniziali: `output/audit/2026-11-10/releases/` nel workspace originale.

## 2.0.1 · aggiornamento correttivo raggruppato

- Pubblicata il 10 novembre 2026; verifica HTTPS: 2026-11-10T01:54:01.988Z.
- Versione Cloudflare: 8f4bfd35-00dd-4a83-9192-c221273fc607, procedura npx wrangler deploy, exit 0.
- Home 200; tutti i 16 asset pubblici coincidono con il pacchetto caricato. CSP, HSTS e blocco frame verificati sulla risposta reale.
- SHA-256 index: 776629b5ee2cc5577c202e758ee338291f8d7be23c9a31833740814b2bb1b446.
- Browser: metadata 2.0.1, una sola CTA Auth principale, schermata mobile e nessun console error/warning nella sequenza provata.
- Tutte le correzioni sono elencate in CHANGELOG.md e AUDIT-PREDEPLOY.md. Il cloud resta disattivato nella configurazione pubblica.

## Procedura di rilascio

1. Eseguire i controlli in `tests/*.cjs`; mantenere cloud e push disabilitati finché non verificati con provider reali.
2. Eseguire `bash scripts/package-release.sh` dalla root. Lo script confronta i file distribuiti con i sorgenti prima di creare gli archivi.
3. Dalla cartella `TROVAT1O-Cloudflare-Deploy`: `npm ci`, poi `npx wrangler deploy`. L’autenticazione Cloudflare resta nella configurazione locale di Wrangler, esclusa dai pacchetti.
4. Registrare Version ID, data, hash e risultato. Verificare home, config, service worker e intestazioni via HTTPS; poi eseguire smoke nel browser.

## Rollback frontend

Il comando disponibile e verificato con Wrangler 4.158.0 è:

```sh
cd TROVAT1O-Cloudflare-Deploy
npx wrangler rollback 9dbc71ac-657a-4102-bfc3-7d2c8b547d12 --message "Ripristino preview 2.0.0"
```

Il rollback modifica il rilascio online: usarlo soltanto in caso di regressione. Non è stato eseguito durante l’audit per non sostituire una versione funzionante. Se si ripubblicano asset manualmente, incrementare la versione cache di `sw.js` e verificare anche un browser che aveva già installato la PWA.

## Database e backup

Schema base e notifiche sono separati in `supabase/schema.sql` e `supabase/notifications.sql`. Sono blueprint per un progetto vuoto: non rieseguire l’intero baseline su un database popolato. Le modifiche live passano da migration mirate registrate da Supabase. Esportare e riconciliare la cronologia prima di usare `db push` da un nuovo checkout.

Nessun backup dati o ripristino completo è stato verificato. Prima di accogliere utenti reali, verificare i backup effettivamente disponibili nel piano Supabase, conservare un export protetto e provare il ripristino in un ambiente separato. La transazione di test con ROLLBACK verifica l’assenza di righe residue, non un backup/restore dell’intero servizio. Correggere le policy con migration successive; non annullare le protezioni per recuperare compatibilità.


## 2.0.2 · gruppo prestazioni e accessibilità

- Pubblicata sullo stesso Worker; versione Cloudflare 79bbea69-3511-400e-8603-5de3c9acacdb.
- Verifica HTTPS: 2026-11-10T11:34:03.833Z,16/16 asset coincidenti e intestazioni corrette.
- SHA-256 index: 75f728b8ae0b8a91d5d5fdebb5d3fc2a1e6020285520592d21cc7cf787cd382b.
- Lighthouse mobile: Performance 96, Accessibility 100, LCP 2141,992 ms, CLS 0, TBT 150 ms.
- Sessione interattiva CPU 4×: INP 120 ms; ricaricamento, ricerca e dettagli offline verificati con risorse Servite dal ServiceWorker.
- Include PNG ottimizzato, contrasto/navigazione tastiera, stabilità del caricamento e workflow CI. Cloud e push restano disabilitati nel client.
- Il sorgente ufficiale scelto dal titolare è Diegosh501/TROVAt10; verificare commit e job sulla pagina Actions. I risultati del caricamento sono conservati nei report locali output/audit/2026-11-10/.
