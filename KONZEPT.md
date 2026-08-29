# Konzept: Home-Assistant-Steuerung für SailfishOS

Stand: 2026-08-28

## 1. Ziel

Native SailfishOS-App (Silica-QML), die eine lokale Home-Assistant-Instanz
steuert. Kein Companion-App-Klon, sondern ein schlanker, auf das Nötigste
reduzierter Client -- Fokus auf schnellem Zugriff auf ein paar Entities statt
auf Vollständigkeit gegenüber der offiziellen Android/iOS-App.

**Verbindung:** nur lokales Netz (REST/WebSocket direkt gegen die HA-Instanz,
kein Nabu Casa/Reverse-Proxy). Remote-Zugriff ist explizit auf Ausbaustufe 3
verschoben und dort optional -- vermeidet TLS/Proxy-Setup, bevor der
Kernclient überhaupt funktioniert.

**Auth:** Long-Lived Access Token (in HA unter Profil → Sicherheit erzeugt),
als `Authorization: Bearer <token>` Header. Kein OAuth-Flow -- für einen
Single-User-Client auf einem eigenen Gerät ist das ausreichend und deutlich
einfacher als HA's vollen OAuth2-Login-Flow nativ nachzubauen.

## 2. Ausbaustufen

### Stufe 1 -- Basis-Client (lokal, manuell) -- **Scaffold steht, s. Abschnitt 3**
- Config-Seite: HA-URL + Long-Lived Access Token
- Liste aller `light`/`switch`-Entities (REST `GET /api/states`)
- Toggle per Service-Call (`POST /api/services/<domain>/toggle`)
- Manuelles Pull-to-refresh, kein Push

### Stufe 2 -- Dashboard & Echtzeit
- WebSocket-API statt Polling → Live-State-Updates
- Gruppierung nach HA-Areas/Rooms (Area Registry)
- Weitere Domains: Climate (Ziel-Temp), Cover, Media Player (Basic-Controls)
- Szenen/Skripte als Favoriten-Kacheln
- Lokaler SQLite-Cache für Offline-Ansicht (letzter bekannter Zustand)

### Stufe 3 -- Systemintegration & Remote
- Lockscreen/Events-View-Widget für 1-2 Lieblings-Entities
- Push-Benachrichtigungen von HA → Sailfish. Zwei Varianten abgewogen:
  - **Variante A** (eigener Relay-Server + natives Background, dauerhafte
    Verbindung): niedrige Latenz, aber hoher Aufwand -- braucht ein RPM
    außerhalb der Sailjail-Sandbox (nicht Store-kompatibel).
  - **Variante B** (periodischer Background-Sync via Nemo Keepalive,
    `BackgroundActivity`): kein echtes Push, Verzögerung im Bereich des
    Poll-Intervalls, aber Store-kompatibel und baut direkt auf dem
    Stufe-1-REST-Client auf.
  - **Entscheidung 2026-08-28: mit Variante B begonnen** (s. Abschnitt 4) --
    Variante A bleibt Option für später, falls sich Sekunden- statt
    Minuten-Latenz als nötig erweist.
- Optional: Device-Tracker (Standort an HA melden, Presence Detection)
- Remote-Zugriff außerhalb des lokalen Netzes (Nabu Casa oder eigener
  Reverse-Proxy mit TLS)

## 3. Update 2026-08-28: Projekt-Scaffold angelegt

Grundgerüst unter `/home/silly/sailhacontrol` erstellt, analog zum Aufbau von
`sailtalerwallet` (`.pro`/`.desktop`/`rpm/*.spec` nach Standard-SFOS-Template,
`org.nemomobile.configuration` für Settings-Persistenz).

**Architektur-Unterschied zu sailtalerwallet:** kein natives C++-Bridge-Objekt
nötig -- Home Assistants REST-API ist reines HTTP+JSON, das QML-eigene
`XMLHttpRequest` reicht (`qml/lib/HaApi.js`). `main.cpp` lädt daher nur die
QML-Root-View, ohne `qmlRegisterType`/Context-Properties.

**Stand der Dateien:**
- `harbour-hacontrol.pro`, `.desktop` (Permissions=Internet, kein
  Camera/Location), `src/harbour-hacontrol.cpp` -- Boilerplate, ungetestet
- `qml/pages/SettingsPage.qml` -- HA-URL + Token, per `ConfigurationValue`
  gespeichert (Klartext -- ausreichend für lokalen Prototyp, siehe TODO)
- `qml/pages/FirstPage.qml` -- Entity-Liste (light/switch) mit Toggle-Switch,
  Pull-to-refresh, Fehleranzeige
- `qml/lib/HaApi.js` -- `getStates()`, `callService()`
- `rpm/harbour-hacontrol.spec` -- Version 0.1

**Noch offen / nicht verifiziert:**
- **Kein App-Icon** -- `SAILFISHAPP_ICONS` in der `.pro` referenziert
  `icons/<size>/harbour-hacontrol.png`, die Dateien existieren noch nicht.
  Muss vor dem ersten `sfdk build`/Packaging ergänzt werden (oder die Zeile
  vorübergehend auskommentieren).
- **Noch nicht gebaut/getestet** -- anders als sailtalerwallet gibt es noch
  kein reales Testgerät-Setup für dieses Projekt. Nächster Schritt: mit
  `sfdk` gegen ein SailfishOS-Target bauen und gegen eine echte
  HA-Instanz im lokalen Netz verifizieren (URL + Token in Settings eintragen,
  Refresh auslösen, Toggle prüfen).
- Token-Speicherung per `org.nemomobile.configuration` ist Klartext in
  `~/.config/harbour-hacontrol/`. Für Stufe 1 akzeptiert; falls das Gerät
  geteilt wird, auf Sailfish Secrets API umstellen.
- Kein Git-Repo initialisiert -- bewusst offen gelassen, bis der erste Build
  gegen echte Hardware verifiziert ist.

## 4. Update 2026-08-28: Stufe 3 / Variante B (Background-Poll + Notification) implementiert

Begonnen ohne dass Stufe 1 bereits auf Hardware verifiziert wurde -- explizit
so gewünscht. Umgesetzt:

- **`qml/pages/FirstPage.qml`**: jede Entity hat jetzt ein Kontextmenü
  ("Bei Änderung benachrichtigen" / "Benachrichtigung deaktivieren"), das die
  Entity-ID in `ConfigurationValue` `/apps/harbour-hacontrol/watchedEntities`
  (kommagetrennt) auf-/abnimmt. Beobachtete Entities zeigen ein kleines
  "benachrichtigt"-Label neben dem Switch.
- **`qml/harbour-hacontrol.qml`**: `BackgroundJob` (aus `Nemo.KeepAlive`, s.
  Abschnitt 5 -- ursprünglich als `BackgroundActivity`/`org.nemomobile.keepalive`
  geschrieben, das war falsch) mit `frequency: TenMinutes`, `enabled: true`.
  Bei jedem `onTriggered`: `HaApi.getStates()` gegen alle beobachteten
  Entities, Vergleich mit zuletzt bekanntem Zustand (persistiert als JSON in
  `ConfigurationValue` `/apps/harbour-hacontrol/lastKnownStates`, damit ein
  App-Neustart nicht bei jeder beobachteten Entity erneut "Änderung" meldet).
  Bei tatsächlicher Änderung: dynamisch erzeugtes `Notification`-Objekt
  (`org.nemomobile.notifications`) via `Qt.createQmlObject()`, `.publish()`.
- **`rpm/harbour-hacontrol.spec`**: `Requires: nemo-qml-plugin-notifications-qt5,
  libkeepalive` ergänzt (reine QML-Plugins, keine BuildRequires nötig, da
  nicht gegen sie gelinkt wird).

**Noch offen / nicht verifiziert (zusätzlich zu Abschnitt 3):**
- **Kernrisiko, auf Hardware zu prüfen**: `BackgroundActivity` hält den
  Prozess nur wach, solange er ohnehin resident ist (Vordergrund oder
  kürzlich minimiert) -- ein vollständig vom System beendeter App-Prozess
  wird dadurch **nicht** neu gestartet. Für "wirklich im Hintergrund, App nie
  geöffnet" bräuchte es einen separaten Daemon mit Autostart/D-Bus-Aktivierung
  (das wäre dann praktisch Variante A). Muss auf dem echten Testgerät beobachtet
  werden: bleibt der Prozess nach "App schließen" (Home-Geste) lange genug
  resident, damit 10-Minuten-Polls überhaupt ankommen?
- Unklar, ob der asynchrone `XMLHttpRequest`-Call zuverlässig innerhalb des
  IPHB-Wachfensters abschließt, bevor die CPU wieder in Suspend geht --
  bekannte Unsicherheit bei `BackgroundActivity` + Netzwerk-I/O, nicht anhand
  von Dokumentation abschließend geklärt.
- Modulnamen (`org.nemomobile.keepalive`, `org.nemomobile.notifications`)
  passen zum bereits bei sailtalerwallet bestätigten Legacy-Namespace-Stil
  (`org.nemomobile.configuration`), aber die exakte QML-API (`run()`/`wait()`-
  Zustandsmaschine von `BackgroundActivity`) ist aus Erinnerung geschrieben,
  nicht gegen SDK-Doku verifiziert -- erster Build wird das aufdecken.
- Kein Picker für "welche Entity beobachten" außerhalb von FirstPage -- man
  muss die Entity vorher schon in der Liste sehen (Light/Switch), um sie per
  Kontextmenü zu markieren.

## 5. Update 2026-08-28 (Teil 2): SDK installiert, erster Build + Emulator-Test

SailfishOS-SDK 3.13.5 lokal installiert unter `/home/silly/SailfishOS`
(`sfdk` unter `/home/silly/SailfishOS/bin/sfdk`, nicht im PATH). Verfügbare
Targets: `SailfishOS-5.1.0.11-{aarch64,armv7hl,i486}` und
`SailfishOS-5.0.0.62-aarch64`. Emulator (`SailfishOS-5.1.0.11`) ist i486 --
für Emulator-Tests muss gegen das **i486-Target** gebaut werden, nicht
aarch64 (das RPM für die reale Jolla Phone bleibt aarch64, s.
sailtalerwallet-Workflow).

**Placeholder-Icons erzeugt** (`icons/<size>/harbour-hacontrol.png`, per
ImageMagick, blauer Hintergrund + "HA"-Schriftzug) -- nur Platzhalter, kein
echtes App-Icon-Design.

**Build- und Deploy-Workflow, der funktioniert hat:**
```
sfdk config target=SailfishOS-5.1.0.11-i486
sfdk config specfile=rpm/harbour-hacontrol.spec
sfdk build
sfdk config device="Sailfish OS Emulator 5.1.0.11"
sfdk deploy --sdk          # baut, rsynct RPMS/ auf den Emulator, installiert
```
Wichtig: `sfdk config <var>=<value>` setzt nur "Session-Scope", der **nicht**
über separate Shell-Aufrufe hinweg persistiert (jeder Bash-Tool-Call ist eine
neue Shell) -- alle drei `config`-Zeilen und der eigentliche Befehl müssen in
derselben Shell-Session laufen (`&&`-verkettet), sonst greift der stehende
**globale** Default (der hier zufällig auf ein fremdes Projekt
`harbour-nemoai` zeigte, vermutlich Altlast aus einer früheren Session).

**Emulator-Zugriff ohne `devel-su`:** anders als auf der Jolla Phone in
sailtalerwallet gibt es auf diesem Emulator-Image kein `devel-su`-Binary --
stattdessen funktioniert passwortloses `sudo` als `defaultuser` (z. B.
`sudo -n journalctl -f`). SSH-Key liegt unter
`~/SailfishOS/vmshare/ssh/private_keys/sdk`, Port `2223`, Host `127.0.0.1`.

**Zwei echte Bugs gefunden und gefixt** (genau der Zweck des Tests -- die
Stufe-3-QML war "aus Erinnerung" geschrieben, s. Abschnitt 4):
1. `import org.nemomobile.keepalive 1.0` existiert in SFOS 5.1 **nicht** --
   nur noch `Nemo.KeepAlive`. Zugehöriges RPM-Paket heißt `libkeepalive`
   (nicht `nemo-qml-plugin-keepalive-qt5`, das Paket existiert schlicht
   nicht).
2. Innerhalb von `Nemo.KeepAlive` heißt der Typ **`BackgroundJob`**, nicht
   `BackgroundActivity`, und hat eine andere API: `enabled`/`frequency`/
   `onTriggered`/`finished()` statt `run()`/`wait()`/`onRunning`. Das
   `run()`/`wait()`-Muster war aus einer älteren/anderen Keepalive-API in
   Erinnerung, existiert so in dieser Version nicht.

Beide Fixes in `qml/harbour-hacontrol.qml` und `rpm/harbour-hacontrol.spec`
eingespielt, dann erneut gebaut/deployed/gestartet -- Journal zeigt danach
**keine** Modul- oder QML-Fehler mehr, nur zwei harmlose Deprecation-Warnungen
(`org.nemomobile.configuration`/`org.nemomobile.notifications` funktionieren
noch, sind aber als Legacy markiert -- Migration auf `Nemo.Configuration`/
`Nemo.Notifications` wäre ein sauberer, nicht dringender Folgeschritt).

**Was dieser Test NICHT abgedeckt hat** (weiterhin offen):
- Keine echte HA-Instanz vorhanden -- `FirstPage` wurde nur im
  unkonfigurierten Zustand gesehen ("Noch nicht konfiguriert"-Hinweis), nie
  gegen echte Entities getestet (Refresh, Toggle, Kontextmenü-Interaktion,
  tatsächliches Feuern einer `Notification`).
- Keine UI-Interaktion getestet (kein Display/VNC in dieser Umgebung
  angebunden) -- nur Prozessstart + Journal-Log geprüft. `ContextMenu` in
  `FirstPage.qml` wird erst bei tatsächlichem Long-Press instanziiert und war
  damit nicht Teil dieses Tests.
- Die in Abschnitt 4 genannten Kernrisiken (Prozess-Residency von
  `BackgroundJob`/Keepalive im Hintergrund, ob der async `XMLHttpRequest`
  rechtzeitig fertig wird) bleiben ungeklärt -- das lässt sich nur auf
  echter Hardware über einen längeren Zeitraum beobachten, nicht im Emulator
  in einer kurzen Testsession.

## 6. Update 2026-08-29: Area-Gruppierung, Sensoren, v0.2-Release

Gegen die echte HA-Instanz des Nutzers verifiziert (lokales Netz erreichbar,
sowohl vom Emulator als auch vom echten Gerät aus -- kein NAT-Problem).
Zwei API-Bugs beim ersten Emulator-Run gefunden und gefixt (`Nemo.KeepAlive`
statt `org.nemomobile.keepalive`, `BackgroundJob` statt `BackgroundActivity`
-- Details s. Abschnitt 5/Memory). Danach:

- **Area/Room-Gruppierung + Sensoren** (Vorgriff auf Stufe 2) über
  `HaApi.getAreaMap()`: `/api/template`-Endpoint mit Jinja2-`area_name()`
  statt WebSocket-API, um REST-only zu bleiben. HAs sandboxed Jinja blockt
  `dict.update()` als "unsafe" -- Workaround ist der `namespace(items=[])`
  + Listenkonkatenation-Idiom. `sensor`-Entities mit `device_class`
  `temperature`/`humidity`/`pressure`/`atmospheric_pressure` werden
  read-only mit Wert (eine Nachkommastelle) + Einheit angezeigt.
  Ein-/ausklappbar pro Raum über ein flaches `ListModel`
  (Header-/Entity-Zeilen gemischt) statt nested ListModels, wegen
  SilicaListView-Virtualisierung bei den teils >100 Entities pro Instanz.
- **`ScrollingLabel`-Komponente** (`qml/components/ScrollingLabel.qml`) für
  einmaliges Durchscrollen langer Namen. **Bug gefunden+gefixt**: fehlende
  `height` (nur `clip:true`) machte den Text komplett unsichtbar --
  Screenshot-gestützt entdeckt, User meldete "sehe kein Text".
- **Toggle-Timing-Fix**: `postToggleRefreshTimer` (1s) statt sofortigem
  Refresh nach `toggle()` -- HAs Service-Response bestätigt nur den
  angenommenen Befehl, nicht dass Zigbee/Matter-Geräte den neuen Zustand
  schon zurückgemeldet haben. Vom Nutzer bestätigt: "toggle geht jetzt
  sauber".
- **Reales Gerät (Jolla Phone, aarch64)**: erste Installation hing im
  `sailjail`-Wrapper fest (nie bis zum eigentlichen Binary durchexekt) --
  Ursache war ein `lipstick-windowprompt`-Berechtigungsdialog
  (Internetzugriff), der auf dem Gerätebildschirm bestätigt werden musste.
  Auf dem Emulator taucht dieser Dialog nicht auf (Dev-Mode überspringt
  ihn). Nach Bestätigung: App läuft sauber, identisches Bild wie im
  Emulator (Raumliste, Ein-/Ausklappen, Sensoren).
- **v0.2-Release**: Public-Repo unter `github.com/silly82/sailhacontrol`
  angelegt, drei RPMs gebaut (i486/Emulator, aarch64/neue Telefone --
  beide getestet; armv7hl/alte Telefone -- baut sauber, aber **ungetestet**,
  da keine armv7hl-Hardware zur Verfügung stand). Doku (`README.md`) auf
  Englisch verfasst, mit Schweizer-Hochdeutsch-Abschnitt danach (kein
  „ß", `ss` statt).

## 7. Update 2026-08-29 (Teil 2): Swipe-Navigation, v0.3-Release

- **Swipe statt Pull-down-Menüpunkt**: Die Sensor-Übersicht war zunächst
  eine eigene, per Pull-down-Menü gepushte `SensorsPage.qml`. Umgebaut zu
  zwei nebeneinander liegenden Sub-Views (`qml/views/RoomsView.qml`,
  `qml/views/SensorsView.qml`), gewechselt per horizontalem Swipe in einer
  gemeinsamen `SilicaFlickable` (`flickableDirection: HorizontalFlick`,
  manuelles Snapping auf `contentX` via `NumberAnimation`) innerhalb der
  jetzt sehr dünnen `FirstPage.qml`. Settings bleibt in beiden Sub-Views
  über das jeweils eigene Pull-down-Menü erreichbar. Vom Nutzer nach Test
  auf Emulator UND echtem Gerät bestätigt: "funktioniert gut".
- **v0.3-Release**: Version in `rpm/harbour-hacontrol.spec` hochgezählt,
  `License:` von Platzhalter auf `MIT` korrigiert (dazugehörige
  `LICENSE`-Datei ergänzt), `URL:` auf die echte GitHub-Repo-URL gesetzt
  (vorher `http://example.org/`-Platzhalter). Alle drei RPMs (i486/
  aarch64/armv7hl) neu gebaut und über `gh release create` mit Notes
  veröffentlicht.

## 8. Update 2026-08-29 (Teil 3): WebSocket-Live-Updates (Rest von Stufe 2)

In eigenem Branch (`feature/websocket-live-updates`) entwickelt, nach Test
auf Emulator und echtem Gerät zurück nach `master` gemerged.

- **Vorab-Verifikation statt Rätselraten**: anders als bei `BackgroundJob`
  zuvor wurde die exakte QML-API diesmal *vor* dem Schreiben von Code aus
  dem `plugins.qmltypes` des SDK-Build-Targets ausgelesen (`sfdk tools exec
  ... cat .../QtWebSockets/plugins.qmltypes`). Typ heisst `WebSocket`
  (`import QtWebSockets 1.0`), Properties `url`/`status`/`active`, Signals
  `textMessageReceived`/`statusChanged`, Methode `sendTextMessage()`.
  **Falle dabei**: das Modul war zwar laut `zypper` im Build-Target
  installiert, die eigentliche `.so` fehlte trotzdem -- `zypper install
  --force` hat sie nachgezogen. Pakete: `qt5-qtdeclarative-import-websockets`
  (QML-Plugin) + `qt5-qtwebsockets` (C++-Lib), beide als `Requires:` im
  Spec ergänzt -- auf dem echten Gerät hat `pkcon` das QML-Plugin-Paket
  beim Install korrekt automatisch nachgezogen.
- **Architektur**: REST (`refresh()`) bleibt die Quelle für Struktur
  (Räume, Sortierung, initialer Zustand); der WebSocket liefert danach nur
  noch Deltas (`state_changed`-Events), die per-Zeile in `entriesModel`
  gepatcht werden (`applyStateChange()`), ohne die Liste neu aufzubauen.
  Auth-Handshake (`auth_required` → `auth`-Antwort mit Token →
  `auth_ok` → `subscribe_events`) läuft komplett in
  `qml/views/RoomsView.qml`. Reconnect nach 5s bei `Closed`/`Error` über
  `Qt.binding()`-Wiederherstellung von `active`, statt die Bindung an
  `configured` durch eine reine Wertzuweisung dauerhaft zu brechen.
- **Bekannte Einschränkung**: HAs `subscribe_events(state_changed)` kennt
  keine serverseitige Domain-Filterung -- bei der 1499-Entity-Instanz des
  Nutzers kommen laufend Events für Entities ausserhalb unseres Models
  (z.B. Energie-Sensoren im Sekundentakt), die per linearem Scan verworfen
  werden. Für die hier relevanten Listengrössen unkritisch, aber ein
  möglicher Kandidat für spätere Optimierung (`entityId`→Index-Map), falls
  Akku-/CPU-Last bei sehr grossen Instanzen auffällt.
- **Verifiziert**: vom Nutzer auf Emulator UND echtem Gerät bestätigt --
  externes Schalten eines Lichts (z.B. über die HA-Weboberfläche oder
  physischen Schalter) erscheint sofort in der App, ohne manuelles
  Pull-to-refresh.
