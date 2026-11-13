# V1.0 ONLINE - stato verificabile

Aggiornato il 13 novembre 2026. Questo documento sostituisce le vecchie percentuali dei checkpoint. Il Master corrente comprende **25 criteri e 11 scenari finali** A-I, L, M.

## Versioni

- **Collaudo cloud reale:** https://v1-check-trovato.diegolucentedesign.workers.dev/ - `1.0.0-cloud-test.10`, Cloudflare `8ac772c9-508b-47db-8487-14b9d0946a2d`.
- **Sito principale:** https://trovato.diegolucentedesign.workers.dev/ - `1.0.0-rc.1`, Cloudflare `959a4c70-a070-4ee8-aa21-b306260b3165`. Resta l'anteprima con dati locali.
- **Supabase:** `nrixslotansgrtrosaof`, 17 migrazioni. Due account Google reali, due profili Free e tre eventi di collaudo: un privato programmato, un privato annullato e un pubblico concluso.
- **Server pubblicati:** `admin-console` v4, `host-contact` v1. Le altre funzioni necessarie devono essere configurate e provate prima dell'apertura definitiva.

Il collaudo usa dati reali persistenti. Non è una demo locale, ma non costituisce ancora la V1 finale aperta al pubblico.

## Barre basate sulle prove

| Verifica | Risultato | Cosa dimostra |
| --- | --- | --- |
| Suite Node | `██████████` 27/27 | Controlli del codice e funzioni con trasporti controllati |
| Moduli SQL locali | `██████████` 16/16 | Applicazione dei moduli nel PostgreSQL locale |
| Regressioni SQL | `██████████` 16/16 | Policy e transizioni su fixture con rollback |
| Login Google e profilo | `██████████` 2 identità reali verificate | Accesso, consenso, Free e profili separati |
| Azioni reali cloud mirate | `██████████` 17/17 osservate | Creazione, modifica, limiti, storico, ruolo, export e PNG sullo stesso account |
| Scenari finali del Master | `████░░░░░░` 4/11 interamente chiusi | Chiusi A, B, D e H; MFA, altro dispositivo, job e ripristino aperti |

La base comprende 17 azioni mirate su cloud-test.2 e il controllo a quattro larghezze su cloud-test.4. Le prove successive chiudono i flussi pubblici fra due Google reali, gli inviti privati e le richieste dirette al backend: 11/11 verifiche con Sportivo e 11/11 con Host ordinario. Il titolare riceve mfa_required da SQL e Edge. Su cloud-test.10 sono superati anche 33 controlli del pin privato con coordinate presenti nei cinque stati di accesso. Sono prove nel collaudo, non un certificato di invulnerabilità o una pubblicazione sul principale.

**V1: 15/25 criteri verificati nel collaudo = 60% dei criteri.**
`███████████████░░░░░░░░░░`
La barra non misura codice scritto o tempo residuo. I gate degli altri criteri restano determinanti per il lancio.

**Prove PostgreSQL native aggiuntive:** [run verificato](https://github.com/Diegosh501/TROVAt10/actions/runs/43481338497), PostgreSQL 17.11 isolato: 17 migrazioni registrate riprodotte, 16 regressioni, nove scenari realmente concorrenti e dump cifrato ripristinato in un secondo database. Confrontati dati e sicurezza di 42 tabelle, 42 policy, 96 funzioni, 177 vincoli, 11 trigger, 84 indici e quattro sequenze. Quattro modifiche negative ai permessi/RLS vengono rilevate; sei guardie locali e quattro sonde native proteggono l’isolamento. Le otto prove di cifratura passano. Auth resta un fixture e non è stato eseguito un recupero completo del progetto Supabase reale. [Procedura backup](BACKUP-RESTORE-SETUP.md).


## I 25 criteri della V1

VERIFICATO indica l'ambito effettivamente provato nel collaudo o nella ripresa. Non anticipa il rilascio sul sito principale.

| # | Criterio | Stato attuale | Evidenza e parte residua |
| --- | --- | --- | --- |
| 1 | Servizio raggiungibile | VERIFICATO | URL HTTPS di collaudo raggiunto e usato realmente; principale ancora preview |
| 2 | Release identificabile | VERIFICATO | Versioni Cloudflare e release pubbliche distinte; candidato rc.7 e collaudo cloud-test.10 identificati; ricevute di sorgenti/CI nel checkpoint privato |
| 3 | Autenticazione reale | PARZIALE | Google funziona; percorso email/password, SMTP, conferma e recupero ancora aperti nel Master |
| 4 | Google OAuth | VERIFICATO | Login reale anche dopo revoca della vecchia chiave; nuova credenziale custodita in Supabase |
| 5 | Profili persistenti | VERIFICATO | Due profili Google separati, ritrovati dopo nuovo accesso; entrambi Free |
| 6 | Assegnazione ruoli | VERIFICATO | Host/Sportivo cambiati sul server e persistenti; Admin assegnato separatamente e non selezionabile |
| 7 | Dashboard Admin protetta | PARZIALE | Allowlist e gate backend operativi; TOTP personale rinviato dal titolare, metriche reali non ancora aperte |
| 8 | Flussi Host/Sportivo | VERIFICATO | Evento pubblico creato, richiesto da altro account, approvato, avviato e concluso; ruoli ordinari controllati |
| 9 | Partite nel cloud | VERIFICATO | Tre eventi persistenti, inclusi annullato e concluso; storico ritrovato anche dal partecipante |
| 10 | Partecipazioni | VERIFICATO | Richiesta/pending, ammissione, conteggio, rimozione e nuova richiesta provati nel cloud |
| 11 | Inviti e privacy | VERIFICATO | Copia reale, ingresso anonimo e OAuth, sede mascherata prima/dopo rimozione; token non pubblicato nei metadata PNG |
| 12 | Comunicazioni necessarie | PARZIALE | Avvisi e preferenze SQL presenti; assistenza protetta testata localmente ma non attivata; push e promemoria pianificati non completati |
| 13 | Persistenza fra dispositivi | DA VERIFICARE | Nuovo accesso nello stesso browser riuscito; non vale come altro account/dispositivo |
| 14 | Tutti iniziano Free | VERIFICATO | Profilo reale Free, default server controllato; acquisti ancora spenti |
| 15 | Retention sette giorni | PARZIALE | Moduli e regressioni presenti; job spenti e nessuna cancellazione automatica attiva |
| 16 | Funzioni server necessarie | PARZIALE | Admin e contatto Host pubblicate; perimetro restante ancora da configurare |
| 17 | Permessi backend | VERIFICATO | 11/11 richieste reali per Sportivo e 11/11 per Host ordinario; gate MFA titolare confermato; fixture per revoche/metadata |
| 18 | Test multiutente | VERIFICATO | Due account Google distinti, flussi pubblici e privati; altro dispositivo e concorrenza rimangono nei criteri/scenari specifici |
| 19 | Nessun blocco conosciuto | NON DIMOSTRATO | Corrette race UI, copia link e ingresso anonimo da invito; servizi e gate di rilascio ancora aperti |
| 20 | Limiti economici | VERIFICATO | Nessun piano comprato, SMS inviato o pagamento reale; dominio acquistato rinviato |
| 21 | Backup/ripristino/rollback | PARZIALE | Recupero SQL isolato di 42 tabelle e permessi provato; recupero completo del progetto gestito ancora aperto |
| 22 | Informative adeguate | PARZIALE | Pagine versionate e consenso profilo acquisito; verifiche su servizi attivi, accordi e cancellazione effettiva aperte |
| 23 | Controlli post-deploy | DA ESEGUIRE | Collaudo cloud separato provato; nessun post-deploy della V1 completa sul principale |
| 24 | Documentazione | VERIFICATO | README e stato correnti aggiornati, limiti espliciti; ricevute del commit/CI e guida nel pacchetto di ripresa |
| 25 | Checkpoint riutilizzabile | VERIFICATO | File privati di ripresa, versioni e punti aperti conservati; non distribuire il checkpoint come sito |

## Scenari finali: prove ancora da chiudere

| Scenario | Prova fatta | Mancanza determinante |
| --- | --- | --- |
| A - Sportivo | VERIFICATO: nuova identità Google, profilo, ricerca, richiesta e persistenza dopo riapertura | Completato nel collaudo |
| B - Host | VERIFICATO: creazione pubblica, gestione richiesta, ammissione, avvio e conclusione | Completato nel collaudo |
| C - Admin | Allowlist, sessione viva, ingresso dedicato dopo sonda qualificata | Enrollment TOTP personale e uso reale della console |
| D - Permessi | VERIFICATO: richieste dirette SQL/Edge e dati privati da Sportivo e Host ordinario | Console completa resta nel distinto scenario C |
| E - Persistenza | Evento e storico visti da due account, anche dopo nuovo Google login | Altro dispositivo fisico ancora da provare |
| F - Retention | Regressioni SQL a sette giorni e vincoli | Job reale in ambiente approvato e risultato operativo |
| G - Errori | Campi vuoti rifiutati; suite su sessioni, rete e risposte tardive | Collaudo reale completo dei servizi; race osservata corretta e coperta da regressioni |
| H - Privacy | VERIFICATO: inviti e precedenti controlli backend, più 33/33 letture reali con pin non nullo: creatore, pending, ammesso, rimosso e anonimo | Completato nel collaudo nell’ambito documentato; nessuna certificazione generale |
| I - Concorrenza | Nove casi su PostgreSQL 17.11 con connessioni distinte e sovrapposizione osservata: doppie richieste, ultimo posto, ammissioni, avvio, Free e supporto | Prova HTTP concorrente nel servizio ancora da completare |
| L - Ripristino | Dump cifrato sintetico ripristinato in un secondo database: 42 tabelle e catalogo di sicurezza coerenti; sorgenti/versione frontend conservati | Backup e ripristino dell’intero progetto Supabase reale, oggetti e configurazione ancora da provare |
| M - Produzione | HTTPS, asset e percorsi riservati della preview controllati | Rilascio coordinato V1 e smoke sul medesimo URL principale |

## Configurazioni e sicurezza

Google usa il client esistente e il callback del solo progetto corretto. Redirect di collaudo esatto, niente wildcard. Nonce checks attivi e email verificata richiesta. Collegamento di configurazione GitHub-Supabase revocato e chiave Google precedente disattivata con consenso specifico. Nuovo login dell'app verificato dopo queste operazioni. Nessun token o segreto è incluso nel pacchetto.

L'account Admin è del titolare già indicato. Il secondo fattore non è stato creato o simulato; il titolare ha scelto di farlo più tardi. Una password storica in chat non è una credenziale da riutilizzare.

`onlineReady`, `exportReady` ed `erasureRequestsReady` sono veri solo nel collaudo. Email/password, assistenza nell’app, Billing, push e ciclo account restano spenti. La UI usa il contatto email per il supporto; il nuovo SQL resta in pending-operations dopo due conferme del connettore scadute. La configurazione di default dei sorgenti resta preview. Il modulo di cancellazione registra una pratica, non chiude accesso o dati: [ERASURE-REQUESTS.md](ERASURE-REQUESTS.md).

Non eseguire più i vecchi test remoti che esigono zero utenti: ora ci sono due account reali. Per prove sintetiche usare isolamento e rollback; le fixture locali non dimostrano backup o autenticazione reale.

## Ordine di completamento

1. Integrare le correzioni minime, sincronizzare GitHub e verificare CI e pacchetti senza segreti.
2. Completare personalmente il TOTP e collaudare la console; completare la prova su altro dispositivo senza inventare identità Google.
3. Configurare i percorsi del Master ancora aperti: email/SMTP/anti-abuso, assistenza, comunicazioni, job e cancellazione effettiva. Gli acquisti restano facoltativi e spenti fino a prove autorizzate.
4. Provare concorrenza, retention e ripristino in sicurezza; adeguare le informative ai servizi effettivi.
5. Solo dopo il superamento dei gate, pubblicare una release coordinata sul principale e chiudere lo scenario M.

Il dominio personalizzato non è un requisito del collaudo gratuito e non equivale all'ultima percentuale mancante dell'intero progetto. V2 PUBLIC BETA, V3 STABLE e V4 COMPLETE PLATFORM restano milestone successive alla V1.
