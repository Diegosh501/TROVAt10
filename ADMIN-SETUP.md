# TROVAT1O · console amministrativa e assistenza

## Modalità offline

Apri `index.html` e seleziona “Console · demo” dal menu per consultare la snapshot offline. I valori e i ticket sono inventati; le modifiche sono solo in memoria e si azzerano al ricaricamento. Quando `onlineReady` sarà attivo, la voce Console sarà mostrata solo a un account con ruolo amministrativo.

## Provisioning online

1. Crea e conferma un account personale con email/password nel progetto Supabase di staging. Cambia prima ogni password eventualmente condivisa in precedenza o riutilizzata.
2. Imposta `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` e `TROVAT1O_ADMIN_EMAIL` nell’ambiente privato e avvia `node scripts/promote-admin.mjs`. Lo script cerca solo quell’email, rifiuta account non confermati e assegna `app_metadata.role=admin`. Non inserire chiavi o password nel codice, nel browser o negli argomenti CLI.
3. Attiva MFA TOTP nell’account. Le funzioni server verificano ruolo admin e livello MFA `aal2` su ogni richiesta.
4. Applica `supabase/schema.sql` solo in un progetto di staging vuoto, controlla RLS e distribuisci `admin-console` e `support-request` con `APP_ORIGIN` impostato all’origine HTTPS esatta, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` e `TURNSTILE_SECRET_KEY` dove previsto.
5. Per usage/carico, crea un token Supabase Management con solo il permesso di lettura analytics disponibile nel progetto e configura `SUPABASE_MANAGEMENT_API_TOKEN` e `SUPABASE_PROJECT_REF` come segreti server. Senza questi parametri la console indica che il dato non è disponibile. Conteggi Usage/Analytics sono intervalli misurati dal provider, non CPU live né una previsione.
6. Configura `config.js` con URL, anon key, origine HTTPS e CAPTCHA pubblica. Attiva `onlineReady` solo dopo aver provato in staging accessi, MFA, RLS, supporto e metriche.

## Privacy e supporto

La dashboard non offre una rubrica utenti e restituisce solo conteggi aggregati. Il ticket non collega l’account per default. Il contatto nominativo/email viene raccolto solo se chi invia sceglie il ricontatto; il collegamento account è un consenso separato. La ricerca dei ticket è limitata ai 50 risultati più recenti/ordinati. Le modifiche hanno un registro di audit e non c’è cancellazione dalla console.

I recapiti mostrati nel prodotto sono quelli forniti dal titolare: `support.trovat10@gmail.com` e `389564728222`; verificare proprietà e formattazione prima di una pubblicazione pubblica. Le bozze legali esistenti vanno completate e revisionate prima di raccogliere dati reali.

## Limiti attuali

Questo è scaffolding, non un servizio pubblicato: non crea l’account amministratore, non attiva Supabase, non configura SMTP/CAPTCHA/MFA, non verifica login reale/MFA o invio del supporto e non attiva telemetria. La visibilità condizionale della sezione non costituisce controllo di accesso; lo applica il backend.

Schema base, policy e tabelle notifiche sono stati applicati al progetto pre-lancio; i test SQL autorizzati sono descritti in AUDIT-PREDEPLOY.md. Le Edge Functions amministrative restano da distribuire e configurare.
