# TROVAT1O · impostazioni cloud e sicurezza

## Modalità corrente

La preview online e quella locale sono demo; `onlineReady` è `false`. La registrazione cloud non è attiva. Il database Supabase ha schema/RLS applicati ma non contiene profili o eventi e non ha Edge Functions pubblicate. La chiave Supabase publishable/anon non è un segreto, ma non è inserita nell’attuale configurazione del client.

## Account previsti

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

Il pannello locale mostra dati fittizi. La modalità online prevista richiede claim server `admin` e MFA `aal2`; nascondere un pulsante nel browser non è autorizzazione. Le richieste di supporto richiedono sessione, CAPTCHA e quota; nome/email di ricontatto solo con consenso specifico. Le funzioni `admin-console` e `support-request` esistono solo nel sorgente e non sono pubblicate.

## Da fare prima di utenti reali

1. Configurare SMTP, Turnstile, redirect HTTPS e origine CORS.
2. Distribuire e provare le Edge Functions usando solo secret server-side.
3. Testare sessioni reali distinte, accesso anonimo e ruoli; provare capienza concorrente, invito scaduto, cambio visibilità, recupero account e sede privata.
4. Implementare consegna push/reminder, cleanup OTP, esportazione/cancellazione e retention.
5. Aggiornare privacy, cookie e termini ai provider effettivi e ai flussi attivi.

Non attivare `onlineReady: true` finché le prove end-to-end non sono passate. Non includere service-role, Twilio, Turnstile secret, HMAC o Stripe secret in file pubblici, commit, log o chat.
