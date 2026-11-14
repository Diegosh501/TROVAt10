# TROVAT1O — backend Supabase

Versioni distribuite e criteri autorevoli: [V1-STATUS.md](../V1-STATUS.md). [Procedura rilascio](../DEPLOY-READINESS.md).

## Stato verificato

Progetto corretto `nrixslotansgrtrosaof`, organizzazione `thnqvzujtphdvpzemxuz`, regione EU Central, PostgreSQL 17.11. Non modificare l’altro progetto eventualmente mostrato nel browser.

Al 14 novembre 2026: 17 migrazioni registrate, due identità Google/profili Free e quattro eventi di collaudo. Funzioni pubblicate: admin-console v4, host-contact v1 e push-dispatch v1. Quest’ultima impone `PUSH_RELEASE_READY=false`: boot gestito verificato, invio e pianificazione spenti. Cron/pg_net assenti; sottoscrizioni e coda push vuote.

Google funziona nel collaudo. Auth pubblico rileva `external.email=true`, benché `emailAuthEnabled=false` nell’app. Chiudere il percorso non configurato sul server fino alla preparazione di SMTP e antiabuso; la sola UI non lo disabilita. Il preflight nella procedura di rilascio segnala questa discrepanza.

## Moduli, migrazioni e candidati

Ordine dei blueprint del controllo locale:

1. `schema.sql`, `notifications.sql`, `admin-security.sql`.
2. `oauth-profiles.sql`, `free-access.sql`, `billing.sql`.
3. `host-contact.sql`, `retention.sql`, `admin-operations.sql`.
4. `account-export.sql`, `write-quotas.sql`, `push-dispatch.sql`.
5. `account-lifecycle.sql`, `session-security.sql`, `account-erasure-requests.sql`.
6. `support-submit.sql`, `account-erasure-execution.sql`.

Sono 17 moduli, distinti dalle 17 migrazioni effettive in `recorded-migrations/`. Non è una procedura da rilanciare sul remoto popolato: alcuni file creano baseline o contengono versioni candidate.

Il ciclo account è applicato con enforcement/purge false. `pending-operations/account-lifecycle-disabled.sql` è storico, da non riapplicare. Assistenza verificata ed esecuzione revisionata della cancellazione restano candidate non applicate: [operazioni pendenti](pending-operations/README.md). Spostarle fra le migrazioni registrate solo dopo successo e versione confermati dal server.

Non usare `db push`, baseline o fixture Auth sul progetto esistente senza riconciliare la cronologia. Le vecchie prove remote che esigono zero utenti ora devono rifiutarlo.

## Identità e autorizzazioni

- Google crea l’identità; il profilo richiede username, ruolo, maggiore età e conferme esplicite. Tutti iniziano Free. Admin/Premium non derivano da metadata modificabili.
- Admin dipende da allowlist privata, sessione viva, TOTP aal2 recente, quote e audit. L’Edge usa il JWT del chiamante. Titolare assegnato, TOTP rinviato; console completa da collaudare.
- I client non leggono/modificano direttamente events. RPC controllano feed, richieste, roster, inviti, pin e transizioni. Token privato conservato solo come hash; sede e coordinate mascherate prima dell’ammissione e dopo rimozione.
- Contatto Host facoltativo e separato dall’evento, collegato al telefono verificato. La scrittura passa da host-contact; il flag del browser non autorizza condivisione.
- Supporto, quote, impronte, audit e dati finanziari non sono directory pubbliche. RLS senza policy nelle tabelle private è un diniego intenzionale. Le RPC SECURITY DEFINER devono mantenere controlli caller/proprietà.
- Storico, durata account e cancellazione sono politiche distinte. Non rimuovere report, dati condivisi o vincoli sconosciuti per forzare un purge.

## Configurazione e prove

Origini/redirect HTTPS esatti, senza wildcard. Google non richiede SMTP, SMS o Turnstile; gli altri percorsi richiedono la propria configurazione. La chiave publishable/anon è pubblica e non sostituisce RLS. Service-role, OAuth, VAPID privato, Stripe, webhook, Turnstile e OTP restano sul server, mai in log o checkpoint.

Gestori utente: `verify_jwt=true`. Dispatcher: false con autenticazione interna del job e gate iniziale false nel codice. Una release revisionata e i passaggi pertinenti sono necessari per attivare consegna/pianificazione. [Push](../PUSH-SETUP.md). Assistenza/cancellazione candidate, Premium €4,99/anno e acquisti restano spenti.

`node tests/local-postgres.cjs --require-engine` esegue 17 moduli e 17 regressioni con rollback su PGlite 0.5.16 e pgcrypto reale. Auth/JWT/MFA sono fixture.

La CI ha riprodotto 17 migrazioni su PostgreSQL 17.11 isolato, eseguito 13 contese e ripristinato un dump cifrato sintetico di 44 tabelle con dati/cataloghi corrispondenti. Auth, Storage, configurazione e segreti del progetto gestito hanno verifiche distinte ancora aperte. [Backup](../BACKUP-RESTORE-SETUP.md).

Prove cloud: due Google reali, flussi pubblici/privati, sei race HTTP e permessi ordinari. Restano TOTP personale, altro dispositivo fisico e ultimo posto fra due Sportivi remoti distinti.

[Admin](../ADMIN-SETUP.md) · [Assistenza](../SUPPORT-SETUP.md) · [Billing](../BILLING-SETUP.md) · [Storico](../RETENTION-SETUP.md) · [Account](../ACCOUNT-LIFECYCLE.md) · [Cancellazione](../ERASURE-REQUESTS.md) · [Quote](../WRITE-QUOTAS.md).
