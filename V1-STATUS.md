# Stato verificabile della V1.0 ONLINE

Aggiornato il 10 novembre 2026. La preview pubblica è **2.0.2**, non la V1.0 multiutente. I sorgenti successivi contengono il blocco di protezioni Admin e isolamento dei dati tra account, non ancora distribuito come nuova interfaccia pubblica. `onlineReady` e `pushReady` restano `false`.

## Decisioni confermate

- Accesso Google. Host e Sportivo sono contesti dello stesso account; Admin è un permesso assegnato dal server, mai una scelta di registrazione.
- Dati condivisi nel cloud. Nessuna scelta sessione/dispositivo nel flusso online; cache pubblica e sessione di autenticazione sono distinte dai match.
- Tutti gli account Free al lancio. L'account non scade; lo storico Free delle sessioni concluse o annullate scade sette giorni dopo la conclusione/annullamento effettivo. Premium futuro per conservazione estesa, senza pagamenti attivi.
- Niente SMS obbligatori per il percorso gratuito e nessun costo attivato. Occorre aggiornare i precedenti controlli telefono per farli coincidere con Google e con le regole di accesso della 1.0.
- Chat eliminate. Richieste, ammissioni e promemoria tramite notifiche; contatto Host solo con consenso.
- Restano eventi calcio 5/8/11, amichevoli e tornei, lista/mappa, inviti anche privati, PNG con logo e riferimento al sito. Il dominio acquistato viene dopo il collaudo sul dominio gratuito.

## Criteri finali: evidenza e stato

| Criterio dell'obiettivo | Classificazione | Evidenza / lavoro aperto |
| --- | --- | --- |
| URL pubblico HTTPS | VERIFICATA | Preview Cloudflare 2.0.2, 16 asset confrontati al deploy |
| Pacchetto/build | VERIFICATA per preview | CI ospitata e archivi 2.0.2; ricontrollare il nuovo blocco prima del suo rilascio |
| Autenticazione Google | MANCANTE | Impostazioni pubbliche Auth: `external.google=false`. Mancano credenziali provider, pulsante/redirect e adattamento del profilo |
| Profili persistenti | PARZIALE | Tabella e vecchio trigger email presenti; completamento del profilo OAuth da implementare |
| Ruoli distinti | PARZIALE | Host/Sportivo e controlli di proprietà presenti; allowlist Admin applicata e testata con fixture |
| Console riservata | PARZIALE | SQL + Edge v1 pubblicati; nessun account Admin reale ancora creato o testato |
| Navigazione per ruolo | IMPLEMENTATA, da verificare online | Interfaccia e controlli presenti; il backend resta l'autorità |
| Eventi cloud gestibili | PARZIALE | RPC applicate; flusso reale UI/account ancora non collaudato |
| Persistenza tra dispositivi | DA VERIFICARE | Nessun test completo con sessioni Auth reali |
| Partecipazioni/comunicazioni | PARZIALE | RPC e trigger notifiche presenti; consegna push e reminder da completare |
| Tutti Free | DA CORREGGERE | Nessun pagamento; adeguare vecchie regole Premium/telefono e testi |
| Scadenza automatica di sette giorni | MANCANTE | Mancano timestamp di conclusione/annullamento, strategia archiviazione/eliminazione con dipendenze, job e test |
| Sicurezza essenziale | PARZIALE | RLS, 21 gruppi SQL Admin, 24 scenari Edge e isolamento account verificati; OAuth/MFA reale, abuso e CSP da completare |
| Account distinti reali | DA VERIFICARE | Fixture SQL annullate non equivalgono a login reali |
| Smoke post-deploy V1.0 | MANCANTE | Eseguito per la preview e per il perimetro anonimo della funzione Admin, non per la V1.0 |
| Nessun blocco fondamentale | NON DIMOSTRATO | L'attivazione attuale di Google fallirebbe il vecchio trigger profilo: correggerlo prima dell'abilitazione |
| Infrastruttura gratuita | PARZIALE | Supabase/Cloudflare Free disponibili entro quote; verificare piano, consumo, limiti e recupero prima di utenti reali |
| Nessun pagamento non autorizzato | VERIFICATA per le operazioni svolte | Nessun piano a pagamento, SMS o dominio acquistato attivato |
| Documentazione aggiornata | PARZIALE | Questo stato, README, sicurezza e guida; allineare tutto alla V1.0 effettivamente distribuita |
| Recupero dei dati | PARZIALE | Nove migrazioni reali preservate; non è un backup dei dati. Ripristino completo non provato |

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
