# HTTPS locale con Wampserver: correzione SAN e installazione della CA

La correzione PHP risolve il caso verificato: certificato con CN corretto, ma senza **Subject Alternative Name (SAN)**, e Chrome con errore `NET::ERR_CERT_COMMON_NAME_INVALID`.

L'installer aggiunge anche l'importazione della CA gia presente in Wamp. Usa i normali menu HTTPS di Wamp per tutti i nuovi siti, senza eseguire mkcert ogni volta.

Progetto indipendente, non distribuzione ufficiale di Wampserver. La correzione PHP e stata confermata funzionante sul PC originario. Il nuovo installer PowerShell richiede ancora una verifica completa su Windows: [stato dei test](docs/VALIDATION.md).

## Installazione

Occorrono Windows, Windows PowerShell 5.1 o successivo, Wamp con HTTPS nativo gia inizializzato e privilegi amministrativi.

1. Scarica ed estrai la repository.
2. Chiudi Wamp dal menu dell'icona nella barra di sistema.
3. Avvia **`Install.cmd`** e accetta la richiesta di Windows per i privilegi amministrativi.
4. Riapri Wamp. Per i siti gia configurati, disattiva e riattiva HTTPS dal menu: i vecchi certificati devono essere rigenerati.
5. Riavvia i servizi Wamp e il browser.

Il percorso predefinito e `C:\wamp64`. Per un percorso diverso, apri PowerShell nella cartella estratta:

```powershell
.\Install.cmd -WampRoot 'D:\wamp64'
```

Solo importazione della CA, utile se hai gia sostituito manualmente il PHP:

```powershell
.\Install.cmd -RootOnly
```

Anteprima senza modifiche:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-WampHttps.ps1 -WhatIf
```

## Cosa viene fatto

- Verifica la compatibilita del PHP tramite hash e crea un backup prima della sostituzione. Versioni diverse o modificate non vengono sovrascritte.
- Legge `C:\wamp64\bin\Certs\Cacerts\Certificat.crt` (oppure il percorso Wamp scelto), controllando che sia un singolo certificato pubblico CA attualmente valido e autoemesso.
- Mostra soggetto e impronta del certificato.
- Importa la CA in **Computer locale → Autorita di certificazione radice attendibili**, per tutti gli utenti del computer. Se la stessa CA e gia presente, non la duplica.
- Ripristina il PHP originale se l'importazione della CA fallisce dopo la sostituzione.

L'importazione concede fiducia ai certificati emessi da questa CA: usa una tua installazione Wamp attendibile e conserva privata la sua chiave. Nel pacchetto non ci sono chiavi private o certificati personali. Non viene scaricata una CA condivisa.

Se manca `Certificat.crt`, inizializza prima HTTPS con Wamp. L'installer non crea siti o regole DNS e non rigenera da solo i certificati esistenti. Non modifica `openssl.cnf` o ESET. I nomi indicati in `ServerAlias` non vengono aggiunti automaticamente al SAN.

Una volta installata la CA, per i siti futuri basta il menu HTTPS di Wamp. Dopo una reinstallazione o una nuova CA puo servire ripetere l'importazione. Dopo un aggiornamento Wamp verifica che la correzione PHP sia ancora presente.

## Ripristino

Chiudi Wamp e ricopia il backup `changeToHttps.php.san-backup-<id>` su `scripts\changeToHttps.php`. Poi riapri Wamp.

La fiducia nella CA e indipendente dal PHP: per rimuoverla intenzionalmente usa `certlm.msc`, controlla l'impronta esatta prima della rimozione e considera che tutti i siti emessi da quella CA perderanno la fiducia.

[Dettagli tecnici, test e licenza](README.md) · [Patch per i manutentori](patches/changeToHttps-san.patch).
