# Stato verificabile della V1.0 ONLINE

Aggiornato il 10 novembre 2026. La preview pubblica è **2.0.2**, non la V1.0 multiutente. I sorgenti successivi contengono il blocco di protezioni Admin e isolamento dei dati tra account, non ancora distribuito come nuova interfaccia pubblica. `onlineReady` e `pushReady` restano `false`.

## Decisioni confermate

- Accesso Google. Host e Sportivo sono contesti dello stesso account; Admin è un permesso assegnato dal server, mai una scelta di registrazione.
- Dati condivisi nel cloud. Nessuna scelta sessione/dispositivo nel flusso online; cache pubblica e sessione di autenticazione sono distinte dai match.
- Tutti gli account Free al lancio. L'account non scade; lo storico Free delle sessioni concluse o annullate scade sette giorni dopo la conclusione/annullamento effettivo. Premium facoltativo a 4,99 EUR/anno aggiunto dal titolare; codice in sviluppo e pagamenti non attivi.
- Niente SMS obbligatori per il percorso gratuito e nessun costo attivato. Il nuovo percorso Google verificato e profilo completo abilita il gioco pubblico senza SMS. Il contatto telefonico richiede ancora la verifica del numero.
- Chat eliminate. Richieste, ammissioni e promemoria tramite notifiche; contatto Host solo con consenso.
- Restano eventi calcio 5/8/11, amichevoli e tornei, lista/mappa, inviti anche privati, PNG con logo e riferimento al sito. Il dominio acquistato viene dopo il collaudo sul dominio gratuito.

## Criteri finali: evidenza e stato

| Criterio dell'obiettivo | Classificazione | Evidenza / lavoro aperto |
| --- | --- | --- |
| URL pubblico HTTPS | VERIFICATA | Preview Cloudflare 2.0.2, 16 asset confrontati al deploy |
| Pacchetto/build | VERIFICATA per preview | CI ospitata e archivi 2.0.2; ricontrollare il nuovo blocco prima del suo rilascio |
| Autenticazione Google | PARZIALE | Client PKCE e profilo completati; progetto Google `trovat1o` e client `TROVAT1O Web - Supabase` creati. Chiave non ancora trasferita a Supabase; provider/login reale non attivi |
| Profili persistenti | IMPLEMENTATA, da verificare con Google reale | Completamento server del profilo applicato; 27 gruppi SQL combinati profilo/gioco con rollback e 16 scenari client passati |
| Ruoli distinti | PARZIALE | Host/Sportivo e controlli di proprietà presenti; allowlist Admin applicata e testata con fixture |
| Console riservata | PARZIALE | SQL + Edge v1 pubblicati; nessun account Admin reale ancora creato o testato |
| Navigazione per ruolo | IMPLEMENTATA, da verificare online | Interfaccia e controlli presenti; il backend resta l'autorità |
| Eventi cloud gestibili | PARZIALE | RPC applicate; flusso reale UI/account ancora non collaudato |
| Persistenza tra dispositivi | DA VERIFICARE | Nessun test completo con sessioni Auth reali |
| Partecipazioni/comunicazioni | PARZIALE | RPC e trigger notifiche presenti; consegna push e reminder da completare |
| Tutti Free | IMPLEMENTATA, collaudo reale aperto | Nuovi profili Free; acquisti disattivati. Billing test isolato dal piano reale. Storico e testi precedenti restano da riallineare alla retention |
| Scadenza automatica di sette giorni | MANCANTE | Mancano timestamp di conclusione/annullamento, strategia archiviazione/eliminazione con dipendenze, job e test |
| Sicurezza essenziale | PARZIALE | RLS, 21 gruppi SQL Admin, 24 scenari Edge e isolamento account verificati; OAuth/MFA reale, abuso e CSP da completare |
| Account distinti reali | DA VERIFICARE | Fixture SQL annullate non equivalgono a login reali |
| Smoke post-deploy V1.0 | MANCANTE | Eseguito per la preview e per il perimetro anonimo della funzione Admin, non per la V1.0 |
| Nessun blocco fondamentale | NON DIMOSTRATO | Trigger OAuth corretto e applicato; attivazione Google, ciclo di vita e prove reali rimangono gate aperti |
| Infrastruttura gratuita | PARZIALE | Supabase/Cloudflare Free disponibili entro quote; verificare piano, consumo, limiti e recupero prima di utenti reali |
| Nessun pagamento non autorizzato | VERIFICATA per le operazioni svolte | Nessun piano a pagamento, SMS o dominio acquistato attivato |
| Documentazione aggiornata | PARZIALE | Questo stato, README, sicurezza e guida; allineare tutto alla V1.0 effettivamente distribuita |
| Recupero dei dati | PARZIALE | Dodici migrazioni reali preservate; non è un backup dei dati. Ripristino completo non provato |

## Sequenza di ripresa

1. Conservare il blocco sicurezza in GitHub con CI verde e pacchetto completo. Non ripetere audit di prestazioni della preview senza modifiche pertinenti.
2. Completare il profilo dopo Google OAuth e i permessi del percorso gratuito. Configurare provider e redirect solo quando il codice è pronto; il titolare inserisce credenziali/codici nelle pagine del servizio, mai in chat.
3. Implementare politica Free di sette giorni dal termine effettivo, archiviazione, eventuali vincoli di sicurezza/legali, pulizia server e test temporali. Non cancellare account per scadenza match.
4. Collegare tutte le operazioni UI alle RPC e provare Host/Sportivo su browser separati, link privato, capienza, espulsione, riammissione e modifica evento.
5. Assegnare l'Admin all'identità confermata scelta dal titolare. Provare enrollment TOTP, accesso, scadenza, revoca, report e ticket senza consultazione indiscriminata dei dati personali.
6. Completare push, reminder, supporto, esportazione/cancellazione account, informative e backup/ripristino. Nessuna attivazione a pagamento.
7. Rilascio coordinato V1.0 e verifica online A-G dell'obiettivo, con risultati reali. Non confondere la preview locale con il servizio multiutente.

## Riferimenti

Obiettivo integrale conservato nell'allegato della chat; materiali `sources/` e PDF di riferimento non modificati. La tavola UI allegata è una guida di flusso, non un'autorizzazione ad attivare tutti i provider citati.

Quote ufficiali consultate: [Supabase](https://supabase.com/pricing), [Cloudflare Workers](https://developers.cloudflare.com/workers/platform/pricing/). Supabase Free include attualmente 50.000 utenti attivi mensili, database 500 MB, storage 1 GB e 5 GB egress; i progetti inattivi possono essere sospesi dopo una settimana. La sostenibilità iniziale a zero non significa risorse gratuite illimitate o backup gestiti equivalenti ai piani a pagamento.

## Checkpoint Google e Premium del 10 novembre 2026

Identità confermate: Admin app `lucente.work@gmail.com`; titolare Stripe `diegolucente2000@gmail.com`. Google Cloud è stato inizializzato dal titolare accettando i termini; progetto `trovat1o` creato e client OAuth `TROVAT1O Web - Supabase` visibile nella lista. Origine autorizzata: URL pubblico Cloudflare. Callback: `https://nrixslotansgrtrosaof.supabase.co/auth/v1/callback`. Il titolare ha autorizzato esplicitamente creazione e custodia della chiave in Supabase, ma il trasferimento non è ancora stato eseguito. Nessuna chiave OAuth è nei file o in chat. Il pannello Google resta aperto per la ripresa.

Google PKCE, completamento profilo, contesto invito e gate Google/telefono sono implementati nei sorgenti e applicati nel database. Sedici scenari OAuth client e ventisette gruppi SQL combinati passati. Il login reale è ancora da eseguire. Le migrazioni Google sono `20261110173318` e `20261110175601`.

Stripe ha confermato il conto `trovat10.app`; sandbox separata `TROVAT1O sviluppo` creata, ancora da autorizzare alla CLI. Billing server/client e webhook sono nei sorgenti; migrazione `20261110181941` applicata. Passati 38 scenari server, 10 client e 6 verifiche delle firme con SDK reale. Diciannove gruppi SQL passati nel dry-run con rollback; ripetizione sullo schema installato non eseguita per conferme del connettore scadute. Nessuna risorsa commerciale o transazione Stripe creata. Dettagli, limiti e ripresa in [BILLING-SETUP.md](BILLING-SETUP.md).

`onlineReady`, `billingReady` e `pushReady` restano `false`. Nessun nuovo deploy frontend: il sito pubblico rimane la preview 2.0.2. Nessuna stima percentuale equivale al superamento dei venti criteri sopra. Alla richiesta del titolare il lavoro viene messo in pausa dopo salvataggio, senza promessa di ripresa automatica.


## Stato alla ripresa dell’11 novembre 2026

- Migrazione reale `20261111025149_trovat1o_online_beta_operations` applicata al progetto `nrixslotansgrtrosaof`: contatto Host legato al numero verificato, ciclo di vita/storico, operazioni Admin, export dati, quote tecniche e API push con lease. Cron e consegna push non attivati. Tredici migrazioni effettive esportate.
- PostgreSQL locale: 12 sorgenti SQL e 11 regressioni completi con rollback dei dati sintetici. Auth/Google/MFA della fixture non costituiscono login reali; niente concorrenza multi-connessione o scheduler cloud provati.
- 20 suite Node correnti, comprese 6 prove del bootstrap reale delle librerie: corretto il vincolo CAPTCHA che impediva di caricare il client Supabase nel percorso solo Google. Supabase JS/Leaflet scaricati dai CDN e confrontati alle rispettive firme SRI: corrispondono. Sei test crittografici Stripe con SDK reale passati; TypeScript passato sui cinque endpoint candidati.
- Corretto il limite anti-abuso delle partecipazioni: quota sulle modifiche effettive AFTER INSERT/UPDATE per non addebitare due volte un UPSERT; ritiro della propria partecipazione sempre possibile.
- Endpoint nuovi e aggiornamento console Admin non ancora distribuiti. L’unica Edge operativa resta `admin-console` v1 precedente. Frontend pubblico ancora 2.0.2; nessun nuovo deploy o login Google reale. `onlineReady`, `billingReady`, `pushReady`, `exportReady` rimangono false nel candidato.
- Browser Google: permesso salvato nega l’accesso anche dopo consenso in chat; non aggirato. Client Google già creato nel progetto `trovat1o`. Credenziale non trasferita a Supabase.
- Browser Supabase: sessione osservata `lucente.work@gmail.com` vede organizzazione `Lucente` (`umqgaecwjmfdnwtuvwew`) e progetto `Trovato` (`nentyffgpuoiczdttzfu`), diversi dall’organizzazione del plug-in `lucente` (`thnqvzujtphdvpzemxuz`) e progetto autorizzato `TROVAt10` (`nrixslotansgrtrosaof`). Nessuna modifica al progetto sbagliato. Login corretto ancora da riallineare; titolare ha autorizzato termini/accesso con GitHub, ma l’ultima osservazione è nuovamente l’organizzazione del vecchio account.
- Stripe plug-in ora disponibile, espone soltanto il conto LIVE `acct_1PdoAhFoPhAyQ2Ya`; nessuna scrittura su quel conto. Sandbox `acct_1UaJJtFvMNykzCOW` già creata e ancora da autorizzare, non ricrearla. Acquisti e tasse non attivati.
- GitHub main rimane `b196b60a644bfe7e7ac12fd26e25650589bfee9c`: sorgenti correnti locali non ancora sincronizzati. Il CI verde precedente non verifica questo candidato. Il pacchetto locale viene rigenerato prima della consegna del riepilogo.

### Nuova decisione del titolare: durata account Free

Il titolare ha cambiato la precedente regola “l’account non scade”: il conteggio di sette giorni dell’account Free deve iniziare dalla creazione del suo PRIMO match. Un acquisto Premium confermato dal server esclude l’account dal processo. La nuova regola prevale sulle frasi precedenti di questo documento, ma NON è ancora implementata o attivata: la migrazione attuale riguarda lo storico dei match, non cancella account.

Alla ripresa preparare la nuova politica con timestamp server del primo match immutabile, controllo del piano reale, preavvisi e gestione delle dipendenze. Nessuna eliminazione cieca di eventi futuri, partecipanti, report o dati soggetti a conservazione. Il titolare delega la scelta prudente delle modalità operative; non servono ulteriori domande sui dettagli ordinari. Definire visibilità/account in scadenza, passaggio a Premium durante la finestra, errori/rimborsi, anonimizzazione e cancellazione Auth con prova di rollback/staging prima dell’abilitazione. Aggiornare consenso/condizioni/privacy e flusso di registrazione alla regola effettiva prima degli utenti reali. Non applicare la nuova scadenza ai soli partecipanti come se avessero creato un match: il trigger richiesto è la prima creazione.

Monitorare lo spazio e mantenere infrastruttura Free iniziale. Un eventuale aumento di spazio a pagamento richiede una decisione economica del titolare; non è autorizzato un upgrade automatico dalla sola discussione sulla crescita.
