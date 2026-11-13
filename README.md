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

# TROVAT1O

**Non perderti più una partita.** La prima versione aiuta a trovare e organizzare calcio amatoriale a 5, 8 e 11; la visione del marchio comprende attività più ampie.

## Stato dell’11 novembre 2026

Il sito pubblico è ancora l’**anteprima interattiva 2.0.2 con dati locali**, non la V1.0 cloud per utenti reali:

[Apri l’anteprima pubblica](https://trovato.diegolucentedesign.workers.dev/).

I sorgenti candidati includono Google PKCE, completamento profilo, Host/Sportivo, console Admin protetta, quote, esportazione, storico, push e predisposizione Premium. La funzione server `admin-console` è aggiornata alla **versione 2**; il nuovo frontend non è stato distribuito. Tutti i flag di attivazione restano `false`. Non usare dati personali reali nella demo.

Lo stato verificabile dei venti criteri è in [V1-STATUS.md](V1-STATUS.md). Non esiste una percentuale che sostituisca i test reali ancora necessari.

## Avvio locale su Mac

Se manca `config.js`, crea la configurazione di prova:

```sh
cp config.example.js config.js
```

Dalla cartella principale prepara i soli file pubblici e avvia il server:

```sh
bash scripts/package-release.sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory TROVAT1O-Cloudflare-Deploy/public
```

Apri [http://127.0.0.1:4173](http://127.0.0.1:4173). Per fermare il tuo server usa `Ctrl+C`; se la porta è occupata usa il server esistente o un’altra porta. Per una prova sulla stessa Wi-Fi puoi usare `--bind 0.0.0.0` e l’IP del Mac. Questo espone soltanto la cartella pubblica: non servire la root del progetto, che contiene documentazione e operazioni riservate. La demo locale non sincronizza eventi tra dispositivi.

## Google, ruoli e dati online

Il percorso V1.0 usa Google verificato e il completamento esplicito del profilo. Non richiede SMS a pagamento o una chiave CAPTCHA per giocare. Email/password, SMTP e OTP sono percorsi opzionali, non prerequisiti del login Google. Il telefono verificato serve alla condivisione facoltativa del recapito Host.

Il server distingue ruolo operativo e piano. Free e Premium ordinari non vedono la console; la demo Admin pubblica è stata rimossa dal candidato. L’ingresso dedicato nel profilo è mostrato solo dopo una conferma del backend per l’account marcato lato server. Il ruolo Admin non è selezionabile durante la registrazione: allowlist privata, sessione viva, secondo fattore TOTP recente e autorizzazioni SQL proteggono le operazioni anche contro chiamate dirette. I match passano da RPC con controlli di proprietà e capienza; il client non legge la tabella eventi direttamente.

Nel flusso cloud non viene proposta la scelta sessione/dispositivo e i dati demo non vengono usati come database condiviso. Sessione tecnica Auth, cache pubblica e identificativo per gestire le push sono separati dai match.

## Free, conservazione e Premium

I nuovi account partono Free. Con account verificato il limite è due eventi attivi; senza verifica consentita si può creare un evento privato ogni sette giorni. La visibilità dello storico Free termina sette giorni dopo la conclusione o l’annullamento effettivi; vedi [RETENTION-SETUP.md](RETENTION-SETUP.md).

La nuova durata dell’**account** Free è distinta: sette giorni dalla creazione del primo match, Premium verificato escluso, avvisi e protezioni su dati condivisi. Codice e interfaccia sono testati localmente, ma la migrazione **non è stata applicata** perché la conferma del connettore è scaduta. Non viene cancellato alcun account online. Vedi [ACCOUNT-LIFECYCLE.md](ACCOUNT-LIFECYCLE.md).

Premium previsto: €4,99/anno. Checkout, portale e webhook sono predisposti ma gli acquisti sono disattivati. I test non creano addebiti o piani reali; una pagina di ritorno non concede privilegi. Vedi [BILLING-SETUP.md](BILLING-SETUP.md).

## Verifiche

Le suite Node eseguono funzioni reali con trasporti controllati e controlli dei sorgenti; non sono login reali presso i fornitori:

```sh
for test_file in tests/*.cjs; do node "$test_file"; done
```

Il driver SQL generico salta esplicitamente il motore se non installato. Per il controllo obbligatorio PostgreSQL locale, usa le dipendenze esatte separate dall’app:

```sh
mkdir -p tmp/local-postgres
cp tests/fixtures/local-postgres/package.json tmp/local-postgres/package.json
cp tests/fixtures/local-postgres/package-lock.json tmp/local-postgres/package-lock.json
npm ci --prefix tmp/local-postgres --ignore-scripts --no-audit --no-fund
node tests/local-postgres.cjs --require-engine
```

Sono passati 22 suite Node, 13 moduli SQL e 12 regressioni con rollback locale; in aggiunta il checkpoint precedente ha verificato sei firme Stripe con SDK reale e i tipi dei gestori Deno. La CI ripete i controlli e il pacchetto senza pubblicare o usare segreti. Nel browser locale sono stati provati creazione, modifica, richiesta dalla mappa, ricerca, storico personale, filtro assistenza ed export PNG; il controllo successivo è stato interrotto da un diniego del browser, senza aggirarlo. Mancano OAuth/MFA reali, account distinti, concorrenza, job e prove post-deploy della V1.0.

## Sorgenti e distribuzione

Repository ufficiale: [Diegosh501/TROVAt10](https://github.com/Diegosh501/TROVAt10). Controlli: [GitHub Actions](https://github.com/Diegosh501/TROVAt10/actions).

`config.js` è escluso da Git; in CI viene generato da `config.example.js`. Le chiavi pubblicabili e gli URL appartengono alla configurazione pubblica; chiavi privilegiate, token, segreti OAuth/Stripe/VAPID e credenziali non devono comparire lì, nei log o nel repository.

`bash scripts/package-release.sh` rigenera le copie e gli archivi dai sorgenti. La cartella `TROVAT1O-Cloudflare-Deploy/public/` è il candidato aggiornato, non la prova del contenuto attualmente online. La pubblicazione è un’operazione successiva e coordinata; seguire [DEPLOY-READINESS.md](DEPLOY-READINESS.md) e [RELEASES.md](RELEASES.md).

## Riferimenti

- [Supabase](supabase/README.md): moduli, migrazioni applicate e operazione ancora da approvare.
- [Admin](ADMIN-SETUP.md), [push](PUSH-SETUP.md), [quote](WRITE-QUOTAS.md), [UX](UX-CHECKPOINT.md), [sicurezza](SECURITY.md).
- `privacy.html`, `termini.html`, `cookie.html`, `politiche.html`: revisione pre-lancio dell’11 novembre, coerente con i provider e le opzioni descritte. Richiede verifica finale dei trattamenti e contratti effettivi; non è un’attestazione legale.
- La guida illustrata aggiornata è inclusa nel pacchetto locale, in `output/pdf/`.

La regione del database remoto è EU Central e la lettura dell’11 novembre trova utenti, profili ed eventi a zero. Hosting e progetto esistenti non richiedono un dominio comprato per le prove. Nessun nuovo piano a pagamento è stato attivato; il costo iniziale zero resta soggetto alle quote dei fornitori e non è una garanzia di risorse illimitate.
