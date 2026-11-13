# TROVAT1O

**Non perderti più una partita.** La prima versione aiuta a trovare e organizzare calcio amatoriale a 5, 8 e 11. La visione del marchio comprende attività più ampie.

## Versioni effettive - 13 novembre 2026

| Ambiente | Collegamento | Stato |
| --- | --- | --- |
| Collaudo cloud | https://v1-check-trovato.diegolucentedesign.workers.dev/ | `1.0.0-cloud-test.4`: Google, profilo e partite reali su Supabase; non è ancora un lancio pubblico definitivo |
| Sito principale | https://trovato.diegolucentedesign.workers.dev/ | `1.0.0-rc.1`: anteprima interattiva con dati locali |
| Sorgenti e pacchetto locale | Questo repository | Candidato aggiornato; i flag di attivazione sono disabilitati per impostazione predefinita |

Il collaudo è separato dal traffico del sito principale. Un caricamento con `wrangler versions upload` non è un rilascio in produzione. [V1-STATUS.md](V1-STATUS.md) registra i **25 criteri** del Master R3 e gli **11 scenari finali**. Non dichiarare la V1 completata prima di soddisfarli.

## Risultati verificati

- Google OAuth configurato sul progetto corretto `nrixslotansgrtrosaof`; primo profilo Host Free completato con le dichiarazioni esplicite del titolare. Nuovo login riuscito anche dopo la disattivazione della vecchia chiave Google.
- Due partite private di collaudo salvate nel database. Creazione, modifica, riapertura, annullamento e storico verificati nell'interfaccia. Nessuna prenotazione reale.
- Cambio Host/Sportivo persistente dopo ricaricamento e ritorno guidato a Host. Il ruolo operativo non attribuisce privilegi di piattaforma.
- Esportazione personale JSON scaricata con tutte le nove sezioni. PNG della partita scaricato e ispezionato: logo e sito presenti, luogo privato escluso anche dai metadata.
- **24 suite Node** superate; **15 moduli SQL e 14 regressioni** con rollback nel PostgreSQL locale. I test con trasporti o identità controllate non sostituiscono account Google distinti, MFA reale o concorrenza remota.
- Form verificato a 320, 390, 768 e 1440 pixel: nessun overflow orizzontale osservato nei contesti controllati, caratteri dei campi a 16 px.
- `admin-console` v4 e `host-contact` v1 pubblicate: origini HTTPS esatte e contesto per richiesta. Il secondo fattore Admin è ancora da attivare personalmente.

La precedente verifica della preview principale ha confrontato 17 asset e rifiutato cinque percorsi riservati. Non attribuirle implicitamente la prova dei flussi cloud.

## Avvio locale su Mac

Se manca la configurazione locale, creala dal modello:

```sh
cp config.example.js config.js
```

Non sovrascrivere una configurazione già predisposta. Dalla cartella principale:

```sh
bash scripts/package-release.sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory TROVAT1O-Cloudflare-Deploy/public
```

Apri http://127.0.0.1:4173 e ferma il server con `Ctrl+C`. Per la stessa Wi-Fi puoi usare `--bind 0.0.0.0` e l'IP del Mac; esponi esclusivamente la cartella pubblica. Non servire la root del progetto, i sorgenti SQL, i backup o il checkpoint. La configurazione locale predefinita resta una demo: non sincronizza partite fra dispositivi.

## Account, ruoli e dati

Il percorso Google già collaudato usa un'email verificata e il completamento esplicito del profilo. Non richiede SMS per giocare. Il telefono Host condiviso resta facoltativo, con verifica e consenso; il numero non è una rubrica pubblica.

**Email/password, conferma email, recupero password, SMTP personalizzato e Turnstile restano requisiti aperti del Master R3.** Non sono stati provati o attivati nel collaudo; `emailAuthEnabled` resta `false`. Non presentarli come disponibili.

Lo stesso account può passare da Sportivo a Host. Soltanto il creatore gestisce il proprio evento. L'Admin di piattaforma è autorizzato in una allowlist privata: sessione Auth viva, TOTP recente e controlli SQL sono indispensabili. L'email scritta nel browser, `user_metadata`, Free o Premium non concedono Admin. Il suggerimento server in `app_metadata` abilita solo la sonda dell'ingresso dedicato; non autorizza dati o azioni. Gli utenti ordinari non hanno una Console demo.

Nel flusso cloud non si sceglie tra sessione e dispositivo: profilo e partite sono nel database. Sessione tecnica Auth e cache di asset pubblici hanno funzioni diverse. Non usare il service worker come archivio di API private.

## Free, storico e acquisti

Tutti gli account creati partono Free. Con account verificato il limite è due eventi attivi. Per l'eventuale percorso privo di verifica consentita è prevista una partita privata ogni sette giorni.

Le due regole dei sette giorni sono distinte:

- **Account Free:** il conteggio richiesto parte dal primo match creato. Il modulo è applicato ma `enabled=false` e `purge_enabled=false`; nessun account è cancellato automaticamente. Premium verificato, Admin e vincoli su dati condivisi sono protetti.
- **Storico:** la finestra Free parte dalla conclusione o dall'annullamento effettivi. Il codice SQL è applicato; il job non è attivo.

Non attivare eliminazioni prima di backup/ripristino, comunicazioni, verifiche sui dati condivisi e percorso di gestione effettivo. Vedi [ACCOUNT-LIFECYCLE.md](ACCOUNT-LIFECYCLE.md) e [RETENTION-SETUP.md](RETENTION-SETUP.md).

Premium previsto a **€4,99/anno**, acquisti disabilitati. Checkout, portale e webhook sono predisposti; nessun pagamento live o acquisto è stato usato come test. Vedi [BILLING-SETUP.md](BILLING-SETUP.md).

## Privacy e assistenza

Il download personale è operativo nel collaudo. La richiesta autenticata di cancellazione entra nella coda protetta di assistenza: **una ricevuta di richiesta non significa accesso chiuso o dati cancellati**. Vedi [ERASURE-REQUESTS.md](ERASURE-REQUESTS.md).

La chiusura completa dell'account, i vincoli di conservazione e la cancellazione effettiva restano da completare. Anche il normale invio assistenza, i promemoria pianificati e le push richiedono ulteriore configurazione e prova. I contatti diretti del supporto sono indicati nell'app. Non dichiarare conclusi accordi con fornitori, informative o verifiche normative non eseguiti.

## Verifiche ripetibili

```sh
for test_file in tests/*.cjs; do node "$test_file"; done
```

Per rendere obbligatorio il motore PostgreSQL locale, usa le dipendenze esatte separate dall'app:

```sh
mkdir -p tmp/local-postgres
cp tests/fixtures/local-postgres/package.json tmp/local-postgres/package.json
cp tests/fixtures/local-postgres/package-lock.json tmp/local-postgres/package-lock.json
npm ci --prefix tmp/local-postgres --ignore-scripts --no-audit --no-fund
node tests/local-postgres.cjs --require-engine
```

PGlite usa PostgreSQL 18.6; il servizio ospitato usa PostgreSQL 17.11. Le fixture Auth/JWT/MFA non sono scambi con i provider reali. La CI ripete controlli Node, SQL obbligatorio, tipi Deno, firme Stripe e confezionamento, senza pubblicare o richiedere segreti.

**Il database remoto ora contiene un profilo reale. Non rieseguire i vecchi test remoti che richiedono un database vuoto.** Conservare i rollback e usare ambienti isolati per prove sintetiche.

## Sorgenti, rilascio e ripresa

Repository scelto: [Diegosh501/TROVAt10](https://github.com/Diegosh501/TROVAt10). Esiti correnti: [GitHub Actions](https://github.com/Diegosh501/TROVAt10/actions). Il verde di un vecchio commit non verifica nuove modifiche.

`config.js` è escluso da Git. Gli URL e le sole chiavi pubblicabili vanno nella configurazione pubblica. Segreti OAuth, Stripe, VAPID, token e chiavi privilegiate restano nei servizi autorizzati, mai nel codice client, in un ticket o nei log. Il collegamento GitHub-Supabase usato per configurare il servizio è stato revocato con consenso; il nuovo login alla console potrà richiedere di autorizzarlo di nuovo.

`scripts/package-release.sh` rigenera copie e archivi dai sorgenti e confronta gli ingressi. Il pacchetto locale comprende backend, test, documentazione e guida PDF. Configurazione del collaudo e checkpoint privato restano separati dai file pubblici. Seguire [DEPLOY-READINESS.md](DEPLOY-READINESS.md), [supabase/README.md](supabase/README.md), [ADMIN-SETUP.md](ADMIN-SETUP.md), [PUSH-SETUP.md](PUSH-SETUP.md) e [SECURITY.md](SECURITY.md).

Il dominio acquistato verrà collegato dopo il collaudo; il dominio gratuito è sufficiente per provarlo. Nessun piano a pagamento, SMS o acquisto è stato attivato in questa ripresa. Costi futuri e continuità dipendono dai limiti reali dei piani scelti.
