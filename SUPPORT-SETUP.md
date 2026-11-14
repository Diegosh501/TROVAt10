# Assistenza — configurazione e verifica

## Stato al 13 novembre 2026

L’invio nell’app è **implementato e verificato localmente, non attivo nel cloud**. Le due richieste di migrazione al connettore sono scadute senza applicazione: il progetto `nrixslotansgrtrosaof` conserva 17 migrazioni e non ha le nuove tabelle. Non spostare lo script in `recorded-migrations/` finché il server non ne conferma l’applicazione.

File pronto: `supabase/pending-operations/20261113161033_trovat1o_verified_support_submission.sql`, generato inizialmente dalla CLI ufficiale e corrispondente al modulo testato `supabase/support-submit.sql`. Non applicare di nuovo baseline o fixture sul database popolato.

La UI mostra il contatto email quando il servizio non è pronto. Non presenta un pulsante di invio non operativo. La disponibilità dell’email o di un operatore umano non viene dimostrata da un link mailto. Il numero indicato dal proprietario resta da verificare prima di presentarlo come canale operativo.

## Garanzie del percorso implementato

- Chiamante autenticato con email confermata; controllo della sessione reale prima della verifica anti-bot e di nuovo nella transazione di scrittura. Nessun privilegio Admin necessario. La scadenza Free non toglie l’accesso all’assistenza.
- Origini HTTPS esatte, preflight con gli header SDK, JSON con limite di 32 KiB, categorie e lunghezze controllate. Nessun identificativo utente o stato amministrativo scelto dal browser.
- Turnstile dedicato: verifica server di esito, hostname, azione `support_submit` ed età massima di cinque minuti, con timeout. Le chiavi pubbliche dimostrative non abilitano il server.
- Nonce anti-riuso conservato come SHA-256 per dieci minuti; unicità globale anche fra account diversi. La risposta persa si può ritentare con una nuova verifica anti-bot.
- UUID dell’invio e impronta del contenuto garantiscono la stessa ricevuta per una richiesta identica nelle successive 24 ore. Cambiare contenuto richiede un nuovo invio. La chiave rimane in memoria della scheda: chiuderla o riaprire il modulo interrompe questa continuità.
- Massimo cinque nuove pratiche per account e giorno UTC. Quota, nonce, pratica e ricevuta sono un’unica transazione. Un errore non lascia una falsa ricevuta o una quota consumata a metà.
- Nome, email di risposta e collegamento al profilo richiedono scelte distinte, inizialmente non selezionate. Senza di esse la pratica non contiene il profilo o recapiti ricavati automaticamente da Google. La ricevuta tecnica privata conserva un collegamento temporaneo account/pratica: non equivale ad anonimato assoluto.
- Le due tabelle di controllo sono private, con RLS e senza accesso diretto anche per service_role; solo la RPC dedicata può scriverle. L’Admin ordinario non riceve questi registri dalla coda delle pratiche.

## Passaggi per attivare realmente il servizio

1. Rinnovare la conferma richiesta dal connettore e applicare la sola operazione pendente. Verificare migrazione registrata, RLS, grant, regole di cancellazione e stato dei job invariato. Salvare la ricevuta con la versione effettiva restituita dal server.
2. Predisporre un widget Cloudflare Turnstile per le sole origini possedute: `trovato.diegolucentedesign.workers.dev` e `v1-check-trovato.diegolucentedesign.workers.dev`. Non inserire il dominio futuro non ancora acquistato. La creazione di una credenziale persistente o nuovi consensi del servizio richiedono la relativa conferma; nessun piano a pagamento.
3. Custodire `SUPPORT_TURNSTILE_SECRET_KEY` nei segreti Supabase. Non riutilizzare la chiave generica di Auth e non pubblicarla nei sorgenti, nei log, negli screenshot o in chat. I segreti Supabase standard rimangono nel server.
4. Impostare server `APP_ORIGIN` esatta e, se serve, `APP_TEST_ORIGIN` esatta. Pubblicare `support-request` con `verify_jwt=true`. Mantenere `SUPPORT_ENABLED` diverso da `true` finché lo schema e la configurazione non sono coerenti.
5. Nel solo collaudo, configurare il site key pubblico in `supportTurnstileSiteKey` e `supportReady:true`, quindi attivare `SUPPORT_ENABLED=true`. La chiave generica `turnstileSiteKey` resta separata per Auth. La libreria CAPTCHA viene caricata solo aprendo il percorso pertinente: un suo guasto non deve bloccare l’accesso Google.
6. Completare una verifica Turnstile reale nel browser con la necessaria conferma. Provare una pratica senza recapiti, una con consenso esplicito, retry, sessione non valida, quota e indisponibilità del servizio. Verificare il ticket nella console con il TOTP personale del titolare, che rimane rinviato: non aggirarlo.
7. Aggiornare informative e documentazione con fornitori, tempi e servizi effettivi; pubblicare sul principale solo dopo i gate generali V1. Un test con trasporti simulati non prova Turnstile reale, invio email o lettura della coda Admin.

## Dati tecnici e conservazione

`private.support_submission_receipts` collega per 24 ore utente, UUID dell’operazione, hash del contenuto e ID pratica. `private.support_captcha_redemptions` conserva per dieci minuti l’hash del token, ID dell’operazione e collegamento utente. Non conserva il token originale, una copia del testo o dell’email. La pulizia opportunistica elimina fino a 100 righe scadute per registro in un invio riuscito; senza nuovi invii i record possono restare oltre la finestra di validità. Prima dell’attivazione definire una pulizia pianificata limitata e le informative coerenti. Nessun job o cancellazione automatica è stato attivato da questo modulo.

L’operazione aggiorna l’elenco dei soli due nuovi vincoli Auth conosciuti: ricevuta in cascata e riferimento nonce azzerato alla cancellazione. Vincoli futuri sconosciuti continuano a bloccare il purge. La pratica è protetta dal vincolo ricevuta finché non scade: prevedere la procedura per l’esercizio dei diritti senza inventare cancellazioni già operative.

## Prove ripetibili

- `node tests/support-edge-runtime.cjs`: 17 scenari sull’handler reale con Auth, CAPTCHA e RPC controllati.
- `node tests/support-client-runtime.cjs`: 14 scenari UI, consensi, retry e cambio account.
- `node tests/bootstrap-runtime.cjs`: 7 scenari, compresa indisponibilità CAPTCHA con Google indipendente.
- `node tests/local-postgres.cjs --require-engine`: 17 moduli e 17 regressioni SQL, comprese `tests/sql/support-submit.sql`; solo database locale isolato e rollback.
- Deno controlla il codice reale con il lockfile; CI include il nuovo handler.

Due mutazioni negative del solo ambiente locale hanno dimostrato che togliere il controllo sessione o il vincolo anti-riuso fa fallire la regressione. Nessuna protezione remota è stata rimossa per provarlo.
