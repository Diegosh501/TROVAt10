# Richieste di cancellazione account

Stato del 13 novembre 2026: **richiesta autenticata operativa nel backend e nel collaudo; cancellazione/chiusura automatica non implementata**. Non equiparare un ticket risolto a dati cancellati.

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
