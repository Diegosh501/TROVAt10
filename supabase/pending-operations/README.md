# Operazioni preparate, non applicate

`account-lifecycle-disabled.sql` contiene la migrazione candidata dell’11 novembre: aggiorna la versione delle conferme e l’esportazione del profilo e installa il ciclo account con entrambe le opzioni disattivate. Il file ha una protezione che rifiuta l’esecuzione se il progetto contiene utenti, profili o eventi.

Il connettore ha richiesto una conferma operativa poi scaduta. La lettura successiva ha confermato che NON è applicata: restano tredici migrazioni remote e nessuna tabella `private.account_lifecycle`.

Questo file non è una migrazione registrata, non va copiato in `recorded-migrations/` e non va avviato con `db push`. Va riesaminato con le dipendenze reali e approvato attraverso il servizio quando il titolare è disponibile. Non usare un altro canale per aggirare la conferma. L’attivazione della regola e del purge è un passaggio separato, successivo alle prove reali.
