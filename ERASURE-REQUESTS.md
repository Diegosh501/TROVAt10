# Richieste di cancellazione account

Stato del 13 novembre 2026: **richiesta autenticata operativa nel backend e nel collaudo; esecuzione della cancellazione preparata come candidato locale disabilitato, non applicato o attivo nel cloud**. Non equiparare un ticket risolto a dati cancellati.

## Utente

Nel collaudo cloud, Profilo → Notifiche e privacy → I tuoi dati → Richiedi cancellazione account. Il pulsante richiede una conferma non preselezionata. Prima è disponibile l’esportazione dei propri dati. La conferma registra una pratica nella coda assistenza, senza chiudere l’accesso, cancellare record o annullare un rinnovo Stripe.

La ricevuta mostra identificativo e stato. La lettura è riservata all’account con sessione viva che ha inviato la richiesta. Non espone testo del ticket, recapiti o dati di altri utenti. Il server ricava il destinatario da Auth: il browser non sceglie un user_id o un piano. Funziona anche per Free senza primo match e Premium; una pratica aperta viene restituita senza duplicati. Tre nuove pratiche in 24 ore sono il limite dopo le eventuali chiusure precedenti.

## Admin

Dopo allowlist e TOTP, aprire Assistenza, categoria Account, cercando «Richiesta cancellazione account». Le nuove pratiche hanno request_kind=account_erasure e requester_user_id associato dal server. Nessun nome o recapito viene copiato automaticamente nel ticket. Le regole esistenti di audit e accesso Admin proteggono la coda.

La gestione del ticket serve a seguire la pratica. Gli stati resolved/closed non provano l’eliminazione di Auth, delle partite, degli acquisti o dei dati presso i fornitori. Non chiudere una richiesta come completata senza una verifica documentata dell’esito.

Prima della chiusura effettiva servono ancora: conferma recente dell’identità, revoca delle sessioni e divieto di nuovo ingresso, gestione delle partite condivise, minimizzazione dei dati residui, riconciliazione degli acquisti, procedura di eliminazione compatibile con Auth/Storage, revisione e ricevuta finale. Un eventuale rinnovo Stripe è un’operazione distinta. Il ruolo Admin richiede anche un percorso di successione per evitare di lasciare il servizio senza gestore.

## Backend e attivazione

Modulo incrementale: supabase/account-erasure-requests.sql, applicato come 20261113013901_trovat1o_authenticated_erasure_intake. Non riapplicare il blueprint su un progetto che lo contiene già.

RPC: request_account_erasure(p_confirm boolean) e my_account_erasure_request(). Entrambe richiedono l’identità confermata e una sessione viva. Nessun grant anonimo o accesso diretto alla tabella support_requests. Le richieste sono serializzate sugli stessi parent Auth → profilo del worker di conservazione, con indice unico per una sola pratica aperta. Il worker conserva già gli account con ticket aperti. Non sono aggiunte nuove FK che cambino le dipendenze della pulizia.

Il client usa erasureRequestsReady. La configurazione di esempio e il sito pubblico principale mantengono il flag disattivato. Il collaudo separato lo abilita per il percorso di richiesta già presente nel database; non attiva cancellazioni.

## Prove e limiti

- 8 casi client: rollout spento, conferma esplicita, ricevuta veritiera, doppio tap, errore rete, cambio account, dialogo sostituito e rifiuto di risposte che dichiarano cancellazioni non supportate.
- Regressione SQL locale e sul database Supabase: privilegi, conferme false/null, isolamento, idempotenza, Free/Premium, conservazione di ticket aperti, quote e revoca sessione.
- Prova Supabase effettuata prima di creare il vero account del titolare, con fixture sintetiche e ROLLBACK: zero utenti, ticket ed eventi residui. Il file rifiuta database popolati: **non rieseguirlo ora sul progetto che contiene utenti reali**.
- Nessuna cancellazione reale o chiusura del conto del titolare provata. Il percorso completo resta aperto.

## Candidato di esecuzione riservata, non attivo

`account-erasure-execution.sql` aggiunge un percorso distinto dal ticket: l’utente conferma esplicitamente la propria richiesta con una sessione realmente creata da meno di 15 minuti; un token appena rinnovato non basta. `confirm_my_account_erasure` non accetta un destinatario diverso dal chiamante. L’Admin deve superare allowlist, sessione viva e TOTP recente. Ruolo Host, Premium e metadata del browser non concedono questo accesso.

`admin_preview_account_erasure` restituisce soltanto esito e motivo del blocco oppure un codice di revisione casuale, valido cinque minuti e legato all’Admin. `admin_execute_account_erasure` richiede quel codice e la frase esatta `CANCELLA ACCOUNT`, ripete i controlli e serializza le dipendenze. Le conferme non vengono preselezionate. Un nuovo riesame o una nuova conferma dell’utente invalida il precedente codice.

La cancellazione resta bloccata da amministrazione, Premium attivo, collegamenti finanziari anche scaduti o checkout pendenti, partite ancora intestate, partecipazioni attive, contributi di posizione, segnalazioni, sospensioni di conservazione, oggetti Storage, altri ticket anche chiusi da minimizzare e dipendenze sconosciute. Una pratica bloccata non chiude l’accesso e non viene dichiarata cancellata. Gli account Admin richiedono un percorso di successione separato.

Per un account privo di vincoli, la stessa transazione elimina le sessioni e Auth, verifica la rimozione di profilo e identità e minimizza la ricevuta. Un errore di dipendenze ripristina anche le sessioni: nessun falso successo o chiusura parziale. Un secondo invio restituisce la ricevuta già completata. Le ricevute finali non contengono user ID, session ID o codice di revisione; l’audit conserva l’Admin e il riferimento alla pratica. L’account Google esterno non viene cancellato, né vengono trattati pagamenti o log dei fornitori come eliminati automaticamente.

Due gate restano spenti: impostazione SQL `account_erasure_execution_settings.enabled=false` ed ambiente Edge `ACCOUNT_ERASURE_EXECUTION_ENABLED` assente/false. La nuova Edge usa il token dell’Admin e la chiave pubblica, senza service-role. Le azioni `erasure-preview` e `erasure-execute` hanno corpo limitato, campi esatti e risposte no-store. L’interfaccia per conferma recente e revisione operativa deve essere integrata e verificata prima dell’attivazione; il solo codice server non completa il flusso online.

Prove attuali: regressione dedicata e tutte le 17 regressioni SQL locali con rollback verificato; 44 casi dell’handler Admin, di cui sei nuovi sul percorso. PostgreSQL nativo concorrente, Auth/Storage del servizio reale, MFA personale e cancellazione reale autorizzata restano verifiche distinte. La migrazione candidata non è stata applicata e nessun utente reale è stato cancellato.

Riferimento primario: [gestione utenti Supabase](https://supabase.com/docs/guides/auth/managing-user-data). La cancellazione di Auth da sola non invalida immediatamente un JWT; il codice elimina le sessioni e i controlli applicativi richiedono utente e sessione vivi. Le dipendenze del servizio gestito richiedono comunque una prova specifica prima del rilascio.
