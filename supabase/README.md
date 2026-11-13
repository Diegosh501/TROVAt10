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

# TROVAT1O - backend Supabase

## Stato effettivo dell’11 novembre 2026

Il progetto corretto è `nrixslotansgrtrosaof`, nome `TROVAt10`, organizzazione `thnqvzujtphdvpzemxuz`, regione EU Central, PostgreSQL 17.11. La lettura della ripresa ha trovato zero utenti Auth, profili ed eventi. Non modificare l’altro progetto `nentyffgpuoiczdttzfu` eventualmente mostrato nel browser.

Sono applicate tredici migrazioni, esportate in `recorded-migrations/`. L’ultima è `20261111025149_trovat1o_online_beta_operations`, che comprende contatto Host, storico, operazioni Admin, esportazione, quote e dispatcher SQL. Non sono attivi job. La sola Edge distribuita è `admin-console` versione 2, JWT richiesto. Google, pagamenti, push e frontend cloud restano da configurare e collaudare.

## Moduli sorgenti

Per un ambiente di prova nuovo con i ruoli/schemi Supabase, l’ordine dei blueprint usato dal controllo locale è:

1. `schema.sql`, `notifications.sql`, `admin-security.sql`.
2. `oauth-profiles.sql`, `free-access.sql`, `billing.sql`.
3. `host-contact.sql`, `retention.sql`, `admin-operations.sql`.
4. `account-export.sql`, `write-quotas.sql`, `push-dispatch.sql`.
5. `account-lifecycle.sql`, nuovo modulo account disattivato e **non applicato sul remoto**.

Questi tredici moduli non corrispondono uno-a-uno alle tredici migrazioni remote. Il blueprint OAuth contiene ora la nuova versione delle informative; la relativa modifica remota è inclusa nell’operazione pendente. Non rieseguire baseline o blueprint sul database esistente. Non usare il fixture Auth dei test su Supabase.

`pending-operations/account-lifecycle-disabled.sql` è pronto per revisione, con controllo database vuoto. La conferma del connettore è scaduta; non contiene un’attivazione automatica. Consultare `../ACCOUNT-LIFECYCLE.md` prima di proseguire.

## Autorizzazioni e dati

- Auth Google crea l’identità; un passaggio esplicito raccoglie username, ruolo, maggiore età e conferme. Tutti partono Free. Non inferire Admin o Premium da metadata modificabili.
- Host/Sportivo sono ruoli operativi. Admin dipende da UUID verificato in allowlist privata, sessione viva, TOTP aal2 recente, quote e audit. Le operazioni Admin usano il JWT del chiamante e non una chiave privilegiata per aggirare questi controlli.
- I client non leggono né modificano direttamente `events`; feed, modifiche, richieste, roster, inviti e pin usano controlli server. Un invito non mostra il campo privato prima dell’ammissione; nel database il token è solo SHA-256.
- Il contatto Host è separato dall’evento, facoltativo e associato all’impronta del telefono effettivamente verificato. La scrittura passa dal gestore `host-contact`; nessuna condivisione basata sul solo flag del browser.
- Supporto, quote, impronte e dati di pagamento non sono directory pubbliche. Le tabelle private hanno RLS e nessun grant ai client; l’assenza di policy di lettura è intenzionale.
- Premium è scritto soltanto dopo una verifica server di pagamento live. Test e live sono isolati. Il modulo account protegge anche i collegamenti finanziari e non elimina clienti Stripe.
- Storico dei match e durata dell’account sono politiche distinte, con avvisi, vincoli e attivazioni separate. Nessun job elimina dati solo perché il browser non li mostra più.

## Configurazione e funzioni

Il percorso Google non richiede SMTP, SMS o Turnstile. Email/password richiederebbe la propria configurazione separata, mentre la verifica del numero è opzionale. Le URL di redirect e l’origine devono coincidere con il sito effettivo. Non usare un’origine wildcard per operazioni autenticate.

La chiave publishable/anon è pubblica e richiede comunque RLS. Service-role, secret OAuth, VAPID privato, chiave Stripe, segreto webhook, Turnstile e segreti OTP restano solo sul server. Il contatto Host usa lo stesso HMAC del percorso OTP. Il dispatcher ha un proprio segreto server e non è una funzione chiamabile liberamente dal browser.

Impostare `verify_jwt=true` per i gestori chiamati da utenti con JWT. I webhook o i job che usano una propria autenticazione verificata possono richiedere `false`: mai disattivare il controllo senza un’autenticazione nel gestore e i relativi test. Leggere le istruzioni specifiche di Billing e push.

## Prove e cronologia

Il driver `../tests/local-postgres.cjs --require-engine` usa PGlite 0.5.16 in memoria e pgcrypto reale: tredici moduli e dodici regressioni con rollback verificato. Auth/JWT/MFA sono fixture sintetici. Non prova scambio OAuth, concorrenza a connessioni separate, estensioni gestite, Cron, backup o provider remoti.

I test remoti vanno limitati a un ambiente di prova autorizzato e devono rifiutare database con dati esistenti. La vecchia autorizzazione a un determinato test sintetico non equivale a permesso indiscriminato di eliminare utenti reali.

Le migrazioni registrate dipendono dalla base Supabase e da `public.rls_auto_enable()`. Non è stato verificato un replay completo né un ripristino dei dati. Non copiare automaticamente la cronologia in `migrations/` e non lanciare `db push` senza riconciliare lo stato e provare un ambiente separato.

Stato generale: [V1-STATUS.md](../V1-STATUS.md). Impostazioni: [Admin](../ADMIN-SETUP.md), [Billing](../BILLING-SETUP.md), [match](../RETENTION-SETUP.md), [account](../ACCOUNT-LIFECYCLE.md), [push](../PUSH-SETUP.md), [quote](../WRITE-QUOTAS.md).
