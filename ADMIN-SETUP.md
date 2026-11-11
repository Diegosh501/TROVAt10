> Ingresso aggiornato nel candidato: dopo Google, aprire Profilo. Solo l’account con hint server e conferma dell’allowlist dal backend riceve “Accesso Admin”; completare TOTP per visualizzare la console. Nessuna voce Admin per Free, Premium ordinario o demo locale. La precedente Console demo resta solo nelle immagini storiche interne.

> Aggiornamento 11 novembre: gestore Admin v2 distribuito e sorgente remoto confrontato. Rifiuto HTTP 401 verificato per credenziali assenti/token falso; TOTP e primo Admin reali ancora da configurare e provare. La preview locale è distinta dall’accesso riservato online. Stato autorevole: V1-STATUS.md.

# TROVAT1O - amministrazione e assistenza

La preview pubblicata 2.0.2 offre **Console · demo** con numeri e ticket inventati. Non è un accesso ai dati reali. Nel flusso cloud la voce si chiama **Amministrazione**. La visibilità della voce è un aiuto di navigazione; il database autorizza ogni operazione.

## Stato verificato il 10 novembre 2026

`admin-security.sql` è applicato al progetto pre-lancio: migrazione registrata `20261110164243_trovat1o_platform_admin_security`. La funzione Edge `admin-console` versione 1 è pubblicata con verifica JWT. Non ci sono account Auth né amministratori assegnati. Google non è ancora configurato e il client mantiene `onlineReady: false`.

La matrice completa di completamento e le dipendenze della 1.0 sono in [V1-STATUS.md](V1-STATUS.md).

## Controlli effettivi

- L'elenco autorevole è `private.platform_admins`, inaccessibile ai client. Un ruolo in `user_metadata`, un'email digitata o un pulsante mostrato non conferiscono privilegi.
- Ogni RPC richiede account confermato e non anonimo/bloccato, appartenenza attiva all'elenco, sessione ancora presente e non scaduta, TOTP verificato e livello `aal2`. L'ultima verifica TOTP deve risalire a non più di 15 minuti.
- Revoca del permesso, logout con revoca della sessione e rimozione del fattore impediscono le successive operazioni sensibili anche usando il precedente access token.
- La funzione Edge usa il token dell'utente e la chiave pubblica. Non usa la service-role per leggere ticket o modificare dati amministrativi.
- Le operazioni sono limitate a 60 al minuto per amministratore. Il database registra le letture della console e le modifiche ai ticket. La modifica di un ticket e i suoi due record di audit sono atomici.
- La console restituisce conteggi aggregati. I contatti dei ticket compaiono solo se forniti volontariamente; la ricerca è limitata a 50 risultati.
- Le risposte amministrative sono `no-store`. Il service worker conserva soltanto il guscio pubblico dell'app, senza API, richieste autorizzate o parametri degli inviti.

## Primo account amministrativo

1. Configurare Google OAuth e il completamento del profilo, poi effettuare un vero accesso con l'identità scelta dal titolare. Questo passaggio resta aperto: l'attuale trigger di registrazione richiede metadati del precedente flusso email e va adattato prima di abilitare Google.
2. Dal pannello Auth rilevare l'ID dell'account e verificarne l'email. Non creare password condivise o credenziali incorporate nell'app.
3. Nel solo ambiente privato impostare `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `TROVAT1O_ADMIN_USER_ID`, `TROVAT1O_ADMIN_EMAIL`. Eseguire `node scripts/promote-admin.mjs`. Lo script legge un solo account, controlla la corrispondenza ID/email e chiama il provisioning riservato al server. I valori non vanno salvati nel repository o passati come argomenti del comando.
4. Accedere di nuovo per aggiornare la voce di navigazione. Aprire Amministrazione, configurare TOTP con un'app di autenticazione e confermare il codice. Dopo 15 minuti è richiesta una nuova verifica.
5. Provare anche con un account Host e uno Sportivo distinti: entrambi devono ricevere un rifiuto chiamando direttamente le RPC amministrative.

Per revocare un permesso, utilizzare lo stesso script con `TROVAT1O_ADMIN_ACTION=revoke`. L'elenco nel database viene aggiornato prima del suggerimento di navigazione nei metadati. Il registro mantiene l'operazione.

## Configurazione della funzione

L'origine predefinita è l'URL HTTPS già pubblicato su workers.dev. Per un altro ambiente usare `APP_ORIGIN` con l'origine esatta: niente wildcard e niente percorso. L'account del titolare non viene identificato confrontando un'email incorporata nel codice.

Per i conteggi di utilizzo API sono opzionali `SUPABASE_MANAGEMENT_API_TOKEN` con il minimo permesso disponibile e `SUPABASE_PROJECT_REF`, solo nei segreti server. Senza questi parametri il dato è indicato come non disponibile; non è una misura di CPU in tempo reale.

`support-request` resta da configurare e distribuire con Turnstile. Le modifiche ai ticket non inviano automaticamente un'email: sono salvate nella console. Non dichiarare operativo un canale di risposta non attivato.

## Prove e limiti

Sono passati 21 gruppi di prove database in `tests/sql/admin-access.sql`, sia prima sia dopo l'applicazione della migrazione. Il test rifiuta database popolati, usa tre utenti/sessioni sintetici e annulla tutte le righe. Non invia email o SMS e non prova un vero scambio OAuth/MFA.

`tests/admin-edge-runtime.cjs` esegue 30 scenari del vero gestore Edge con trasporti Auth/RPC simulati. Il controllo Deno dei tipi locali è passato. Le prove HTTP del deploy sono salvate nel rapporto di audit. Il login Admin reale e l'assegnazione del primo amministratore restano aperti.

Gli advisor segnalano ancora le RPC SECURITY DEFINER intenzionalmente esposte e tre tabelle private con RLS senza policy: in questo schema non esposto il diniego predefinito e l'assenza di privilegi client sono voluti. Non è una certificazione di assenza di vulnerabilità. La CSP della web app mantiene handler inline da migliorare in un intervento dedicato.
