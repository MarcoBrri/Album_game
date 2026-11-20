# Club Quiz — directory con foto e gioco per imparare i nomi

Sito statico (una pagina) + database Supabase.
- **Visitatori** (senza account): aprono il link del gruppo, guardano la directory, giocano e **propongono** nuove persone.
- **Amministratore** (con account): crea la directory, **approva o rifiuta** le proposte, modifica ed elimina i profili.

Le proposte restano invisibili a tutti, tranne all'amministratore, finché non vengono approvate.

## 1. Database (Supabase) — GIÀ FATTO per il progetto «Album's game»
Schema applicato e `config.js` già compilato. I passi sotto servono solo per ripeterlo su un altro progetto.

1. Vai su https://supabase.com, crea un account e premi **New project**. Scegli una regione europea e annota la password del database.
2. Nel progetto apri **SQL Editor → New query**, incolla tutto il contenuto di `supabase/schema.sql` e premi **Run**. Deve finire senza errori.
3. Apri **Project Settings → API** e copia due valori: **Project URL** e **anon public key**.
4. Incollali nel file `config.js` al posto dei segnaposto. (La *anon key* è pensata per stare nel browser: la sicurezza è nelle regole del database.)

## 2. Accesso amministratore
- Nelle impostazioni **Authentication** (provider Email) per i primi test disattiva **Confirm email**, altrimenti ogni registrazione richiede un link ricevuto per email (il servizio email predefinito di Supabase ha limiti molto bassi).
- Apri il sito, premi **Registrati** con la tua email e una password (minimo 8 caratteri): quell'account sarà l'amministratore.
- Quando hai creato il tuo account, nelle impostazioni Authentication **disattiva le nuove registrazioni** (opzione tipo «Allow new users to sign up»): così nessun altro potrà creare directory.

## 3. Pubblica il sito
Scegli una delle due strade (servono solo i file `index.html` e `config.js`):
- **Netlify Drop** (la più rapida): vai su https://app.netlify.com/drop e trascina la cartella. Ottieni subito un indirizzo pubblico.
- **GitHub Pages**: crea un repository, carica `index.html` e `config.js`, poi **Settings → Pages → Deploy from a branch → main / (root)**. L'indirizzo sarà `https://<utente>.github.io/<repository>/`.

## 4. Prova le due viste
1. Apri il sito, accedi, scrivi il nome del gruppo e premi **Crea la directory**. Copia il **link** (finisce con `#nome-xxxxx`).
2. Apri quel link in una **finestra privata** del browser: è la **vista utente**. Premi **Aggiungi una persona** e salva: vedrai «Grazie!» e la persona non compare.
3. Torna nella finestra dell'amministratore e ricarica: in cima c'è **Da approvare (1)**. Premi **Approva**: ora la persona è visibile nella directory e nei giochi.

## Cose da sapere
- **Privacy**: foto e nomi sono dati personali (nLPD). Informa i partecipanti e usa il pulsante Elimina se qualcuno chiede di essere tolto. Scegli la regione europea del progetto.
- **Foto**: vengono ridimensionate a 240×240 pixel e salvate nel database (circa 15–25 KB ciascuna).
- **Spam**: ogni directory accetta al massimo 200 proposte in attesa. Non c'è un CAPTCHA: se il link finisse in mani sbagliate, basta rifiutare le proposte.
- **Link**: il link contiene un codice casuale difficile da indovinare, ma chi lo riceve può inoltrarlo.
- **Piano gratuito**: Supabase mette in pausa i progetti inattivi per più settimane; si riattivano dal pannello.

## Scheda personalizzabile

Alla creazione di una directory l'amministratore sceglie un modello (Azienda, Sci club, Vuoto) e definisce quali informazioni raccogliere per ogni persona: campi di testo libero, a scelta singola o a scelta multipla, con eventuali dettagli (massimo 8 campi). Foto e nome ci sono sempre; il soprannome è facoltativo. La struttura si può cambiare in seguito dal pulsante «Modifica la scheda».

Se avevi già installato una versione precedente, esegui una volta `supabase/migrazione-campi.sql` nello SQL Editor di Supabase (le directory esistenti ricevono la struttura «Sci club»). Per una nuova installazione basta `supabase/schema.sql`.

## Manutenzione

- **Controllo automatico**: il workflow `.github/workflows/keepalive.yml` interroga il database ogni 3 giorni, così il progetto Supabase gratuito non va in pausa. Si può lanciare a mano da GitHub → Actions → «Tieni attivo Supabase» → Run workflow. Attenzione: GitHub sospende i workflow programmati se il repository non riceve modifiche per 60 giorni (manda un'email prima): in quel caso basta riattivarlo dalla scheda Actions.
- **Password dimenticata**: perché il link nell'email riporti all'app, in Supabase → Authentication → URL Configuration imposta come *Site URL* l'indirizzo GitHub Pages dell'app (es. `https://<utente>.github.io/<repository>/`).
- **Registrazioni**: le nuove registrazioni admin sono disattivate (Authentication → Sign In / Providers → «Allow new users to sign up»). Per aggiungere un amministratore: Authentication → Users → Add user.
- **Backup**: nella pagina Impara, da admin, il pulsante «Scarica backup» salva un file `.sql` con struttura, persone (foto comprese) e classifica. Per ripristinare da zero: crea un progetto Supabase, esegui `supabase/schema.sql`, crea l'utente admin con la stessa email, poi esegui il file di backup nello SQL Editor. Conserva i backup in un posto privato: contengono le foto.
- **Libreria Supabase**: è fissata alla versione 2.119.2 con controllo d'integrità. Per aggiornarla vanno cambiati insieme numero di versione e codice `integrity` in `index.html`.
