# TROVAT1O

**Non perderti più una partita.** La prima versione aiuta a trovare e organizzare calcio amatoriale a 5, 8 e 11. La visione del marchio comprende attività più ampie.

## Versioni effettive - 14 novembre 2026

| Ambiente | Collegamento | Stato |
| --- | --- | --- |
| Collaudo cloud | https://v1-check-trovato.diegolucentedesign.workers.dev/ | `1.0.0-cloud-test.11`: Google, profilo e partite reali su Supabase; non è ancora un lancio pubblico definitivo |
| Sito principale | https://trovato.diegolucentedesign.workers.dev/ | `1.0.0-rc.1`: anteprima interattiva con dati locali |
| Sorgenti e pacchetto locale | Questo repository | Candidato `1.0.0-rc.10`; i flag di attivazione sono disabilitati per impostazione predefinita |

Il collaudo è separato dal traffico del sito principale. Un caricamento con `wrangler versions upload` non è un rilascio in produzione. [V1-STATUS.md](V1-STATUS.md) registra i **25 criteri** del Master R3 e gli **11 scenari finali**. Non dichiarare la V1 completata prima di soddisfarli.

## Risultati verificati

- Due identità Google reali, due profili separati Free; consenso Google in produzione. Host e Sportivo condividono lo stesso modello di account; l’Admin rimane una diversa autorizzazione server.
- Quattro partite di collaudo persistenti. Flusso pubblico provato: creazione → ricerca → richiesta → ammissione → avvio → conclusione → storico ritrovato dallo Sportivo dopo un nuovo accesso. Nessuna prenotazione reale.
- Invito privato copiato e riaperto prima del login; ritorno da Google allo stesso evento. Sede mascherata prima dell’ammissione e dopo rimozione. Una nuova richiesta non riammette automaticamente.
- Esportazione personale JSON con nove sezioni e PNG scaricati. Logo e sito nei metadata; sede privata, nomi e token esclusi dal PNG privato.
- **29 suite Node; 17 moduli SQL e 17 regressioni locali.** **11/11 controlli backend reali come Sportivo e 11/11 come Host ordinario**. La sonda del titolare riceve `mfa_required` sia da SQL sia da Edge. La console completa richiede il TOTP personale, rinviato dal titolare.
- Larghezze controllate: 320, 390, 768 e 1440 px; campi a 16 px e azioni profilo dentro i bordi. Non è una garanzia su ogni dispositivo.
- `admin-console` v4 e `host-contact` v1 pubblicate; 17 migrazioni sul progetto corretto. La correzione degli avvisi distingue avvio, conclusione, annullamento e cambio dei dettagli.
- **15/25 criteri V1 verificati nel collaudo; 4/11 scenari finali chiusi (A, B, D, H)**. Le cifre misurano criteri verificati, non tempo residuo o percentuale di codice. La V1 completa non è ancora rilasciata sul principale.

La riservatezza dei pin è stata provata con coordinate presenti: **33/33 controlli reali** nei cinque stati creatore, pending, ammesso, rimosso e anonimo. Il backend nasconde sede, coordinate e roster quando non consentiti.

**Assistenza:** il modulo sicuro ha 17 prove dell’handler, 14 della UI e una regressione SQL dedicata. È ancora disattivato: migrazione remota in attesa di conferma tecnica e widget Turnstile reale da configurare. La UI propone l’email invece di un invio non operativo. La libreria CAPTCHA è separata dal caricamento Google. Vedi [SUPPORT-SETUP.md](SUPPORT-SETUP.md).

Il collaudo ha controlli HTTPS, asset e percorsi riservati propri. Non attribuirgli la pubblicazione coordinata della V1 sul principale.

**Caricamento e uscita:** il collaudo mostra uno stato di attesa fino alla prima risposta cloud, gestisce errore e ripristino della rete e impedisce accessi concorrenti mentre la disconnessione è in corso. Otto regressioni mirate e prova browser con rete lenta/offline riuscite. Sei prove HTTP simultanee con 18 operazioni hanno rispettato limite Free, unicità delle richieste, rientro, avvio e conclusione. La contesa dell’ultimo posto fra due giocatori distinti è provata nel PostgreSQL nativo isolato, non con due Sportivi Google nel servizio.

**Notifiche, candidato rc.10:** corretta l’importazione ESM che impediva l’avvio del dispatcher e aggiunta verifica della coppia VAPID prima di prendere messaggi. 19 casi del gestore e otto prove con libreria/cifratura reali, senza consegna o chiavi persistenti. Pubblicazione del nuovo endpoint rifiutata dalla revisione automatica in attesa di consenso specifico: push e job restano spenti. [Dettagli e comandi](PUSH-SETUP.md).

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

La condivisione apre un pannello con **Copia invito** sempre disponibile. La condivisione nativa è un’azione separata e non blocca la copia. Un token privato corrente viene preservato nei refresh della stessa sessione in memoria; dopo un nuovo accesso, generarne uno nuovo sostituisce il precedente e la UI lo avverte. Gli inviti non sono archiviati nei dati demo o nell’export personale.

## Free, storico e acquisti

Tutti gli account creati partono Free. Con account verificato il limite è due eventi attivi. Per l'eventuale percorso privo di verifica consentita è prevista una partita privata ogni sette giorni.

Le due regole dei sette giorni sono distinte:

- **Account Free:** il conteggio richiesto parte dal primo match creato. Il modulo è applicato ma `enabled=false` e `purge_enabled=false`; nessun account è cancellato automaticamente. Premium verificato, Admin e vincoli su dati condivisi sono protetti.
- **Storico:** la finestra Free parte dalla conclusione o dall'annullamento effettivi. Il codice SQL è applicato; il job non è attivo.

Non attivare eliminazioni prima di backup/ripristino, comunicazioni, verifiche sui dati condivisi e percorso di gestione effettivo. Vedi [ACCOUNT-LIFECYCLE.md](ACCOUNT-LIFECYCLE.md) e [RETENTION-SETUP.md](RETENTION-SETUP.md).

Premium previsto a **€4,99/anno**, acquisti disabilitati. Checkout, portale e webhook sono predisposti; nessun pagamento live o acquisto è stato usato come test. Vedi [BILLING-SETUP.md](BILLING-SETUP.md).

## Privacy e assistenza

Il download personale è operativo nel collaudo. La richiesta autenticata di cancellazione entra nella coda protetta di assistenza: **una ricevuta di richiesta non significa accesso chiuso o dati cancellati**. Vedi [ERASURE-REQUESTS.md](ERASURE-REQUESTS.md).

Il candidato rc.9 integra un percorso di cancellazione revisionata, ancora disabilitato e non applicato al cloud: identità recente dell’utente, TOTP Admin, verifica dei vincoli, codice temporaneo e ricevuta veritiera. Le prove locali con dati sintetici non sostituiscono il collaudo Auth/Storage del servizio gestito o l’autorizzazione a cancellare un account reale. Anche il normale invio assistenza, i promemoria pianificati e le push richiedono ulteriore configurazione e prova. I contatti diretti del supporto sono indicati nell'app. Non dichiarare conclusi accordi con fornitori, informative o verifiche normative non eseguiti.

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

**Il database remoto ora contiene due account e due profili reali. Non rieseguire i vecchi test remoti che richiedono un database vuoto.** Conservare i rollback e usare ambienti isolati per prove sintetiche.

## Sorgenti, rilascio e ripresa

Repository scelto: [Diegosh501/TROVAt10](https://github.com/Diegosh501/TROVAt10). Esiti correnti: [GitHub Actions](https://github.com/Diegosh501/TROVAt10/actions). Il verde di un vecchio commit non verifica nuove modifiche.

`config.js` è escluso da Git. Gli URL e le sole chiavi pubblicabili vanno nella configurazione pubblica. Segreti OAuth, Stripe, VAPID, token e chiavi privilegiate restano nei servizi autorizzati, mai nel codice client, in un ticket o nei log. Il collegamento GitHub-Supabase usato per configurare il servizio è stato revocato con consenso; il nuovo login alla console potrà richiedere di autorizzarlo di nuovo.

`scripts/package-release.sh` rigenera copie e archivi dai sorgenti e confronta gli ingressi. Il pacchetto locale comprende backend, test, documentazione e guida PDF. Configurazione del collaudo e checkpoint privato restano separati dai file pubblici. Seguire [DEPLOY-READINESS.md](DEPLOY-READINESS.md), [supabase/README.md](supabase/README.md), [ADMIN-SETUP.md](ADMIN-SETUP.md), [PUSH-SETUP.md](PUSH-SETUP.md) e [SECURITY.md](SECURITY.md).

Il dominio acquistato verrà collegato dopo il collaudo; il dominio gratuito è sufficiente per provarlo. Nessun piano a pagamento, SMS o acquisto è stato attivato in questa ripresa. Costi futuri e continuità dipendono dai limiti reali dei piani scelti.

## Prove di concorrenza e recupero

Il percorso PostgreSQL nativo usa un servizio isolato nei controlli GitHub, con dati sintetici e immagine ufficiale bloccata. Le prove forzano connessioni realmente sovrapposte e ripristinano un dump cifrato in un secondo database. Il risultato del run corrente resta la prova autorevole: non equivale a un recupero completo di Supabase gestito o a un test HTTP sul servizio. Istruzioni e cifratura privata: [BACKUP-RESTORE-SETUP.md](BACKUP-RESTORE-SETUP.md).

**Prove PostgreSQL native aggiuntive:** [run verificato](https://github.com/Diegosh501/TROVAt10/actions/runs/43481338497), PostgreSQL 17.11 isolato: 17 migrazioni registrate riprodotte, 16 regressioni, nove scenari realmente concorrenti e dump cifrato ripristinato in un secondo database. Confrontati dati e sicurezza di 42 tabelle, 42 policy, 96 funzioni, 177 vincoli, 11 trigger, 84 indici e quattro sequenze. Quattro modifiche negative ai permessi/RLS vengono rilevate; sei guardie locali e quattro sonde native proteggono l’isolamento. Le otto prove di cifratura passano. Auth resta un fixture e non è stato eseguito un recupero completo del progetto Supabase reale. [Procedura backup](BACKUP-RESTORE-SETUP.md).

