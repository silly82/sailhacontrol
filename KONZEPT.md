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

## 9. Update 2026-08-29 (Teil 4): Erweiterte Lichtsteuerung, v0.4-Release

In eigenem Branch (`feature/light-detail-controls`) entwickelt.

- **Submenu statt Ausbau des Toggles**: Tap auf den Namen einer
  `light`-Entity (nur Lichter, nicht Switches) öffnet
  `qml/pages/LightDetailPage.qml` mit Helligkeit-/Farbtemperatur-Slidern
  und einem Button zum Farbe-Wählen -- der Toggle-Switch bleibt unverändert.
  `ListItem.onClicked` + `menu:` (Kontextmenü) koexistieren ohne
  zusätzliche `MouseArea`, da `ListItem` beides gleichzeitig unterstützt;
  `onClicked` feuert für Taps ausserhalb des Switch-Bereichs (der Switch
  konsumiert seinen eigenen Tap zuerst).
- **Capability-Erkennung** über `attributes.supported_color_modes`
  (Helligkeit: irgendein Modus ausser `onoff`; Farbtemperatur:
  `color_temp`; Farbe: `hs`/`rgb`/`xy`/`rgbw`/`rgbww`) -- nur tatsächlich
  unterstützte Regler werden angezeigt.
- **Kelvin statt Mired verifiziert**: vor dem Schreiben von Code echte
  Light-Entity-Attribute der HA-Instanz abgefragt (`curl .../api/states`).
  Diese HA-Version nutzt durchgehend `min_color_temp_kelvin`/
  `max_color_temp_kelvin`/`color_temp_kelvin` (kein `mireds` mehr) --
  `light.turn_on` entsprechend mit `color_temp_kelvin` statt `color_temp`
  aufgerufen.
- **Farbauswahl über stock Silica-Komponente** `ColorPickerPage`
  (`import Sailfish.Silica 1.0`, kein eigener Farbwähler gebaut) -- API
  vorher via `sfdk tools exec ... cat ColorPickerPage.qml` verifiziert
  (`signal colorClicked(color color)`, gepusht als inline `Component`).
- **Bug gefunden+gefixt** (Nutzer-Feedback: "state scheint erst nach
  licht ein zu stimmen"): HA meldet `brightness`/`color_temp_kelvin`/
  `rgb_color` als `null`, solange die Entity `state: off` ist -- keine
  Einschränkung unserer App, sondern HAs Datenmodell (viele Integrationen
  "vergessen" den letzten Wert visuell, auch wenn intern noch vorhanden).
  Fix: Hinweistext auf der Detail-Seite, sichtbar nur wenn `!entityIsOn`,
  erklärt dass der Regler dann einen Startwert statt eines gespeicherten
  Zustands zeigt, und dass Verstellen das Licht mit einschaltet.
- **v0.4-Release**: Version hochgezählt, Branch nach `master` gemerged,
  alle drei RPMs neu gebaut und veröffentlicht.

## 10. Update 2026-08-31: Lockscreen-Widget geprüft -- nicht möglich, Notification-Action stattdessen

**Rechercheergebnis vor dem Bauen**: ein echtes Lockscreen-Widget wie unter
Android existiert für Sailjail-sandboxte Drittanbieter-Apps nicht. Der
gesamte Lockscreen-QML-Code (`LockScreen.qml`,
`LockscreenBackground.qml`, ...) liegt unter `lipstick-jolla-home-qt5`,
also im System selbst -- keine `Loader`/Plugin-Erweiterungsstelle für
Drittanbieter-Inhalte gefunden (`grep` nach `loader|plugin|thirdparty` in
`LockScreen.qml` ergab nichts). Damit war die ursprüngliche
Konzept-Formulierung "Lockscreen-Widget" nicht wörtlich umsetzbar --
mit dem Nutzer abgestimmt: stattdessen **Notification mit
Action-Button**, der direkt vom Sperrbildschirm aus (aufgeklappte
Benachrichtigung) eine beobachtete Entity umschaltet, ohne die App zu
öffnen.

- **Technischer Weg**: `Nemo.Notifications`' `Notification.remoteActions`
  (Property, Array von `remoteAction(name, displayName, service, path,
  iface, method, arguments)`-Deskriptoren) plus `Nemo.DBus`'
  `DBusAdaptor` -- Letzteres erlaubt, einen D-Bus-Dienst **komplett aus
  QML heraus** anzubieten (keine C++-Erweiterung nötig). Muster
  (Funktionsnamen im `DBusAdaptor`-Block werden automatisch zu
  D-Bus-Methoden) verifiziert anhand von `jolla-settings/settings.qml`
  im SDK-Target, nicht geraten.
- **Umsetzung** in `qml/harbour-hacontrol.qml`: `DBusAdaptor` mit
  `service/path/iface = org.example.hacontrol` (ergibt sich aus dem
  bereits von Sailjail vergebenen eigenen Bus-Namen, s.
  `[X-Sailjail]` in der `.desktop`-Datei) und einer `toggleEntity(entityId)`-
  Funktion, die den bestehenden `HaApi.callService(...toggle...)`-Call
  aufruft. `notifyStateChange()` hängt jetzt `remoteActions` mit einer
  "Umschalten"-Aktion an jede Benachrichtigung.
- **Gleiche Einschränkung wie der Background-Poll selbst**: funktioniert
  nur, während der App-Prozess resident ist (kein D-Bus-Activation-
  `.service`-File vorhanden) -- keine neue Einschränkung, sondern
  dieselbe wie bei Ausbaustufe 3/Variante B insgesamt.
- **Verifiziert in zwei Schritten**: (1) `toggleEntity` manuell per
  `dbus-send` gegen eine echte Entity (`light.wohnen`) aufgerufen --
  Licht ging real an, per REST-API-Abfrage bestätigt, danach zurück
  ausgeschaltet. (2) Kompletter Weg End-to-End über einen echten
  Background-Poll-Zyklus: `watchedEntities`/`lastKnownStates` in dconf
  vorbereitet, Nutzer hat die Entity extern umgeschaltet, nach dem
  nächsten Poll zeigte `lastKnownStates` den neuen Wert und
  `NotificationActionRow.qml` (die Lipstick-Komponente fürs Rendern von
  Action-Buttons auf Benachrichtigungen) tauchte exakt zum Poll-Zeitpunkt
  im Journal auf -- Nachweis, dass die Benachrichtigung mit sichtbarem
  Button tatsächlich publiziert wurde.
- **Neues `Requires:`**: `nemo-qml-plugin-dbus-qt5` im Spec ergänzt.

## 11. Update 2026-08-31 (Teil 2): Verbleibender Konzept-Punkt zurückgestellt

Damit sind alle Konzept-Punkte aus Ausbaustufe 1-3 umgesetzt bis auf einen:

- **Remote-Zugriff** (Zugriff ausserhalb des lokalen Netzes, z. B. via
  Nabu Casa oder eigener Reverse-Proxy, s. Abschnitt 1/2). **Als
  Future-TODO ohne Priorität zurückgestellt** -- explizit auf Wunsch des
  Nutzers nicht jetzt angegangen. Kein technischer Blocker bekannt, nur
  bewusst nicht priorisiert.

## 12. Update 2026-08-31 (Teil 3): Echtes App-Icon statt Platzhalter, v0.6

Bisher nur ein ImageMagick-Platzhalter (blaues Quadrat + "HA"-Schriftzug,
s. Abschnitt 5). Nutzer hat die offiziellen Sailfish-Icon-Design-Ressourcen
verlinkt (`Sailfish-Apps-icon-template.zip`,
sailfishos.org/design/icons/, "App icon story"-PDF) mit dem Hinweis, dass
die Icon-Silhouette bewusst **keine einfache Rounded-Rect/Squircle** ist,
sondern eine Familie organischer Formen, definiert im offiziellen Template
-- nicht selbst schätzen.

- **Exakten Pfad aus dem Template übernommen**: `icon-launcher-template.svg`
  (86x86-Space) heruntergeladen und den Silhouette-Pfad 1:1 extrahiert --
  zwei gegenüberliegende Ecken mit grossem organischem Viertelkreis-Radius
  (~42.7px), die anderen beiden mit normalem kleinem Rundungsradius
  (~1.4px).
- **Rendering-Stolperstein**: ImageMagicks eingebauter SVG-Parser (MSVG)
  unterstützt `<linearGradient>` nicht zuverlässig -- Hintergrund kam
  einfarbig schwarz statt als Verlauf heraus. `rsvg-convert` (CLI) war
  nicht installiert, nur die Library. Kein `pip`/`cairosvg` verfügbar.
  Lösung: `python3-cairo` (pycairo) war als System-Paket bereits
  vorhanden -- Pfad, Gradient und Motiv direkt per pycairo-API gezeichnet
  statt über einen SVG-Parser, umgeht das Problem komplett.
- **Design**: Navy-zu-HA-Blau-Diagonalverlauf (`#1B3A57` → `#41BDF5`),
  weisses Haus-Silhouetten-Motiv, zentriert. Bei 86px (kleinste
  Launcher-Grösse) noch klar lesbar getestet.
- **Reproduzierbar**: Generator-Skript unter `icons/source/generate-icon.py`
  committed (`python3 icons/source/generate-icon.py` regeneriert alle vier
  Grössen direkt in `icons/<size>x<size>/`), statt nur die fertigen PNGs
  ohne Herkunft abzulegen.
- Vorschlag dem Nutzer per Artifact-losem Bildvergleich (Read-Tool-Vorschau)
  gezeigt und direkt bestätigt bekommen, dann übernommen.
- **Nachtrag**: Datei auf der Platte/im Paket war sofort korrekt (auch via
  `raw.githubusercontent.com` verifiziert), trotzdem zeigte der
  Launcher auf beiden Geräten weiter das alte "HA"-Quadrat -- Ursache war
  ein In-Memory-Pixmap-Cache im lange laufenden `lipstick`-Prozess (auf
  dem Emulator seit dem allerersten Install vor Tagen aktiv), der beim
  Überschreiben derselben Datei nie invalidiert wurde. Fix:
  `systemctl --user restart lipstick` auf beiden Geräten (auf dem
  Emulator ohne `devel-su`, auf dem Handy ebenfalls ohne -- User-Session-
  systemd braucht dafür keine Root-Rechte).

## 13. Update 2026-08-31 (Teil 4): Vorbereitung für Jolla-Store/Harbour-Einreichung

Nutzer hat auf die offiziellen Harbour-Richtlinien verwiesen. Recherchiert
via `docs.sailfishos.org/Develop/Apps/Harbour/` (Allowed APIs, Allowed
Permissions) -- und, entscheidend, den **offiziellen Validator lokal
laufen lassen** statt nur die Doku zu lesen:
```
sfdk check -s harbour <rpm-datei>
sfdk check -s rpmlint <rpm-datei>
```
Das deckte konkrete, vorher unbekannte Probleme auf:

- **Blockierender Fehler**: `Nemo.KeepAlive 1.1` ist laut Harbours
  Allowed-APIs-Liste **nicht erlaubt** -- nur `Nemo.KeepAlive 1.2`. Import
  in `harbour-hacontrol.qml` entsprechend gehoben.
- **Deprecation-Warnungen bereinigt**: `org.nemomobile.configuration` →
  `Nemo.Configuration` (5 Dateien), `org.nemomobile.notifications` →
  `Nemo.Notifications` -- das waren bisher nur kosmetische Log-Zeilen,
  jetzt als echte Harbour-Warnungen bestätigt und behoben. Nach dem Fix
  auf dem Emulator verifiziert: keine Deprecation-Zeilen mehr im Journal.
- **rpmlint-Fehler behoben**: `no-changelogname-tag` (fehlender
  `%changelog`-Abschnitt -- ergänzt) und `explicit-lib-dependency
  libkeepalive` (rpmlint will soname-Form `Requires: libkeepalive.so.1`
  statt Paketname). **Soname-Form wieder zurückgedreht**: bestand lokale
  Checks genauso gut, brach aber die echte Installation auf dem Handy
  ("nothing provides libkeepalive.so.1" -- zypper dort wollte die
  `()(64bit)`-qualifizierte Form). Paketname-`Requires: libkeepalive`
  bleibt, rpmlint-Warnung bewusst in Kauf genommen (ohnehin nur
  `TreatErrorsAsWarnings`, kein harter Blocker).
- **`%license`-Versuch verworfen**: `%license LICENSE` (Fedora-Konvention,
  installiert nach `/usr/share/licenses/...`) wurde vom Harbour-Validator
  mit "Installation not allowed in this location" abgelehnt -- Harbours
  Pfad-Whitelist ist enger als allgemeine Fedora-Regeln. `License:`-Tag im
  Spec-Header reicht, keine separate Datei installiert.
- **Unstripped-Binary-Warning behoben**: `sfdk build` (Dev-Workflow) setzt
  beim qmake-Aufruf `QMAKE_STRIP=:` (No-op) für schnellere Iteration --
  explizites `%{__strip}` im `%install`-Abschnitt ergänzt statt sich auf
  automatisches Stripping zu verlassen.
- **Ergebnis**: `sfdk check -s harbour` UND `-s rpmlint` laufen für alle
  drei Architekturen (i486/aarch64/armv7hl) sauber durch (0 Fehler,
  0 Warnungen bei rpmlint bis auf die bewusst akzeptierte
  `explicit-lib-dependency`). Auf Emulator und echtem Gerät installiert
  und gestartet, keine neuen Laufzeitfehler.
- **Noch offen für eine tatsächliche Einreichung** (nicht Teil dieser
  Vorbereitung): Jolla-Account + Harbour-Zugang einrichten, und die
  Store-typische Frage klären (z. B. ob eine App, die primär eine
  private/lokale HA-Instanz steuert, für den Store überhaupt sinnvoll
  ist, oder ob GitHub-Releases das bessere Vertriebsmodell bleiben --
  diese Entscheidung liegt beim Nutzer).

## 14. Update 2026-08-31 (Teil 5): Store-Listing-Assets vorbereitet

Neuer Ordner `store/` (kein Code, nicht Teil des RPM-Pakets): drei
Screenshots vom SDK-Emulator (Raumliste, Sensor-Übersicht,
Licht-Detail-Regler -- letztere zwei erforderten manuelle Navigation
durch den Nutzer, da kein Touch-Input simuliert werden kann),
Beschreibungstext für die Store-Auflistung auf Englisch und Deutsch.

- **Datenschutz-Rückfrage vorab**: die Screenshots zeigen die echten
  Raum-/Gerätenamen der HA-Instanz des Nutzers (u. a. ein Personenname
  als Zimmerbezeichnung). Vor dem Committen explizit nachgefragt statt
  einfach zu veröffentlichen -- vom Nutzer bestätigt: "so wie es ist,
  passt schon".
- Harbours FAQ dokumentiert keine festen Screenshot-Masse/-Formate oder
  eine Kategorie-Liste (anders als die RPM/API-Regeln gibt es dafür
  keinen automatisierten Validator) -- `store/README.md` hält das
  explizit als unverifiziert fest, statt Zahlen zu erfinden.

## 15. Update 2026-09-03: Store-Assets gegen das echte Formular verfeinert

Nutzer hat das tatsächliche Harbour-Einreichungsformular gepostet
(Title/Details/Categorization/Binaries/Compatibility/Visual
assets/Contact details/Publish settings). Damit ließ sich raten durch
Wissen ersetzen:

- **Summary-Feld entdeckt**: eigenes Feld, getrennt von Description,
  200-Zeichen-Limit -- vorher übersehen, `summary-en/de.txt` ergänzt.
- **Screenshots neu**: echtes Gerät statt Emulator (1032x2272 nativ),
  auf 1080x2378 hochskaliert, weil das Formular "at least 1080px wide"
  verlangt und die native Handybreite knapp darunter liegt.
- **Description bereinigt**: Titel-Zeile ("HA Control") und
  GitHub-Link am Ende entfernt, da beides schon eigene Formularfelder
  hat (Title, Open source project URL) -- keine Doppelung.
- **Kategorie bleibt offen**: Dropdown-Optionen nie gesehen, Nutzer
  trägt selbst ein.
- Account existiert bereits, **Einreichung macht der Nutzer manuell
  selbst** im Web-UI -- das ist kein Automatisierungs-Kandidat.

## 16. Update 2026-09-07: Thermostat-Steuerung (climate-Domain)

Analog zur Lichtsteuerung: Tap auf den Namen einer `climate`-Entity
öffnet `qml/pages/ThermostatDetailPage.qml` mit Zieltemperatur-Regler
(`min_temp`/`max_temp`/`target_temp_step` aus den Attributen) und
Modus-Auswahl (`ComboBox` + `ContextMenu`+`Repeater` über
`hvac_modes`). Vor dem Schreiben echte Climate-Attribute der
HA-Instanz per curl geprüft (6 Thermostate, `hvac_modes` reicht von
`["off","heat"]` bis `["auto","heat","off"]`, `target_temp_step` nicht
immer vorhanden -- Fallback 0.5).

**Zwei echte Bugs beim Testen gefunden+gefixt** (Nutzer-Feedback
"Mode fehlt noch Off Heat", dann per Screenshot verifiziert):

1. QML-`ListModel`-Rollen sind **typgebunden** (der erste Wert legt
   den Typ fest) -- die `value`-Rolle war durch Toggle-/Sensor-Zeilen
   bereits als String festgelegt; die Zieltemperatur einer
   Climate-Zeile kam aber als Number rein (`s.attributes.temperature`)
   und produzierte `Can't assign to existing role 'value' of
   different type [Number -> String]`-Warnungen im Journal, mit
   falscher/fehlender Anzeige als Symptom. Fix: Zieltemperatur immer
   via `String(...)` in die Zeile schreiben.
2. **Modus-Anzeige blieb leer**, obwohl "Modus" als Label sichtbar
   war: `ThermostatDetailPage.qml` las `attributes.state`, aber HAs
   `state` (bei climate == aktueller hvac_mode) liegt als
   **Geschwisterfeld neben** `attributes`, nicht darin -- war also
   immer `undefined`. Fix: eigenes `hvacMode`-Feld in `RoomsView.qml`s
   Zeilen-Objekten, separat von `attributes` durchgereicht als
   `entityHvacMode`-Property.
- Verifiziert auf Emulator (Screenshot: "Modus Aus" korrekt) und
  echtem Gerät (Nutzer: "geht, temperatur setzen funktioniert").
  `sfdk check -s harbour`/`-s rpmlint` weiterhin sauber bis auf die
  bereits akzeptierte `libkeepalive`-Warnung.

## 17. Update 2026-09-07 (Teil 2): Domain-Abdeckung erweitert (media_player/cover/fan/scene, weitere Sensor-Klassen), v0.9

Ausgangspunkt: Analyse aller 1517 Entities der echten HA-Instanz nach
Domain/`device_class` zeigte deutliche Lücken (siehe Gap-Analyse-Antwort
im Chat). Auf Nachfrage "wichtigste 5 pro Kategorie ergänzen" wollte der
Nutzer stattdessen **volle Abdeckung ohne künstliches Limit** ("Alle
Entities zeigen, nicht limitieren") -- eine automatische "wichtigste 5"
Auswahl (z.B. bei Batterie-Sensoren) ist ohne manuelle Kuratierung nicht
sinnvoll definierbar.

**Neu abgedeckt** (`qml/views/RoomsView.qml`):
- `fan`/`cover` in die bestehenden `toggle`-Zeilen aufgenommen (nutzen
  wie `light`/`switch` den generischen `<domain>.toggle`-Service). Einzige
  Besonderheit: `cover`s "an"-Äquivalent ist `state === "open"`, nicht
  `"on"` -- zentral in einer neuen `isEntityOn(domain, state)`-Helper-
  funktion behandelt statt an jeder Stelle einzeln zu unterscheiden.
- `media_player` als eigener `kind` mit Submenu (Tap auf Namen, analog
  Licht/Thermostat) -- neue `qml/pages/MediaPlayerDetailPage.qml` mit
  Play/Pause/Vor/Zurück (`media_play_pause`/`_next_track`/
  `_previous_track`) und Lautstärke-Regler (`volume_set`), nur sichtbar
  wenn die Entity `volume_level` überhaupt liefert (viele Chromecasts/
  Sonos-Entities tun das nicht durchgehend). Titel/Interpret nur
  angezeigt falls `media_title`/`media_artist` vorhanden (bei keiner der
  23 realen media_player-Entities zum Testzeitpunkt aktiv befüllt, da
  nichts lief -- defensiv codiert statt angenommen).
- `scene` als eigener `kind` **ohne Switch**: Scenes haben laut echten
  API-Daten (13 Entities geprüft) keinen sinnvollen on/off-Zustand (State
  ist der Zeitpunkt der letzten Aktivierung, z.B.
  `"2026-08-20T16:48:58...+00:00"`, oder `"unknown"`) und keinen
  `toggle`-Service -- nur `scene.turn_on`. UI dafür: Tap auf die ganze
  Zeile aktiviert sofort (`activateScene()`), rechts nur ein
  "Aktivieren"-Hinweislabel statt eines Switches. Der Notify-Kontextmenü
  (`menu:`) bewusst nicht für `scene` angeboten -- "bei Änderung
  benachrichtigen" ergibt für einen Zeitstempel-State keinen Sinn.
- Sensor-`device_class`-Liste um `battery`/`energy`/`power` erweitert
  (waren mit 37/59/44 Entities die größten unabgedeckten Sensor-
  Kategorien in der Analyse). `qml/views/SensorsView.qml` um die
  entsprechenden Abschnitte ("Batterie"/"Energie"/"Leistung") ergänzt --
  gleiches generisches Section-Muster wie Temperatur/Feuchte/Luftdruck,
  keine Sonderbehandlung nötig.

**Getestet**: i486-Build auf dem Emulator installiert; da für UI-Checks
auf dem Emulator kein Touchscreen zur Verfügung steht, wurde die
VirtualBox-Fensterausgabe per `import` gegriffen und Taps/Swipes über
`xdotool` gegen das Fenster simuliert (einzelner schneller
Mousedown→Mousemove→Mouseup-Sprung wird als Flick erkannt, mehrstufige
langsame Bewegung dagegen als Long-Press -- wichtig für zukünftige
Emulator-UI-Checks). Damit visuell bestätigt: Room-Zählungen stiegen
sichtbar (z.B. Bastelzimmer 30→57) durch die neu erfassten Entities,
mehrere Szenen-Zeilen im Wohnzimmer zeigen korrekt Name + "Aktivieren",
Scroll/Expand/Collapse unverändert funktionsfähig. Kein einziges
QML-`ListModel`-Rollentyp-Warning im Journal über den vollen Lauf mit
allen 1517 Entities (die aus der Climate-Arbeit bekannte
Type-Locking-Falle wurde durchgehend vermieden, u.a. durch `String(...)`
für alle `value`-Zuweisungen). Auf dem echten Gerät (aarch64) installiert
und Prozessstart ohne Fehler im Log bestätigt; volle visuelle
Bestätigung dort nicht möglich (kein Display-Zugriff über die
SSH-only-Verbindung) und daher noch ausständig, sobald der Nutzer selbst
schaut.
`sfdk check -s harbour`/`-s rpmlint` auf allen drei Architekturen weiterhin
sauber bis auf die bereits akzeptierte `libkeepalive`-Warnung.

## 18. Update 2026-09-08: update-Domain (zu aktualisierende Geräte), v0.10

Aus der ursprünglichen Gap-Analyse noch offen: `update`-Domain (107
Entities in der echten Instanz, aber zum Prüfzeitpunkt nur 3 mit
`state === "on"`, d.h. Update verfügbar -- die meisten Entities sind die
meiste Zeit "off"/aktuell). Auf Nachfrage "was braucht [es] für die
Anzeige von zu updatenden Geräten" kurz die relevanten Attribute genannt
(`installed_version`/`latest_version`/`title`, `supported_features`-Bit 0
== `UpdateEntityFeature.INSTALL`) und empfohlen, das **nicht** pro Raum
in `RoomsView.qml` einzuhängen, sondern als eigene, raumübergreifende
dritte Sub-View analog `SensorsView.qml` -- Updates sind naturgemäss
nicht raumgebunden interessant, und ungefiltert wären es 107 grössten-
teils irrelevante Zeilen für typischerweise eine Handvoll echte Treffer.
Nutzer hat zugestimmt ("ja, umsetzen").

**Neu**: `qml/views/UpdatesView.qml` -- flache (keine Sections, anders
als bei den Sensoren) Liste, gefiltert auf `state === "on"`. Pro Zeile:
Name (`title` bevorzugt vor `friendly_name`, HA befüllt `title` bei
`update`-Entities meist mit dem eigentlichen Produktnamen statt der
technischen Entity-Bezeichnung) + zweite Zeile mit
`installed_version → latest_version`, rechts ein "Installieren"-Label
(gleiches Tap-zum-Aktivieren-Muster wie bei `scene` in v0.9 -- kein
Submenu nötig für einen einzelnen Install-Trigger). Ruft
`update.install` auf; danach (wie bei `toggle()`/`activateScene()`)
kurzer Timer + Refresh, da der Service-Call nur die Annahme bestätigt,
nicht den Abschluss. Zeilen mit `in_progress === true` zeigen
"Installiert…" statt "Installieren" und sind nicht mehr antippbar;
Entities ohne das `INSTALL`-Feature-Bit ebenfalls nicht antippbar
(seltener Fall, aber `supported_features` variiert real zwischen 5/15/27
je nach Integration).

`FirstPage.qml`s Swipe-Snap-Logik war bisher hart auf zwei Seiten
(0/`page.width`) codiert -- verallgemeinert auf
`Math.round(contentX / page.width) * page.width`, geclampt auf
`[0, viewRow.width - page.width]`, damit sie mit einer dritten Sub-View
(und potenziell weiteren) weiterhin sauber einrastet statt zwischen
Seiten hängen zu bleiben.

**Getestet**: auf dem Emulator (i486) installiert, `xdotool`-Swipe (s.
[[sailfishos-sdk-workflow]] für die Geste) zur dritten Seite bestätigt
korrektes Rendering mit den drei echten anstehenden Updates der
Instanz (u. a. zwei ESPHome-Taster-Firmware-Updates). Kein
QML-Rollentyp- oder Referenzfehler im Journal. Auf dem echten Gerät
(aarch64) installiert und fehlerfrei gestartet; volle visuelle
Bestätigung dort weiterhin nicht möglich (SSH-only-Verbindung, wie
schon bei v0.9 vermerkt). `sfdk check -s harbour`/`-s rpmlint` auf allen
drei Architekturen sauber bis auf die bereits akzeptierte
`libkeepalive`-Warnung.
