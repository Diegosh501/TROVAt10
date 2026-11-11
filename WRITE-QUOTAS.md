> Stato 11 novembre: SQL incluso nella migrazione remota 20261111025149_trovat1o_online_beta_operations. Nessun cleanup Cron attivo. I limiti sono coperti dalle regressioni locali; il collaudo con sessioni reali resta aperto.

# Quote tecniche di scrittura

La migrazione `supabase/write-quotas.sql` aggiunge protezioni contro creazioni/annullamenti ripetuti e cambi di partecipazione automatizzati. Si applica dopo baseline, sicurezza Admin e accesso Free. È sorgente locale finché non viene applicata e verificata nell'ambiente cloud autorizzato.

| Azione del chiamante | Minuto server | Ora server |
| --- | ---: | ---: |
| Creazione evento | 10 | 60 |
| Nuova richiesta/cambio della propria partecipazione | 60 | 600 |
| Gestione di altri partecipanti | 60 | 600 |

Sono finestre fisse per minuto/ora, basate sull'orologio della transazione server, distinte dai limiti Free/Premium. Un cambio di finestra può consentire una raffica ai suoi due lati. Anche Premium rispetta questi tetti tecnici. Sessanta creazioni in un'ora sono ampiamente superiori al normale uso individuale e permettono organizzazione in blocco senza rendere illimitato un account: tornei o importazioni oltre il limite richiedono un processo amministrativo dedicato. Non sono un limite di prezzo né una promessa di capacità del servizio.

I trigger agiscono su INSERT di eventi e INSERT/cambio effettivo di stato delle partecipazioni, anche quando la scrittura proviene da RPC SECURITY DEFINER. L'identità è `auth.uid()` del chiamante, mai `current_user`, che in una funzione privilegiata potrebbe essere il proprietario SQL. Annullare o eliminare un evento non azzera il contatore. Un aggiornamento che lascia invariato lo stato non consuma quota. Ritirare la propria partecipazione rimane sempre possibile e non consuma il contatore delle nuove richieste. Errori successivi alla scrittura annullano insieme modifica e contatore nella stessa transazione.

Ogni coppia utente/azione ha una sola riga privata con entrambe le finestre. Un UPSERT condizionale incrementa i due contatori atomicamente sulla riga bloccata e restituisce `PT429 / write_rate_limited` quando una finestra è piena. I client non possono leggere/modificare la tabella, invocare l'helper privato o scegliere un'azione pubblica per aggirare la quota. Non vengono copiati nome, email, telefono, dettagli dell'evento o contenuto dei report: resta il solo UUID tecnico dell'account con azione, finestre e conteggi.

Un amministratore realmente in allowlist, con sessione attiva e TOTP recente, è escluso soltanto quando modera la partecipazione di altri utenti. La creazione di suoi eventi e le sue partecipazioni continuano a contare. Le autorizzazioni degli eventi e delle RPC rimangono comunque necessarie: un'esenzione dalla quota non concede privilegi. I processi di servizio e le fixture prive di `auth.uid()` non consumano quote.

`public.cleanup_write_quotas()` è eseguibile solo dal ruolo di servizio e rimuove contatori inattivi da oltre 48 ore. La cancellazione dell'account elimina i relativi contatori tramite FK. Questa migrazione non crea Cron o servizi; il cleanup va collegato a un job di manutenzione separato e verificato prima dell'uso pubblico. Se il job non viene configurato, i contatori restano al massimo tre righe per account, con le finestre aggiornate all'uso; la retention di 48 ore non va dichiarata operativa automaticamente.

`tests/sql/write-quotas.sql` verifica finestre, cicli crea/annulla, identità attraverso RPC privilegiate, separazione delle azioni, no-op, rollback, bypass Admin ristretto e cleanup. L'harness `node tests/local-postgres.cjs --require-engine` usa PGlite e fixture sintetiche; l'UPSERT reale viene eseguito ma una singola connessione non prova concorrenza tra sessioni PostgreSQL distinte. Quel collaudo resta necessario nell'ambiente di staging autorizzato.
