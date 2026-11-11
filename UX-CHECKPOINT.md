# Frontend: controllo e integrazione del 10 novembre 2026

`index.html` e `index-v2.html` sono identici. Queste modifiche sono nei sorgenti candidati, non costituiscono un nuovo deploy o un collaudo Google/Stripe reale.

## Flussi corretti

- Le risposte tardive del cambio ruolo non modificano il profilo di chi accede successivamente sullo stesso dispositivo.
- Liste fattori, challenge, enrollment e verifica MFA conservano il confine dell'account. Un enrollment concluso dopo logout non mostra QR o chiave TOTP dell'account precedente. Il codice di verifica ha un pulsante disabilitato durante la richiesta.
- Il controllo MFA iniziale non apre la console dopo un cambio account. Richieste di amministrazione e risultati di ricerca tardivi non popolano un'altra sezione o un altro account.
- Un doppio tap sul salvataggio invia una sola creazione in corso. I callback dei partecipanti e degli stati evento hanno controlli dell'account e protezione contro richieste duplicate.
- Il contatto Host usa la funzione `host-contact`, per consenso e revoca: `{eventId, phone, consent}`. L'esito atteso è `{ok:true}`. Il numero opzionale non viene più scritto direttamente dalla pagina.
- Un errore del contatto successivo alla creazione non dichiara che la partita non esiste. Il messaggio distingue la partita già salvata dalla condivisione non aggiornata, evitando duplicazioni per tentativi di creazione ripetuti.
- La CTA di una partita privata è **Crea partita**. Non comunica una pubblicazione che l'utente non ha scelto.
- Le richieste di partecipazione in attesa compaiono in **I miei match**. Il percorso online non tronca lo storico a dieci partite: usa i dati restituiti dal server e la politica di conservazione del backend. La demo locale conserva il vecchio limite, dichiarandolo come limite della demo.
- Partite concluse o annullate non mostrano azioni di modifica, avanzamento stato o ammissione. Quelle in corso possono essere segnate concluse; la modifica dei dettagli resta per le partite programmate.
- Lo stato di pagamento tardivo non carica il profilo dell'account successivo. Il fallimento della lettura dell'abbonamento non viene convertito silenziosamente in una corretta lettura Free.
- L'attributo HTML `hidden` ha una regola esplicita, così lo stile dei pulsanti e delle griglie non rende visibili controlli nascosti, compresa la gestione abbonamento.

## Console amministrativa essenziale

Un selettore accessibile da mobile apre una sezione alla volta: Panoramica, Utenti, Eventi, Segnalazioni, Assistenza o Registro attività.

Le directory online usano ricerca, filtro e pagine da 25. La directory utenti mostra username, ruolo, piano e conteggi, senza renderizzare email o telefono. I controlli disponibili passano solo dalle azioni riservate `users`, `events`, `reports`, `user-role`, `review-report` e `cancel-event`. Il ruolo pubblico non può essere impostato ad Admin. Le revisioni hanno stato consentito e nota massima di 2000 caratteri. L'annullamento richiede una conferma nel prodotto. Nessun pulsante promette sospensione account o configurazioni non implementate.

Il registro usa l'RPC esistente `audit`, risposta `{entries:[...]}`, e dichiara il limite alle ultime 50 azioni. Le richieste di assistenza mantengono la sezione e i contatti volontari già previsti. Le altre directory nella demo offline mostrano che è necessario un accesso amministrativo online, senza inventare dati operativi.

## Prove eseguite

- `tests/ui-account-boundary.cjs`: 13 regressioni delle funzioni effettive del client, con trasporti controllati. Coprono cambio account, MFA, doppio salvataggio, errore contatto dopo commit, storico, richieste pending, azioni chiuse e ritorno pagamento.
- `tests/admin-client-runtime.cjs`: 13 scenari della console. Coprono directory pseudonime, escaping, paginazione, ricerca, risposta tardiva, logout, errori, ID/ruoli/stati/note invalidi, conferma annullamento e registro.
- Tutte le suite `tests/*.cjs` presenti al controllo sono passate. Log locale: `tmp/resume/ui-review-final-tests.log`. Le prove dei gestori Edge, SQL e firme Stripe hanno suite separate gestite dalla release.
- Controllo di uguaglianza dei due index superato. Il controllo degli handler comprende i nuovi collegamenti della console.

## Verifiche da completare

Il tentativo di aprire un server locale su `127.0.0.1:4173` è stato rifiutato dall'ambiente di esecuzione prima del bind. Non è stata richiesta un'approvazione al titolare assente e non è stato interagito con la sua console Google. Questo blocco non va descritto come test browser superato. Il responsabile del rilascio può eseguire il controllo reale su una directory di soli asset pubblici autorizzata.

Servono ancora un collaudo visuale mobile/desktop della nuova console e degli stati, Google reale, utenti distinti, MFA reale, funzioni distribuite e verifiche dopo il deploy. La politica di sette giorni mostrata online dipende dall'applicazione del backend di retention; non è simulata tramite cancellazione nel browser.

Le push restano disattivate finché il backend non è pronto. Prima di abilitarle occorre gestire anche la revoca della sottoscrizione del dispositivo al cambio account/logout, senza interferire con la successiva registrazione dello stesso browser; è stato segnalato al responsabile del backend.


## Integrazioni successive salvate

Il ciclo push su logout/cambio account è ora implementato e verificato da 10 scenari in `push-lifecycle-runtime.cjs`; le push restano disabilitate fino alla consegna reale e alla configurazione server. L’export nelle preferenze è protetto da `exportReady`: 8 scenari su paginazione, errori e cambio account; il file JSON viene costruito in memoria senza salvataggio permanente dei dati dell’account nel browser. Sei scenari del bootstrap coprono il caricamento Supabase per Google senza richiedere CAPTCHA. Nessuna delle prove sostituisce un collaudo visuale della build cloud attiva.
