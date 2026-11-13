# Stato corrente — 13 novembre 2026, collaudo multiutente

Questa sezione prevale sullo storico conservato sotto. Stato dettagliato: **V1-STATUS.md**.

- **Collaudo cloud:** https://v1-check-trovato.diegolucentedesign.workers.dev/, `1.0.0-cloud-test.10`, Cloudflare `8ac772c9-508b-47db-8487-14b9d0946a2d`. Candidato sorgente `1.0.0-rc.7`, cache pubblica v21. Il principale resta `1.0.0-rc.1`, preview locale: nessun nuovo traffico di produzione è stato attivato.
- **Due account Google e due profili Free reali.** Tre eventi di prova: un privato programmato, un privato annullato e un pubblico concluso. Nessuna prenotazione o pagamento. Pubblicazione, richiesta, ammissione, avvio, conclusione e storico sono stati provati fra account distinti.
- **Inviti:** copia effettiva del link, ingresso anonimo e ritorno da Google verificati. Sede privata mascherata per ospite, pending e rimosso; visibile solo dopo ammissione. Una nuova richiesta dopo rimozione resta pending. Il token resta in memoria, non nell’archivio locale dei match; generare un nuovo invito dopo una nuova sessione sostituisce quello precedente, con avviso.
- **Sicurezza reale:** 11/11 controlli HTTP con Sportivo e 11/11 con Host ordinario. Admin SQL/Edge negati, profili altrui invisibili, sede/roster/contatto privati protetti e azioni altrui respinte. Due sonde del titolare confermano `mfa_required`. Nessun enrollment MFA simulato: il titolare lo ha rinviato.
- **Backend:** progetto `nrixslotansgrtrosaof`, 17 migrazioni. Nuova migrazione `20261113121927_trovat1o_event_status_notification_copy`: testo corretto per avvio e conclusione; tipo, permessi e coda invariati. Admin Edge v4 e contatto Host v1 attivi. Nessun job di purge/retention/push attivo.
- **Controlli:** 27 suite Node; 16 moduli SQL e 16 regressioni locali, compresi avvisi di stato. Le fixture non provano Auth gestita, concorrenza HTTP, Cron o ripristino. Quattro larghezze già controllate: 320, 390, 768 e 1440 px.
- **Master R3:** 15/25 criteri verificati nel collaudo = 60% dei criteri, non del tempo o del codice. Scenari A, B, D e H chiusi nell’ambito documentato: 3/11. Pin riservati verificati con coordinate presenti: 33/33 controlli reali nei cinque stati creatore, pending, ammesso, rimosso e anonimo. Persistenza su altro dispositivo, concorrenza, automatismi e recupero restano aperti.
- **Assistenza nuova:** handler, UI, quote e registri anti-riuso/idempotenza verificati localmente. Migrazione pendente: due conferme del connettore scadute, nessun DDL applicato. Il modulo resta spento e la UI presenta il contatto email. Leggere [SUPPORT-SETUP.md](SUPPORT-SETUP.md). CAPTCHA caricato solo su richiesta, indipendente dall’accesso Google.
- **Residui:** TOTP e uso completo Admin, email/password con SMTP/conferma/reset/anti-abuso, assistenza, push/promemoria, retention/account lifecycle, cancellazione effettiva, backup/ripristino, informative e rilascio sul principale. Acquisti Premium €4,99/anno spenti. Nessun servizio a pagamento acquistato.
- **Advisors:** 18 tabelle private con RLS senza policy (diniego intenzionale), due RPC anonime e 43 autenticate SECURITY DEFINER da mantenere con gate/grant stretti. Protezione password compromesse segnalata: percorso email e configurazione anti-abuso remota restano un gate; il flag UI spento non prova la disattivazione del provider.
- Sorgenti, CI e integrità degli archivi hanno ricevute separate nel checkpoint privato. Un vecchio verde non verifica nuove modifiche. Non eseguire i test che richiedono un DB remoto vuoto: contiene account reali.

---

## Documento e checkpoint precedenti

# Durata degli account Free

Decisione del titolare dell’11 novembre 2026: il periodo Free parte dalla **creazione del primo match**, dura sette giorni ed esclude gli account con Premium verificato attivo. Non coincide con lo storico dei match, che ha un termine distinto dalla conclusione o dall’annullamento.

## Stato effettivo

Il codice è in `supabase/account-lifecycle.sql`, con interfaccia dietro `accountLifecycleReady: false`. Le impostazioni server iniziano con `enabled=false` e `purge_enabled=false`. **Non è attivo online.** Il tentativo di applicare la migrazione con il connettore l’11 novembre ha richiesto una conferma operativa poi scaduta: una lettura successiva ha verificato che la tabella non esiste e le migrazioni remote restano tredici. Non riprovare automaticamente per ottenere approvazioni ripetute.

La funzione Admin aggiornata a versione 2 è stata invece distribuita, senza attivare questo modulo, Google o pagamenti. Nessun account reale è stato cancellato e nessun nuovo costo è stato autorizzato.

## Regole implementate

- Un trigger sul primo inserimento effettivo di un evento registra l’ora reale del server dopo aver acquisito il blocco sulla conferma delle condizioni, non l’ora di inizio della transazione. L’orario del match, l’orologio del dispositivo e i dati modificabili del profilo non possono scegliere questa data. Se la creazione viene annullata dalla transazione, anche il conteggio viene annullato.
- Partecipazione, cambio ruolo, annullamento e rimozione di un match non fanno ripartire il periodo. Uno Sportivo che non ha mai creato un evento non avvia il conteggio.
- Prima di creare un evento, quando la regola è attiva, viene presentata una conferma non preselezionata con il collegamento alle condizioni. La conferma viene registrata per il solo account chiamante con una sessione ancora valida; non è un consenso pubblicitario e non può attribuire Premium.
- Alla scadenza, il server impedisce nuove creazioni e nuove richieste. Gestione dei match già esistenti e ritiro della partecipazione restano possibili. L’account resta consultabile fino alla cancellazione fisica, così può chiedere assistenza o esportare i dati.
- Un avviso nell’account all’inizio spiega la regola. Alla scadenza il worker registra un altro avviso: la cancellazione fisica non avviene prima di ulteriori 48 ore. Gli avvisi di servizio non dipendono dalle preferenze sugli aggiornamenti di attività; non è promessa un’email o una push consegnata se il relativo servizio non è attivo.
- Premium attivo e amministratori presenti nell’allowlist sono protetti. Un token o un metadata fornito dal browser non conferma un pagamento. Dopo la cessazione del Premium vengono rivalutati il termine originario e un nuovo avviso, se il worker aveva osservato e azzerato il precedente.

## Cancellazione prudente

`run_account_retention(25)` usa una transazione, batch limitati e blocchi sugli account, sui profili e sui piani. Non effettua una verifica SQL seguita da una cancellazione HTTP separata, che potrebbe correre contro un pagamento. Quando tutte le condizioni sono soddisfatte, elimina la riga Auth: profilo e sessioni vengono rimossi dalle relazioni a cascata. Le operazioni sensibili continuano a controllare l’esistenza dell’utente/sessione anche con un vecchio JWT.

La cancellazione viene rinviata se esistono match ancora intestati all’utente, partecipazioni approvate/in attesa a eventi non conclusi, contributi di posizione ancora collegati, segnalazioni, assistenza aperta, audit di assistenza o una sospensione di conservazione. Sono protetti anche piano mancante, oggetti Storage dell’utente e qualsiasi collegamento Billing, incluse operazioni pendenti. La riduzione dei dati finanziari dopo la loro conservazione obbligatoria è una procedura distinta: questo worker non la indovina né cancella il cliente Stripe.

La presenza di una nuova dipendenza sconosciuta, anche a cascata e anche transitiva, ferma il purge fisico. Non vengono eliminati report per liberare forzatamente un account. Il rinnovo di una sospensione di conservazione acquisisce gli stessi blocchi sul record Auth e sul profilo del worker, prima di aggiornare la sospensione; non può dichiararsi riuscito per un account già eliminato. Un vincolo o un conflitto di blocchi trattiene la riga e permette una riprova. Le righe trattenute passano a una verifica successiva: non occupano indefinitamente i primi posti del batch bloccando gli altri account.

Il ciclo di conservazione degli eventi deve terminare prima di liberare un Host che conserva eventi. Un match necessario a un altro partecipante non è cancellato per espellere più rapidamente l’Host. Questa salvaguardia significa che non si può promettere spazio recuperato per ogni account esattamente al settimo giorno.

I record precedenti alla comunicazione della regola o non riconciliati sono esclusi dalla cancellazione automatica. Non anticipare la data della conferma per farli rientrare nel job.

## Attivazione e disattivazione

Prima dell’attivazione servono: migrazione approvata nel progetto corretto, revisione delle dipendenze reali/Storage, informative aggiornate, percorso di esportazione e assistenza funzionante, disponibilità effettiva del Premium proposto e prove reali di Auth/pagamento in ambiente separato. La beta gratuita iniziale può mantenere disattivata questa durata finché gli acquisti non sono operativi: non presentarla come già applicata.

Le RPC `set_account_lifecycle_enabled(enabled,purge_enabled,policy_version)`, `set_account_retention_hold(...)` e `configure_account_retention_cron(...)` sono riservate al server. La configurazione rifiuta il purge se l’enforcement è spento. Il job usa l’estensione inclusa `pg_cron`, al minuto 37 di ogni ora; il modulo non installa l’estensione e non lo attiva automaticamente. Va controllata una vera esecuzione sul servizio prima di chiamarlo operativo. I conteggi privati del worker sono conservati per 30 giorni, senza una lista di persone eliminate.

Per fermare la pulizia, disabilitare il solo job e impostare entrambe le opzioni server su false. Disattivare un job non ripristina account già cancellati. Occorrono una procedura di backup/ripristino provata e istruzioni che non reintroducano dati di account eliminati.

## Prove e limiti

`tests/account-lifecycle-runtime.cjs` esegue dieci scenari delle funzioni reali del client con trasporti controllati: conferma, ordine delle chiamate, errore server, doppio tap, scadenza, risposta tardiva e cambio account. `tests/sql/account-lifecycle.sql` esegue dodici gruppi in PostgreSQL locale e termina con rollback verificato dei conteggi.

Le prove coprono periodo esatto, mancato reset, join senza timer, sessione revocata, blocco delle nuove operazioni, preavviso/grazia, Premium, Admin, acquisti, match attivi, segnalazioni, vincoli nuovi, Storage, cancellazione Auth/sessione/profilo e rotazione del batch. Sono prove sintetiche PGlite, non un accesso Google reale, un webhook reale o un’esecuzione Cron. La concorrenza a connessioni separate e la gestione delle tabelle Auth/Storage del servizio reale restano da verificare in un ambiente approvato.

Riferimenti primari: [gestione e cancellazione utenti Supabase](https://supabase.com/docs/guides/auth/managing-user-data), [Cron Supabase](https://supabase.com/docs/guides/cron). I JWT già emessi possono sopravvivere fino alla loro scadenza; la cancellazione non sostituisce i controlli applicativi su utente e sessione.
