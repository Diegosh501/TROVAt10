# Operazioni candidate e riferimenti storici

Stato del 13 novembre 2026: il progetto remoto ha **17 migrazioni registrate** e contiene account reali. Non rieseguire baseline o fixture che richiedono zero utenti; non usare `db push` senza riconciliare la cronologia.

- `20261113161033_trovat1o_verified_support_submission.sql`: candidato assistenza verificato localmente e in PostgreSQL nativo. Non applicato: due conferme tecniche del connettore scadute, consenso chat valido. Non aggirare la conferma e non ripetere automaticamente il ciclo.
- `20261113223917_trovat1o_reviewed_erasure_execution.sql`: nuovo candidato per conferma recente dell’utente, revisione Admin/TOTP, protezione delle dipendenze e cancellazione transazionale. Nome generato da Supabase CLI 3.1.0; contenuto identico a `../account-erasure-execution.sql`. Esecuzione inizialmente disabilitata; nessuna cancellazione reale o applicazione remota. Le prove locali non attestano l’integrazione sul servizio gestito.
- `account-lifecycle-disabled.sql`: **riferimento storico, da non riapplicare**. La migrazione corrispondente è stata successivamente registrata come `20261111124013_trovat1o_account_lifecycle_disabled.sql`. La tabella esiste; enforcement e purge rimangono disattivati. Il vecchio file conserva il controllo di database vuoto e non è una nuova operazione da eseguire.

Solo una migrazione effettivamente riuscita, con versione restituita dal server e sorgente confrontato, va aggiunta a `recorded-migrations/`. Pubblicare un file candidato non lo applica. Abilitare il servizio, attivare un job o consentire cancellazioni sono passaggi distinti, successivi alle verifiche e alle autorizzazioni pertinenti.
