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

# Stato verificabile della V1.0 ONLINE

Aggiornato l’11 novembre 2026 dopo la ripresa del checkpoint. Questo file sostituisce le vecchie percentuali e le descrizioni storiche conservate nell’archivio di audit.

**Frontend pubblico:** anteprima 2.0.2 su https://trovato.diegolucentedesign.workers.dev/ . **Candidato locale:** successivo, con nuove protezioni e flussi. **Server Admin:** versione 2 distribuita e confrontata con il sorgente. Nessun nuovo deploy frontend.

## Decisioni correnti

- Google verificato, completamento profilo esplicito, Host/Sportivo dello stesso account. Admin è un permesso server con sessione viva e TOTP recente.
- Dati condivisi nel cloud; niente scelta sessione/dispositivo nel flusso online. La demo resta separata, con dati sintetici locali.
- Tutti gli account partono Free. Premium facoltativo a €4,99/anno, acquisti ancora spenti.
- Nuova durata account Free: sette giorni dal PRIMO match creato, esclusione del Premium verificato attivo, avvisi e conservazione prudente. Codice testato ma migrazione e attivazione ancora mancanti.
- Storico Free: sette giorni dalla conclusione/annullamento effettivi. Il codice SQL è applicato; il job non è attivato.
- Niente SMS obbligatori con Google verificato; il numero Host condiviso resta opzionale e richiede verifica e consenso.
- Niente chat. Avvisi, richieste e promemoria; primo perimetro calcio 5/8/11, lista/mappa, eventi pubblici o privati, inviti e PNG con logo.
- Nessun acquisto di dominio o aumento a pagamento dell’infrastruttura autorizzato automaticamente.

## Venti criteri finali

| Criterio | Stato | Evidenza e limite |
| --- | --- | --- |
| URL pubblico HTTPS | VERIFICATO per preview | Il dominio gratuito esiste; non è ancora la V1.0 cloud |
| Build e pacchetto | VERIFICATO per il candidato | Test e confezionamento locali; CI e archivi identificati nei report, nessun deploy implicito |
| Autenticazione Google | PARZIALE | PKCE e profilo presenti; trasferimento credenziale/provider e login reale mancanti |
| Profili persistenti | IMPLEMENTATO | SQL applicato e fixture testati; profili reali ancora zero |
| Ruoli distinti | PARZIALE | Controlli server presenti; Host/Sportivo/Admin reali ancora da collaudare |
| Console riservata | PARZIALE | Edge v2 distribuita; token falso/assenza credenziali rifiutati. Allowlist e TOTP reali da configurare |
| Navigazione per ruolo | VERIFICATA in locale | Browser e trasporti controllati; collaudo cloud ancora necessario |
| Gestione eventi cloud | PARZIALE | RPC applicate, UI collegata; nessun evento reale creato |
| Persistenza multi-dispositivo | DA VERIFICARE | Prove con due identità e browser/dispositivi reali mancanti |
| Partecipazioni e comunicazioni | PARZIALE | Richieste e notifiche SQL presenti; push e promemoria reali da configurare e consegnare |
| Nuovi account Free | IMPLEMENTATO | Profilo server parte Free; nessun acquisto test attribuisce Premium live |
| Scadenze automatiche | PARZIALE | Match SQL applicato, job spento. Account SQL/client testati, migrazione non applicata |
| Sicurezza essenziale | PARZIALE | RLS, confini account, MFA, quote e handler testati; nessuna garanzia contro ogni attacco e prove reali ancora aperte |
| Account distinti reali | DA VERIFICARE | Fixture e profilo demo non equivalgono a login Google reali |
| Smoke post-deploy V1.0 | MANCANTE | Disponibili prove della preview e del perimetro anonimo dell’Edge Admin |
| Nessun blocco fondamentale | NON DIMOSTRATO | Google, provider/funzioni, automatismi e prove reali sono ancora gate |
| Infrastruttura iniziale gratuita | PARZIALE | Servizi esistenti; quota/continuità/backup da convalidare prima del lancio |
| Nessuna spesa non autorizzata | VERIFICATO per questa ripresa | Nessun piano comprato, SMS inviato o pagamento reale eseguito |
| Documentazione aggiornata | AGGIORNATA al checkpoint | README, informative v2 e guida 8 pagine; revisione dei contratti/provider ancora necessaria |
| Recupero | PARZIALE | Tredici migrazioni preservate e rollback hosting documentato; backup dati e ripristino integrale non provati |

## Risultati della ripresa

- Nuova richiesta Admin completata nel candidato: niente Console demo per utenti locali o normali, Premium non concede Admin, ingresso dal profilo soltanto dopo sonda qualificata del backend. La marcatura server è un hint, non un permesso. Ventitré scenari aggiuntivi verificano metadata falsi, revoca, link diretto, cambio account, logout e risposte tardive. La verifica online con Google/TOTP reale resta aperta.
- I due rilievi sul ciclo account sono corretti: timestamp reale dopo il blocco dell’ACK e rinnovo conservazione serializzato sugli stessi parent del worker. La regressione rifiuta il vecchio timestamp di inizio transazione; la concorrenza reale a più connessioni resta da provare.

- Primo commit di sincronizzazione sorgenti: `7c78c6277e7fd2d390c1267e21b220598aefc9a2`, 118 file; CI [42951137476](https://github.com/Diegosh501/TROVAt10/actions/runs/42951137476) verde. Le modifiche successive hanno una ricevuta separata nel report finale: non attribuire loro automaticamente il verde di questo commit.
- 22 suite Node; 13 moduli SQL e 12 regressioni con conteggi identici dopo rollback nel PostgreSQL locale. PGlite 0.5.16 usa PostgreSQL 18.6, diverso dal remoto 17.11: non prova GoTrue, MFA reale, concorrenza o Cron.
- Browser locale: profilo QA, creazione privata da Organizza, modifica, presenza nei propri match, assenza dalla ricerca pubblica, ricerca/azzera, pin mappa, richiesta pending, filtro assistenza e download PNG. Viewport 320/390/768/1440 senza overflow osservato nei contesti esaminati. Corretto il font dei campi che una vecchia regola rendeva 11 px: ora 16 px e 46 px di altezza su mobile. Non sono stati verificati tutti i browser o tutti i dispositivi.
- Le misure statiche responsive precedenti non avevano individuato il conflitto di specificità CSS; sono state integrate da misure effettive del browser. Struttura del form corretta, opzioni compatte, consenso a larghezza piena e nomi accessibili aggiunti al supporto.
- Admin Edge v2: sorgente remoto identico, JWT richiesto, richieste senza credenziali e con token falso restituiscono 401; preflight dell’origine autorizzata 204. Non è una prova di accesso Admin reale.
- Health Supabase senza avvisi. I linter di sicurezza segnalano policy assenti sulle tabelle private chiuse ai client e RPC SECURITY DEFINER intenzionali: sono avvisi da revisionare nel contesto dei controlli, non permessi da aprire automaticamente.

## Blocchi e prossimi passi

1. Accesso alle console: il browser Google ha un diniego salvato; non aggirarlo. Il browser Supabase mostrava un account/progetto diverso da quello collegato al connettore. Riconciliare l’accesso al progetto corretto `nrixslotansgrtrosaof` prima di configurare Google. L’ultima interazione sul browser locale è stata anch’essa negata: non riprovare attraverso altri strumenti o superfici.
2. La nuova operazione `supabase/pending-operations/account-lifecycle-disabled.sql` ha richiesto una conferma operativa poi scaduta. Lettura successiva: nessuna tabella lifecycle, tredici migrazioni, zero utenti. File pronto per revisione/approvazione; non applicato e nessuna cancellazione attiva.
3. Completare provider, Admin reale, funzioni, push/reminder, esportazione/cancellazione su richiesta e job. Prima di attivare la durata Free proposta, rendere effettivo il percorso Premium, comunicare condizioni e provare casi di acquisto/scadenza in ambiente approvato.
4. Verificare contratti dati/trasferimenti, gestione delle pratiche e backup/ripristino; provare i flussi A-G con account distinti e solo dopo effettuare il rilascio frontend coordinato e lo smoke online.

`onlineReady`, `emailAuthEnabled`, `billingReady`, `exportReady`, `accountLifecycleReady`, `pushReady` restano false; Billing è in modalità test. Il pubblico non deve vedere un successo simulato presentato come azione cloud.

Riferimenti: [readiness](DEPLOY-READINESS.md), [account](ACCOUNT-LIFECYCLE.md), [match](RETENTION-SETUP.md), [Billing](BILLING-SETUP.md), [push](PUSH-SETUP.md). Non dichiarare il 100% finché i venti criteri non hanno evidenza reale.
