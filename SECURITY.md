# TROVAT1O · impostazioni cloud e sicurezza

## Modalità corrente

La preview online e quella locale sono demo; `onlineReady` è `false`. La registrazione cloud non è attiva. Il database Supabase ha schema/RLS applicati ma non contiene profili o eventi ; `admin-console` v1 è pubblicata, mentre le altre Edge Functions restano da configurare. Google è ancora disattivato e non esistono account Auth reali. La chiave Supabase publishable/anon non è un segreto, ma non è inserita nell’attuale configurazione del client.

## Percorso V1.0 aggiornato

Il percorso richiesto usa Google OAuth, con completamento del profilo, tutti i piani Free e nessuna scelta di salvataggio locale online. È ancora da implementare e configurare completamente: il vecchio trigger profilo richiede metadati del signup email, quindi Google non va attivato prima del suo adattamento. Le regole telefono pubbliche precedenti vanno riallineate al percorso gratuito, senza attivare SMS a pagamento.

## Flusso email precedente, non attivo

1. Registrazione con username, email, password, ruolo e conferma della maggiore età/consensi.
2. Conferma email obbligatoria prima dell’accesso alle funzioni dell’app. Accesso con email/password.
3. Il numero può essere aggiunto dopo. La verifica è richiesta per pubblicare o unirsi a eventi pubblici e per inviare segnalazioni. Evento privato e invito valido permettono l’accesso con email confermata senza OTP SMS. Twilio Verify può comportare costi.

Supabase Auth deve avere **Confirm email** attivo, SMTP personalizzato, URL HTTPS/redirect e protezioni CAPTCHA configurate. L’email automatica predefinita Supabase non è sufficiente per account pubblici. Accetta provider email generici verificati; richiedere Gmail, Google, Apple o Meta non migliora da solo la protezione contro abusi.

## Eventi e dati riservati

- `events` non è leggibile o aggiornabile direttamente da `anon` o `authenticated`; il client usa un feed server che rimuove il luogo preciso e il pin privato per i non ammessi.
- Creazione, modifica, gestione del roster, capienza, pin e stato passano da funzioni transazionali con controllo dell’utente, email, ruolo e stato evento.
- Gli inviti privati sono token casuali, memorizzati solo come hash e con scadenza. Una richiesta privata necessita del token valido.
- I dati del profilo e il telefono verificato non sono accessibili agli altri account. Il contatto WhatsApp dell’Host è separato e viene mostrato solo su consenso agli ammessi.
- Numeri verificati, OTP temporanei, supporto e audit non sono leggibili dal client. I report sono rate-limited e hanno accesso moderazione separato.

## OTP e anti-abuso

Le Edge Functions locali `phone-otp-start` e `phone-otp-verify` richiedono JWT ed email confermata, origine esatta, CAPTCHA e limiti server. Twilio controlla il codice; la tabella numero temporaneo scade dopo 10 minuti ed è cancellata dopo la verifica. Nel database resta HMAC-SHA256, non il numero in chiaro. Limiti iniziali: un invio ogni 60 secondi, 5 invii al giorno, 8 tentativi per finestra di 10 minuti. Queste funzioni non sono ancora pubblicate; configurare quote provider/IP e cleanup prima dell’uso reale.

## Supporto e amministrazione

Il pannello locale mostra dati fittizi. La modalità online usa la allowlist privata del database, una sessione ancora valida, account non anonimo/bloccato e MFA TOTP `aal2` verificato negli ultimi 15 minuti. Il ruolo nei metadati serve solo alla navigazione. Le RPC verificano nuovamente il permesso anche nelle richieste dirette; `admin-console` non usa una service-role. Revoca e logout impediscono le successive operazioni sensibili. Ticket e audit vengono modificati atomicamente; le operazioni Admin sono limitate a 60/minuto. Vedi ADMIN-SETUP.md.

`admin-console` v1 è pubblicata, ma mancano il primo amministratore e un login OAuth/MFA reale. `support-request` resta da configurare e distribuire: richiede sessione, CAPTCHA e quota; nome/email di ricontatto solo con consenso specifico.

## Da fare prima di utenti reali

1. Configurare SMTP, Turnstile, redirect HTTPS e origine CORS.
2. Distribuire e provare le Edge Functions usando solo secret server-side.
3. Testare sessioni reali distinte, accesso anonimo e ruoli; provare capienza concorrente, invito scaduto, cambio visibilità, recupero account e sede privata.
4. Implementare consegna push/reminder, cleanup OTP, esportazione/cancellazione e retention.
5. Aggiornare privacy, cookie e termini ai provider effettivi e ai flussi attivi.

Non attivare `onlineReady: true` finché le prove end-to-end non sono passate. Non includere service-role, Twilio, Turnstile secret, HMAC o Stripe secret in file pubblici, commit, log o chat.

## Isolamento client e cache

In modalità cloud il codice ignora i dati della demo nel browser e rifiuta le scritture locali di account/eventi/notifiche. Il cambio account ripulisce anche i modali nascosti e scarta feed/profili tardivi. Il service worker in preparazione v11 conserva soltanto file pubblici, usa chiavi canoniche senza parametri invito, esclude API/richieste autorizzate e rispetta `no-store`/`private`. Le risposte Admin hanno `Cache-Control: no-store`. Questo blocco frontend non è ancora nel deploy pubblico 2.0.2.

Il controllo automatico non equivale a un penetration test completo. La CSP mantiene handler inline; una sessione rubata prima della revoca e entro la finestra MFA resta un rischio da ridurre. Le tabelle private senza policy hanno diniego RLS predefinito e nessun privilegio client; gli avvisi generici sulle RPC SECURITY DEFINER richiedono revisione mirata, non sono rimossi nascondendoli.
