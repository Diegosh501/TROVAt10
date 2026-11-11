# TROVAT1O · rilascio e readiness

Aggiornato il 10 novembre 2026. Questo documento distingue la preview pubblica gratuita dal servizio multiutente.

## Preview pubblica

- **Indirizzo:** [trovato.diegolucentedesign.workers.dev](https://trovato.diegolucentedesign.workers.dev/)
- **Hosting:** Cloudflare Workers con asset statici; non serve acquistare un dominio.
- **Modalità:** preview interattiva senza login cloud. Account di prova, eventi, preferenze e notifiche restano sul dispositivo/browser.
- **Privacy:** `robots.txt` scoraggia l’indicizzazione, ma il link è pubblico e non è protetto da password. Non usare dati reali.
- **Stato del pacchetto:** la release iniziale V2 è stata pubblicata con versione Cloudflare 9dbc71ac-657a-4102-bfc3-7d2c8b547d12. Il successivo aggiornamento correttivo usa la cartella `TROVAT1O-Cloudflare-Deploy/public/`.

## Stato Supabase reale

Il progetto `TROVAT1O` (`nrixslotansgrtrosaof`, regione EU Central) contiene ora lo schema V2 e le policy. Il database applicativo è ancora vuoto; nessun account o evento reale è stato creato. Le verifiche hanno confermato che `anon` e `authenticated` non possono leggere o aggiornare direttamente la tabella `events`; il client può consultare solo il feed che nasconde la sede privata e può effettuare modifiche attraverso RPC con controllo del proprietario.

Al controllo successivo alle migration:

- RLS è attiva sulle tabelle applicative; supporto, OTP e numeri verificati hanno anche policy esplicite di diniego per i client.
- L’advisor Health non ha segnalato problemi.
- Gli avvisi di sicurezza residui sono sui RPC `SECURITY DEFINER` necessari per il feed pubblico, gli inviti e le operazioni autenticate. Ogni funzione imposta un search path sicuro e verifica ruolo/utente; restano da provare con sessioni online distinte.
- Gli avvisi performance riguardano indici inutilizzati in un database senza righe; non risultano chiavi esterne prive di indice.
- La funzione `admin-console` v1 è pubblicata; il frontend resta con `onlineReady: false`. Billing, supporto e OTP non sono distribuiti.

Il fatto che lo schema sia applicato **non significa che l’app multiutente sia online**. Mancano configurazione dei provider, distribuzione delle funzioni e prove reali con account separati.

## Passaggi che bloccano gli account online

1. Configurare SMTP personalizzato in Supabase Auth per conferma email e recupero password. L’invio email standard di Supabase non è adatto a utenti pubblici.
2. Configurare Turnstile e gli URL HTTPS/redirect definitivi per il dominio `workers.dev` scelto o, più avanti, per il dominio acquistato.
3. Pubblicare e provare `admin-console` e `support-request`. Pubblicare `phone-otp-start` e `phone-otp-verify` solo se si attiva Twilio Verify; SMS può avere costi.
4. Caricare le impostazioni Supabase pubblicabili e i segreti esclusivamente nelle rispettive impostazioni sicure. Non inserire service-role, segreti CAPTCHA/Twilio o Stripe nel sito o nel repository.
5. Eseguire prove con anonimo, Host, Sportivo, Host non verificato, utenti ammessi e non ammessi: signup, conferma email, login/recovery, creazione, invito privato, accesso, approvazione, capienza, annullamento, sede privata, segnalazione e cancellazione/esportazione account.
6. Implementare e testare consegna push/reminder in background, retention e cleanup delle righe temporanee. La coda SQL non invia da sola notifiche.
7. Aggiornare informative e consensi con provider, tempi di conservazione e flussi attivi prima di raccogliere dati reali.
8. Solo dopo questi passaggi abilitare `onlineReady: true` e pubblicare una versione beta multiutente.

Non è necessario limitare gli account a Gmail, Google, Apple o Meta: la protezione richiesta è conferma email più policy server-side, limiti e verifiche anti-abuso. L’accesso social non è configurato.

## Test locali già eseguiti

I controlli in `tests/` coprono smoke UI, flussi UX, responsive, brand PNG, collegamenti e handler, regole di sicurezza e integrazione del client con le RPC. Sono controlli sul codice, non prove d’identità o di concorrenza su utenti cloud reali. L’app è stata anche controllata nel browser per i flussi locali e l’export PNG nella versione precedente del rilascio.

## Pubblicare la preview aggiornata

La cartella Cloudflare contiene solo i file statici in `public/`. Dalla root sincronizza preview e archivi con `bash scripts/package-release.sh`, poi pubblica:

```sh
cd "/Users/claudia/.codex/.chatgpt-projects/g-p-6ad372b660b0819189c0e8409c915b87/TROVAT1O-Cloudflare-Deploy"
npm ci
npx wrangler deploy
```

Il rilascio è una preview offline, perché il cloud è spento in `config.js`. Verificare il sito su `workers.dev` dopo la pubblicazione; l’esito del deploy non prova signup o sincronizzazione Supabase.

## Dominio personalizzato in seguito

`trovat10.app` si può collegare dopo l’acquisto con DNS e HTTPS. Poi aggiornare URL pubblici, redirect Auth, metadata dell’infografica, CORS e informative. Il dominio non è necessario per pubblicare o provare la preview gratuita.

## Avvio locale su Mac

```sh
cd "/Users/claudia/.codex/.chatgpt-projects/g-p-6ad372b660b0819189c0e8409c915b87"
python3 -m http.server 4173 --bind 127.0.0.1
```

Apri `http://127.0.0.1:4173`; arresta il server con `Ctrl+C`. Per accesso da altri dispositivi Wi-Fi serve usare l’indirizzo di rete locale del Mac e autorizzare il firewall.

## Esiti aggiornati dell’audit

Il rapporto completo è [AUDIT-PREDEPLOY.md](AUDIT-PREDEPLOY.md). Sono stati corretti rientro dopo rimozione, visibilità delle richieste ai partecipanti, recupero password, gestione CAPTCHA, focus e pulsanti duplicati, mappa e pacchetti. Il test SQL autorizzato con utenti sintetici ha eseguito tutte le asserzioni senza errori e il rollback: al controllo successivo utenti/eventi/partecipazioni sono tornati a zero. Queste prove non verificano la consegna SMTP/SMS né sessioni Auth reali.


## Ultimo rilascio2.0.2

Worker 79bbea69-3511-400e-8603-5de3c9acacdb pubblicato;16 asset pubblici confrontati. LCP 2,142 s e CLS 0 nella prova Lighthouse mobile; INP 120 ms nella sessione con CPU 4×. Offline reale Chrome verificato. Questi risultati riguardano la preview: i blocchi degli account online elencati sopra restano aperti. Repository sorgente ufficiale scelto: https://github.com/Diegosh501/TROVAt10 .

## Checkpoint successivo Google / Billing

Il percorso primario è Google, non il precedente signup email obbligatorio. Il codice OAuth e il completamento profilo sono pronti e applicati; progetto Google e client web creati, trasferimento della chiave, redirect Supabase e login reale ancora da completare. Email/password richiederebbe separatamente SMTP/Turnstile. I gate del gioco riconoscono Google verificato, senza SMS obbligatorio.

Billing è disattivato: vedere `BILLING-SETUP.md` per i test effettivi e le dipendenze aperte. Dodici migrazioni registrate, non un backup. Lo stato che prevale sui vecchi elenchi è `V1-STATUS.md`. Non pubblicare il candidato come piattaforma multiutente prima di collaudo Google, retention, notifiche e account distinti.
