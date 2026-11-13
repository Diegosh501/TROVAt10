# V1.0 ONLINE - stato verificabile

Aggiornato il 13 novembre 2026. Questo documento sostituisce le vecchie percentuali dei checkpoint. Il Master corrente comprende **25 criteri e 11 scenari finali** A-I, L, M.

## Versioni

- **Collaudo cloud reale:** https://v1-check-trovato.diegolucentedesign.workers.dev/ - `1.0.0-cloud-test.4`, Cloudflare `d775cc22-ab21-406e-ab37-7e7fd15a7db1`.
- **Sito principale:** https://trovato.diegolucentedesign.workers.dev/ - `1.0.0-rc.1`, Cloudflare `959a4c70-a070-4ee8-aa21-b306260b3165`. Resta l'anteprima con dati locali.
- **Supabase:** `nrixslotansgrtrosaof`, 16 migrazioni. Un account reale, un profilo e due eventi privati di collaudo: uno programmato, uno annullato.
- **Server pubblicati:** `admin-console` v4, `host-contact` v1. Le altre funzioni necessarie devono essere configurate e provate prima dell'apertura definitiva.

Il collaudo usa dati reali persistenti. Non è una demo locale, ma non costituisce ancora la V1 finale aperta al pubblico.

## Barre basate sulle prove

| Verifica | Risultato | Cosa dimostra |
| --- | --- | --- |
| Suite Node | `██████████` 24/24 | Controlli del codice e funzioni con trasporti controllati |
| Moduli SQL locali | `██████████` 15/15 | Applicazione dei moduli nel PostgreSQL locale |
| Regressioni SQL | `██████████` 14/14 | Policy e transizioni su fixture con rollback |
| Login Google e profilo | `██████████` 1 identità reale verificata | Accesso, consenso e persistenza del profilo del titolare |
| Azioni reali cloud mirate | `██████████` 17/17 osservate | Creazione, modifica, limiti, storico, ruolo, export e PNG sullo stesso account |
| Scenari finali del Master | `░░░░░░░░░░` 0/11 interamente chiusi | Servono ancora prove multiutente, MFA, job e ripristino |

Le 17 azioni mirate sono state eseguite sul collaudo cloud-test.2; sul successivo cloud-test.4 sono stati riprovati salvataggio, Organizza, etichette e tutte le azioni del profilo a quattro larghezze. Le regressioni automatiche coprono le correzioni intermedie. Queste barre non si sommano in una percentuale generale. Una suite SQL o una singola azione riuscita non chiude uno scenario completo e non certifica l'assenza di vulnerabilità.

## I 25 criteri della V1

VERIFICATO indica l'ambito effettivamente provato nel collaudo o nella ripresa. Non anticipa il rilascio sul sito principale.

| # | Criterio | Stato attuale | Evidenza e parte residua |
| --- | --- | --- | --- |
| 1 | Servizio raggiungibile | VERIFICATO | URL HTTPS di collaudo raggiunto e usato realmente; principale ancora preview |
| 2 | Release identificabile | VERIFICATO | Versioni Cloudflare e release pubbliche distinte; nuovo candidato da sincronizzare nel rilascio successivo |
| 3 | Autenticazione reale | PARZIALE | Google funziona; percorso email/password, SMTP, conferma e recupero ancora aperti nel Master |
| 4 | Google OAuth | VERIFICATO | Login reale anche dopo revoca della vecchia chiave; nuova credenziale custodita in Supabase |
| 5 | Profili persistenti | VERIFICATO | Profilo del titolare ritrovato dopo ricaricamento e nuovo accesso |
| 6 | Assegnazione ruoli | VERIFICATO | Host/Sportivo cambiati sul server e persistenti; Admin assegnato separatamente e non selezionabile |
| 7 | Dashboard Admin protetta | PARZIALE | Allowlist e gate backend operativi; TOTP personale rinviato dal titolare, metriche reali non ancora aperte |
| 8 | Flussi Host/Sportivo | PARZIALE | Creazione, modifica, annullamento e cambio ruolo reali; richiesta/ammissione fra due persone ancora da provare |
| 9 | Partite nel cloud | VERIFICATO | Due partite private nel DB, una annullata nello storico; persistenza dopo nuovo login |
| 10 | Partecipazioni | PARZIALE | SQL/RPC e quote testati; scambio reale Host/Sportivo mancante |
| 11 | Inviti e privacy | PARZIALE | PNG privato ispezionato senza sede, nomi o token; invito fra utenti distinti ancora da collaudare |
| 12 | Comunicazioni necessarie | PARZIALE | Avvisi e preferenze SQL presenti; normale assistenza, push e promemoria pianificati non completati |
| 13 | Persistenza fra dispositivi | DA VERIFICARE | Nuovo accesso nello stesso browser riuscito; non vale come altro account/dispositivo |
| 14 | Tutti iniziano Free | VERIFICATO | Profilo reale Free, default server controllato; acquisti ancora spenti |
| 15 | Retention sette giorni | PARZIALE | Moduli e regressioni presenti; job spenti e nessuna cancellazione automatica attiva |
| 16 | Funzioni server necessarie | PARZIALE | Admin e contatto Host pubblicate; perimetro restante ancora da configurare |
| 17 | Permessi backend | PARZIALE | RLS, caller/sessione, CORS e rifiuto anonimo testati; prove reali su ruoli ordinari distinti mancanti |
| 18 | Test multiutente | DA VERIFICARE | Una sola identità reale; fixture non sostituiscono il test |
| 19 | Nessun blocco conosciuto | NON DIMOSTRATO | Configurazioni e flussi residui aperti; race del salvataggio corretta nel candidato, con regressioni su risposte differite; altri gate restano aperti |
| 20 | Limiti economici | VERIFICATO | Nessun piano comprato, SMS inviato o pagamento reale; dominio acquistato rinviato |
| 21 | Backup/ripristino/rollback | PARZIALE | Sorgenti/migrazioni e versione hosting precedente conservati; recupero completo dei dati non provato |
| 22 | Informative adeguate | PARZIALE | Pagine versionate e consenso profilo acquisito; verifiche su servizi attivi, accordi e cancellazione effettiva aperte |
| 23 | Controlli post-deploy | DA ESEGUIRE | Collaudo cloud separato provato; nessun post-deploy della V1 completa sul principale |
| 24 | Documentazione | VERIFICATO | README e stato correnti aggiornati, limiti espliciti; ricevute del commit/CI e guida nel pacchetto di ripresa |
| 25 | Checkpoint riutilizzabile | VERIFICATO | File privati di ripresa, versioni e punti aperti conservati; non distribuire il checkpoint come sito |

## Scenari finali: prove ancora da chiudere

| Scenario | Prova fatta | Mancanza determinante |
| --- | --- | --- |
| A - Sportivo | Google, profilo, ruolo, ricerca e riapertura sul titolare | Richiesta e stato partecipazione con altro utente reale |
| B - Host | Due creazioni private, modifica, limite Free, annullamento e storico | Pubblicazione, richieste/ammissioni reali e conclusione con partecipanti |
| C - Admin | Allowlist, sessione viva, ingresso dedicato dopo sonda qualificata | Enrollment TOTP personale e uso reale della console |
| D - Permessi | RPC/RLS, sessione revocata e metadata falsi in test | Host e Sportivo distinti contro backend reale |
| E - Persistenza | Match e ruolo dopo ricaricamento e nuovo Google login | Altro account e altro dispositivo |
| F - Retention | Regressioni SQL a sette giorni e vincoli | Job reale in ambiente approvato e risultato operativo |
| G - Errori | Campi vuoti rifiutati; suite su sessioni, rete e risposte tardive | Collaudo reale completo dei servizi; race osservata corretta e coperta da regressioni |
| H - Privacy | Sede privata assente dal feed; PNG e metadata senza sede esatta | Scenari reali anonimo/estraneo/pending/ammesso/rimosso |
| I - Concorrenza | Serializzazione progettata e fixture | Richieste HTTP realmente simultanee, capienza e transizioni |
| L - Ripristino | Versione precedente e sorgenti conservati | Backup dati e ripristino integrale provati |
| M - Produzione | HTTPS, asset e percorsi riservati della preview controllati | Rilascio coordinato V1 e smoke sul medesimo URL principale |

## Configurazioni e sicurezza

Google usa il client esistente e il callback del solo progetto corretto. Redirect di collaudo esatto, niente wildcard. Nonce checks attivi e email verificata richiesta. Collegamento di configurazione GitHub-Supabase revocato e chiave Google precedente disattivata con consenso specifico. Nuovo login dell'app verificato dopo queste operazioni. Nessun token o segreto è incluso nel pacchetto.

L'account Admin è del titolare già indicato. Il secondo fattore non è stato creato o simulato; il titolare ha scelto di farlo più tardi. Una password storica in chat non è una credenziale da riutilizzare.

`onlineReady`, `exportReady` ed `erasureRequestsReady` sono veri solo nel collaudo. Email/password, Billing, push e ciclo account restano spenti. La configurazione di default dei sorgenti resta preview. Il modulo di cancellazione registra una pratica, non chiude accesso o dati: [ERASURE-REQUESTS.md](ERASURE-REQUESTS.md).

Non eseguire più i vecchi test remoti che esigono zero utenti: ora il titolare ha un account reale. Per prove sintetiche usare isolamento e rollback; le fixture locali non dimostrano backup o autenticazione reale.

## Ordine di completamento

1. Integrare le correzioni minime, sincronizzare GitHub e verificare CI e pacchetti senza segreti.
2. Completare personalmente il TOTP e collaudare la console; provare gli altri account/dispositivi senza inventare identità Google.
3. Configurare i percorsi del Master ancora aperti: email/SMTP/anti-abuso, assistenza, comunicazioni, job e cancellazione effettiva. Gli acquisti restano facoltativi e spenti fino a prove autorizzate.
4. Provare concorrenza, retention e ripristino in sicurezza; adeguare le informative ai servizi effettivi.
5. Solo dopo il superamento dei gate, pubblicare una release coordinata sul principale e chiudere lo scenario M.

Il dominio personalizzato non è un requisito del collaudo gratuito e non equivale all'ultima percentuale mancante dell'intero progetto. V2 PUBLIC BETA, V3 STABLE e V4 COMPLETE PLATFORM restano milestone successive alla V1.
