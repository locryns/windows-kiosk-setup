# Windows Kiosk Setup (Edge fullscreen)

Transforme un laptop Windows 11 **Home** en kiosque dédié à une seule application
web, en mode plein écran Edge. Conçu pour des déploiements terrain (borne club,
écran mural) où Windows 11 Home ne permet pas d'utiliser l'outil officiel
**Assigned Access**.

Déployé en production sur un ASUS Vivobook Go E1504FA (AMD Ryzen, 8 GB RAM,
Wi-Fi) pointant sur `https://fdm.awbb.be`.

## Caractéristiques

- **Auto-login** sur un compte standard dédié (sans saisie de mot de passe au
  démarrage).
- **Edge en mode `--app=URL --start-fullscreen`** : fenêtre PWA sans barre
  d'URL, profil **persistant** (mots de passe sauvegardés et cookies conservés).
  On n'utilise **pas** `--kiosk --edge-kiosk-type=fullscreen` car ce mode force
  une session **InPrivate** -- autofill désactivé, rien n'est conservé entre
  redémarrages. Le confinement URL passe par policies (ci-dessous).
- **URL sandbox** : `URLBlocklist=['*']` + `URLAllowlist` sur l'hôte kiosk et
  `*.{domaine-apex}` (ex. `*.awbb.be`) + `NewWindowsInApp=1`.
- **Watchdog** : si Edge ferme, il est relancé dans les 10 secondes.
- **Verrouillage clavier** : Win, context menu, Task Manager, Registry Editor,
  CMD interactif, centre de notifications, lock screen.
- **Nettoyage** : suppression d'une trentaine d'UWP (Bing, Copilot, Xbox, Teams,
  Outlook, Paint, OneDrive UI, ASUS junk, Widgets, Phone Link…) et désactivation
  d'une vingtaine de services non nécessaires à un kiosque web.
- **Power** : tous les timeouts (veille, hibernation, écran, disque) à jamais.
- **Compte admin préservé** pour maintenance SSH à distance.

## Prérequis

1. Machine Windows 11 Home (ou Pro) fraîche.
2. Deux comptes locaux :
   - `bcsilly` (ou autre) : compte **standard** qui exécutera le kiosk.
   - `suppo` (ou autre) : compte **Administrateur** pour l'exécution des scripts
     et l'accès distant.
3. OpenSSH Server installé côté Windows avec votre clé publique dans
   `C:\ProgramData\ssh\administrators_authorized_keys` (droits NT AUTHORITY\SYSTEM
   + Administrators uniquement via `icacls`).
4. Edge déjà présent (fourni avec Windows). Les scripts détectent
   automatiquement `Program Files (x86)` et `Program Files`.

## Déploiement

Depuis le Mac de support, les scripts sont poussés via SCP puis exécutés via
SSH. Chacun se lance en session PowerShell **élevée** (compte admin).

```sh
# Variables
HOST=192.168.1.20          # ou IP Tailscale (bc-silly-kiosk)
ADMIN=suppo
KEY=~/.ssh/secretive-ssh.pub

# 1. Upload
scp -i $KEY *.ps1 $ADMIN@$HOST:C:/Users/$ADMIN/

# 2. Phase 1 - Supprimer bloatware UWP
ssh -i $KEY $ADMIN@$HOST "powershell -ExecutionPolicy Bypass -File C:\\Users\\$ADMIN\\remove-bloatware.ps1"

# 3. Phase 2 - Désactiver services inutiles
ssh -i $KEY $ADMIN@$HOST "powershell -ExecutionPolicy Bypass -File C:\\Users\\$ADMIN\\disable-services.ps1"

# 4. Phase 3-5 - Kiosk (auto-login + Edge + lockdown)
ssh -i $KEY $ADMIN@$HOST "powershell -ExecutionPolicy Bypass -File C:\\Users\\$ADMIN\\setup-kiosk.ps1 -KioskUser bcsilly -KioskPassword oneteam -KioskURL https://fdm.awbb.be"

# 5. Reboot
ssh -i $KEY $ADMIN@$HOST "shutdown /r /t 5 /f"
```

> **Attention** : si le compte kiosk a déjà un mot de passe et des mots de
> passe Edge sauvegardés, passer `-KioskPassword ""` ou le mot de passe exact
> **actuel**. Forcer un reset via `net user` régénère les clés DPAPI et rend
> illisibles les mots de passe Edge existants.

## Maintenance distante

Le laptop installe Tailscale avec un auth-key pré-autorisé :

```sh
# Mac
ssh -i ~/.ssh/secretive-ssh.pub suppo@100.64.X.X "..."
```

Edge ne peut plus être fermé par l'utilisateur (watchdog). Pour arrêter le
kiosk afin d'intervenir :

```powershell
# Stopper launcher + watchdog + Edge
schtasks /End /TN KioskLauncher 2>$null
Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force
taskkill /IM cmd.exe /FI "WINDOWTITLE eq watchdog*" /F
```

Pour relancer sans reboot :

```powershell
Start-Process "C:\Kiosk\launch-kiosk.bat"
Start-Process "C:\Kiosk\watchdog.bat"
```

## Fichiers installés sur la machine

| Chemin | Rôle |
|---|---|
| `C:\Kiosk\launch-kiosk.bat` | Launcher : kill Edge en boucle puis lance kiosk |
| `C:\Kiosk\watchdog.bat` | Loop 10 s : relance Edge s'il n'est plus actif |
| `%KioskUser%\...\Startup\KioskLauncher.lnk` | Démarrage auto du launcher |
| `%KioskUser%\...\Startup\KioskWatchdog.lnk` | Démarrage auto du watchdog |

## Pièges rencontrés (gagnez 3 h de debug)

- **`--kiosk` force InPrivate** : d'après la [doc officielle Edge][msdoc],
  `--kiosk --edge-kiosk-type=fullscreen` (Digital Signage) **et**
  `--edge-kiosk-type=public-browsing` démarrent une **session InPrivate**.
  Conséquences : autofill désactivé, cookies/mots de passe non persistés
  entre redémarrages, impossible d'utiliser les credentials sauvegardés.
  Fix : basculer en `--app=URL --start-fullscreen` (profil persistant, fenêtre
  chromeless) et confiner les URLs via `URLAllowlist`/`URLBlocklist`.
- **Edge startup boost** : `--win-session-start --no-startup-window` pré-charge
  Edge avant que le launcher ne s'exécute. La nouvelle instance lancée avec
  `--app=` rejoint alors la session pré-existante **dans une fenêtre normale
  avec barre d'URL**. Fix : policies `StartupBoostEnabled=0` +
  `BackgroundModeEnabled=0` (appliquées par `setup-kiosk.ps1`) et kill loop
  agressif dans `launch-kiosk.bat`.
- **Raccourci PWA Edge** : `Install site as app` crée un `.lnk` dans le dossier
  Startup qui lance Edge `--app-id=... --app-url=...` — même effet que ci-dessus.
  Le setup les nettoie automatiquement.
- **DisableCMD=1** : bloque aussi les `.bat`. Toujours utiliser **`DisableCMD=2`**
  pour bloquer CMD interactif tout en laissant les batchs tourner.
- **Password Edge** : `net user <account> ""` puis `net user <account> <pwd>`
  régénère les master keys DPAPI du compte. Edge détecte que son `encrypted_key`
  (ou une ancienne AES key) n'est plus déchiffrable et **met le flag
  `clearing_undecryptable_passwords=True`** dans `Preferences`. Les mots de
  passe sauvegardés deviennent irrécupérables, même avec la bonne clé DPAPI.
  Ne jamais forcer un reset si les mots de passe Edge sont utiles.
- **Windows 11 Home** : pas de GPO, pas d'Assigned Access, pas de Shell Launcher.
  Tout passe par registre utilisateur + startup shortcuts.

[msdoc]: https://learn.microsoft.com/en-us/deployedge/microsoft-edge-configure-kiosk-mode

## Licence

MIT — à adapter à votre contexte. Fait pour un usage interne, testé sur un
unique laptop. Faites vos backups.
