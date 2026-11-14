# Sicurezza e limiti verificati

Aggiornato il 14 novembre 2026. Stato operativo e criteri finali: [V1-STATUS.md](V1-STATUS.md). Le prove documentano il perimetro verificato e non certificano invulnerabilità.

## Autenticazione effettiva

Google OAuth PKCE e due identità reali sono collaudati con completamento esplicito del profilo. Il dominio Gmail non sostituisce controlli contro abusi o autorizzazioni.

Auth pubblico rileva Google ed email abilitati, anonimi/telefono disabilitati, signup consentito e conferma email richiesta. L’app offre solo Google (`emailAuthEnabled=false`). Chiudere temporaneamente il provider email server fino alla configurazione e verifica SMTP/antiabuso. La console richiede un nuovo accesso; la modifica non è stata eseguita.

```sh
node scripts/verify-auth-settings.mjs TROVAT1O-Cloudflare-Deploy/public/config.js output/audit/auth-provider-preflight.json
```

Il controllo legge solo /auth/v1/settings del progetto corretto. Rifiuta chiavi server, altre origini, redirect, risposte malformate, provider non offerti e conferma email disabilitata. Non esegue JavaScript dal config, non crea utenti, non accede e non invia messaggi. Preview indica esito non verificato. SMTP, CAPTCHA e consegna restano verifiche separate del Master.

Google non conferma un numero WhatsApp digitato. Il recapito Host richiede consenso e corrispondenza HMAC al numero verificato. OTP/SMS restano opzionali e spenti; nessun costo attivato.

## Admin e sessioni

Admin non è selezionabile e non deriva da email nel browser, Free/Premium o user_metadata. Allowlist UUID privata, account valido, sessione viva, TOTP aal2 recente, quote e audit proteggono le RPC. L’Edge usa il JWT del chiamante; non aggira l’autorizzazione con service-role.

L’indizio server in app_metadata limita solo le sonde di navigazione. Prima della conferma backend non compaiono metriche, pratiche o funzioni privilegiate. Logout, cambio account, rinnovo token e revoca invalidano lo stato client. Titolare già assegnato, TOTP rinviato: non crearlo, acquisirne i codici o simularlo.

La migrazione `20261113012931_trovat1o_live_session_guards` è applicata. Le RPC/letture protette passano da is_email_confirmed/has_live_session che rifiutano sessioni revocate. Il precedente limite sul solo JWT ordinario è corretto. Le regressioni sintetiche e le sonde cloud hanno ambiti distinti: SQL non prova da solo rinnovo o revoca tramite provider gestito.

## Database e privacy

I client non leggono/modificano direttamente events. RLS, grant minimi e RPC controllano identità, proprietà, ammissione, capienza e transizioni. Feed/inviti mascherano sede e pin privati prima dell’ammissione e dopo rimozione. Token casuali a 256 bit conservati solo come SHA-256.

La rilettura del catalogo non trova tabelle pubbliche applicative senza RLS, privilegi client sulle tabelle private o lettura client della coda push. Le sole RPC SECURITY DEFINER eseguibili da anon sono feed e anteprima invito. Le 43 eseguibili da authenticated devono mantenere i propri gate: il ruolo authenticated da solo non autorizza i dati.

Gli advisor segnalano 18 tabelle private senza policy (diniego intenzionale), RPC esposte e protezione password compromesse disabilitata. Non aprire tabelle o rimuovere controlli per azzerare gli avvisi. Il controllo del search path restituisce solo indicatori, senza estrarre configurazioni potenzialmente riservate. rls_auto_enable() appartiene alla base della piattaforma ed è distinta dalle routine applicative.

Quote limitano creazioni, richieste e operazioni ripetute; il ritiro volontario resta disponibile. L’assistenza candidata usa quote, idempotenza e anti-riuso transazionali, ma non è ancora attiva.

## Browser, cache ed export

Nel cloud il client ignora archivi demo e mantiene profilo/partite nel database. Sessione tecnica Auth distinta dai dati applicativi. Logout/cambio account puliscono console/modali e scartano risposte tardive. La gestione push è serializzata fra identità.

Il service worker conserva la sola shell pubblica, escludendo API, richieste autorizzate, no-store e chiavi con parametri. Le cache distribuite sono nel registro rilasci; quella dei sorgenti può essere diversa. Risposte riservate no-store.

L’export personale usa sessione viva e paginazione controllata; esclude token Auth/invito, impronte telefono e rubrica altrui. La richiesta di cancellazione attiva produce una pratica; l’esecuzione revisionata candidata è disabilitata e non applicata. [Cancellazione](ERASURE-REQUESTS.md).

## Job, pagamenti e notifiche

La retention eventi parte da conclusione/annullamento effettivi; il ciclo account dal primo match creato. Premium, report, vincoli, Storage e dati condivisi richiedono controlli prima di eliminare. Lifecycle, purge e job sono spenti.

Billing isola test/live, verifica firma sul corpo originale, gestisce duplicati e rilegge lo stato dal provider. Redirect, metadata e storage del browser non conferiscono Premium. Acquisti reali non attivati.

Push-dispatch v1 è pubblicato con PUSH_RELEASE_READY=false. Tre richieste HTTP gestite hanno restituito il 503 previsto. Il codice controlla autenticazione del job, coppia VAPID prima del claim, consenso/lease prima dell’invio, endpoint consentiti, timeout e retry. Nessun nuovo segreto, sottoscrizione, job o invio reale. Otto prove crypto/runtime non equivalgono a consegna su dispositivo.

## Segreti, dipendenze e recupero

Config.js è pubblico ed escluso da Git: solo opzioni pubbliche, URL e chiave publishable/anon. Service-role, token Management, OAuth, Stripe, VAPID privato, Turnstile e OTP restano nei servizi, mai in comandi condivisi, screenshot, log o checkpoint.

SDK/tool fissati con integrità/lock. Dispatcher con SDK npm ufficiale fissato; non aggirare frozen quando una risorsa cambia. I pacchetti escludono credenziali locali, Git, dipendenze installate e cartelle interne. Esporre solo public/, anche su Wi-Fi.

La CI verifica concorrenza e recupero SQL cifrato isolati. Backup completo del Supabase gestito ancora aperto; rollback frontend non ripristina dati. [Procedura](BACKUP-RESTORE-SETUP.md).

Restano TOTP/console reale, email/antiabuso, assistenza, automatismi/comunicazioni, recupero/cancellazione gestiti, altro dispositivo, informative e rilascio coordinato.
