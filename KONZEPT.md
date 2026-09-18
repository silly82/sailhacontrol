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
(aarch64) installiert, gestartet und vom Nutzer visuell bestätigt
("sieht gut aus auf handy"). `sfdk check -s harbour`/`-s rpmlint` auf
allen drei Architekturen sauber bis auf die bereits akzeptierte
`libkeepalive`-Warnung.

## 19. Update 2026-09-08 (Teil 2): UI-Politur -- Farb-Swatch bei Lichtern, Fortschrittsbalken bei Updates, v0.11

Auf Nachfrage "Vorschlag für etwas fancy shiny UI, immer noch minimal"
mehrere Optionen genannt (Domain-Icons, Live-Flash bei WS-Updates,
Farb-Swatch bei Lichtern, Fortschrittsbalken bei Updates,
CoverPage-Quick-Action); Nutzer wählte die beiden datengetriebenen
Optionen -- beide brauchen keinen neuen API-Call, nur Attribute, die
schon abgefragt werden.

**Farb-Swatch bei Lichtern** (`qml/views/RoomsView.qml`): kleiner
farbiger Kreis zwischen Name und Switch bei `light`-Entities mit
bekannter Farbe. Bevorzugt echtes `rgb_color`; falls nicht vorhanden,
Näherung aus `color_temp_kelvin` per Tanner-Helland-Approximation
(`kelvinToRgb()` -- kein exaktes Farbmodell, aber für einen kleinen
Vorschau-Kreis ausreichend). `null` (Swatch unsichtbar) wenn das Licht
aus ist oder keins von beidem liefert -- HA meldet beide Attribute als
`null` solange aus (bekannte Einschränkung, s. README). `attributes`
wurde bisher nur für climate/media_player-Zeilen per WebSocket
live nachgezogen (`applyStateChange()`) -- jetzt auch für
`light`-Toggle-Zeilen, damit der Swatch bei externen Änderungen sofort
nachzieht statt erst beim nächsten Pull-to-refresh.

**Fortschrittsbalken bei laufenden Updates** (`qml/views/UpdatesView.qml`):
ersetzt die Versions-Zeile ("X → Y") durch einen schmalen, abgerundeten
Balken in `Theme.highlightColor`, solange `in_progress === true`. Manche
Integrationen liefern `update_percentage` (Balken füllt sich passend,
Prozentzahl daneben), andere nicht -- dort läuft stattdessen ein
wanderndes Highlight (`SequentialAnimation on x`, hin und her) als
unbestimmter Fortschritt. `updatePercentage` wird als `-1` statt
`null`/`undefined` gespeichert, wenn unbekannt -- sonst dieselbe
ListModel-Rollentyp-Falle wie beim `value`-Feld in RoomsView.qml
(Number/null-Mix auf derselben Rolle). Ein neuer `Timer`
(`progressPollTimer`, 3s, läuft nur solange `anyInProgress`) pollt
während einer laufenden Installation automatisch nach, damit der
Balken tatsächlich mitwächst statt nur einmal beim initialen
Tap-Refresh stehen zu bleiben.

**Debugging-Hinweis**: die erste Version des Balkens sass sichtbar zu
eng an der Namenszeile (wirkte wie eine Unterstreichung statt einer
zweiten Zeile) -- Ursache war schlicht eine zu knapp bemessene Höhe
für das Balken-`Item` (`Theme.paddingMedium`, dann versuchsweise
`Theme.fontSizeExtraSmall + Theme.paddingSmall`, beides noch zu
knapp). Fix: Item-Höhe auf `Theme.paddingLarge`, Balkendicke von
`Theme.paddingSmall/2` auf volles `Theme.paddingSmall` erhöht (klar
sichtbarer "Pill"-Balken statt Haarlinie), UND `contentHeight` der
`ListItem`-Delegate selbst für `in_progress`-Zeilen um
`Theme.paddingSmall` vergrössert, damit die zusätzliche Höhe nicht mit
der nächsten Zeile kollidiert. Erst nach dieser dritten Iteration sah
es im Screenshot tatsächlich wie ein sauberer Balken aus statt wie ein
Rendering-Fehler.

Für die visuelle Prüfung auf dem Emulator wurden testweise zwei
Fake-Zeilen (`in_progress: true`, eine mit/eine ohne Prozentwert) am
Anfang von `buildEntries()` eingefügt (`matches.unshift(...)`), um
den Balken ohne ein echtes `update.install` gegen die reale
HA-Instanz auszulösen zu können -- ein echter Install-Trigger hätte
tatsächlich Geräte-Firmware auf der Hardware des Nutzers angestossen,
das wollte ich nicht ungefragt riskieren. Die Fake-Zeilen wurden vor
dem Commit wieder entfernt.

**Getestet**: Emulator (Farb-Swatch mit "Küche Tisch Lampe", reale
`rgb_color: [255, 167, 88]`, korrekt als warmer Orange-Punkt
gerendert; Fortschrittsbalken mit den Fake-Test-Zeilen verifiziert,
s. o.), echtes Gerät (aarch64, installiert+startet fehlerfrei, keine
QML-Fehler im Log). `sfdk check -s harbour`/`-s rpmlint` auf allen
drei Architekturen sauber bis auf die bereits akzeptierte
`libkeepalive`-Warnung.

## 20. Update 2026-09-18: Echte mobile_app-Integration (Push + Device-Status), v0.12

Nutzer-Wunsch: "Benachrichtigungsfunktion und Device-Status-Funktion der
Original-App nachbauen" -- gemeint war explizit nicht der bestehende
Poll-basierte Ansatz (Ausbaustufe 3/Variante B), sondern die echten
`mobile_app`-Mechanismen der offiziellen HA-Companion-App: (a) HA kann
aktiv Push-Nachrichten ans Handy schicken (`notify.mobile_app_...`,
z.B. aus Automationen), (b) das Handy meldet umgekehrt eigene Sensoren
(Akkustand, Verbindungsart) an HA zurück. Per Rückfrage (AskUserQuestion)
bestätigt, bevor mit der Umsetzung begonnen wurde.

**API-Mechanik vorab aus dem echten `home-assistant/core`-Quellcode
gelesen** (nicht geraten) -- `mobile_app/const.py`, `notify.py`,
`push_notification.py`, `websocket_api.py`, `webhook.py`, `http_api.py`:
Registrierung per `POST /api/mobile_app/registrations` (Bearer-Token wie
die bestehenden REST-Calls); `app_data.push_websocket_channel: true`
reicht laut `supports_push()` in `util.py` bereits aus, damit HA einen
echten `notify.mobile_app_<gerät>`-Service anbietet, der über die
**bereits bestehende, authentifizierte WebSocket-Verbindung** (aus
Abschnitt 8) zugestellt wird -- kein eigener HTTP-Server, kein
C++-Bridge-Objekt nötig. Client sendet dafür einmalig
`{"type": "mobile_app/push_notification_channel", "webhook_id": ..., "support_confirm": false}`,
HA liefert Pushes danach als reguläre `event`-Nachrichten auf derselben
Verbindung. Sensor-Updates laufen separat über
`POST /api/webhook/<webhook_id>` (kein Bearer-Header nötig, die
Webhook-ID selbst ist das Secret) mit `register_sensor`/
`update_sensor_states`.

**Device-Status-Sensoren ohne UPower**: SailfishOS nutzt für
Akkustand/Ladezustand `com.nokia.mce` (`get_battery_level`/
`get_charger_state`) statt UPower, und `net.connman`
(`Manager.GetServices()`, erster Eintrag = aktive Verbindung) für die
Verbindungsart -- beides direkt gegen den laufenden SDK-Emulator per
`dbus-send --system` verifiziert (`org.freedesktop.UPower` ist auf
SailfishOS schlicht nicht vorhanden), bevor `qml/components/DeviceStatusProbe.qml`
geschrieben wurde. Die exakte `Nemo.DBus`-QML-API (`getProperty`/`call`/
`typedCall`, keine `plugins.qmltypes` für dieses Plugin vorhanden) wurde
per `strings` auf der Plugin-`.so` im SDK-Target verifiziert statt aus
Erinnerung übernommen.

**Zwei echte Bugs beim End-to-End-Test gegen die reale, 1500+-Entity-
Instanz des Nutzers gefunden+gefixt** (nicht im Emulator allein
aufgefallen -- Debugging lief per curl direkt gegen die echte HA-Instanz,
da dieser Rechner sie im lokalen Netz erreicht):

1. **`os_version` ist trotz "optional" in HAs eigenem Schema faktisch
   erforderlich.** Ohne dieses Feld crasht `mobile_app`s eigenes
   `async_setup_entry()` (direkter Dict-Zugriff ohne Fallback) NACH
   Erzeugung der `webhook_id`, aber VOR ihrer Registrierung beim
   generischen Webhook-Dispatcher. Symptom war tückisch: die
   REST-Registrierung meldet trotzdem Erfolg (HTTP 201 + scheinbar
   gültige `webhook_id`), aber jeder folgende Aufruf gegen diese ID
   (`register_sensor`, Push, sogar `get_config`) bekommt für immer
   HAs Leer-200-Antwort für unbekannte Webhooks -- das generische
   Anti-Enumeration-Verhalten des Webhook-Dispatchers. Erst per
   `curl` mit/ohne `os_version` gegenübergestellt gefunden. Fix: immer
   einen statischen `os_version`-Wert mitschicken (kein natives
   Auslesen der echten SailfishOS-Version -- bräuchte C++, HA zeigt
   den Wert ohnehin nur an).
2. **Push-Kanal-Abo hatte eine Race Condition**: wurde nur im
   `auth_ok`-Handler des WebSockets gesendet, aber die Registrierung
   (asynchroner REST-Call in `harbour-hacontrol.qml`) war zu dem
   Zeitpunkt bei einem Neustart oft noch nicht fertig -- damit blieb
   der Push für den Rest dieser Verbindung unabonniert. Fix: eigene
   `subscribePushChannelIfReady()`-Funktion, zusätzlich an
   `webhookIdSetting`s `onValueChanged` gehängt.

**Verifiziert Ende-zu-Ende gegen die echte Instanz** (Emulator, i486):
Registrierung erzeugt ein neues, sauberes `mobile_app`-Gerät "SailfishOS
Phone" in HA (per WebSocket-Admin-Query bestätigt: genau ein
`state: "loaded"`-Eintrag, keine Karteileichen trotz mehrerer
Test-Registrierungsläufe -- HAs Config-Entry-Dedup nach
`unique_id = app_id-device_id` greift wie erwartet). `notify.send_message`
(Ziel-Entity `notify.sailfishos_phone`) aus HAs Dev-Tools ausgelöst -->
Push-Banner erscheint sofort auf dem Emulator, per Screenshot bestätigt.
Alle drei Device-Status-Sensoren (`sensor.sailfishos_phone_akkustand`,
`binary_sensor.sailfishos_phone_ladt`, `sensor.sailfishos_phone_verbindungsart`)
erscheinen mit für den Emulator plausiblen Werten (kein echter Akku -->
`-1`, korrekt herausgefiltert statt als Sensorwert gesendet; `ladt: on`
und `verbindungsart: ethernet` passend zum Emulator-Setup). Kein
einziger QML-Fehler im Journal über die gesamte Testsession.

**Nachtrag, selbe Session -- echtes Gerät angeschlossen**: aarch64-RPM
auf die reale Jolla Phone installiert (`192.168.2.15`, s.
sailtalerwallet-Workflow für devel-su/pkcon). Zwei Cross-Arch-Stolperfallen
dabei erneut bestätigt (bereits aus sailtalerwallet bekannt, hier zum
ersten Mal live erlebt): (1) `sfdk build` für i486 dann aarch64
nacheinander im selben Arbeitsverzeichnis (kein Shadow-Build) relinkt
stillschweigend die stehen gebliebene i486-`.o`/Binary in die
aarch64-RPM -- sichtbar am `warning: Binaries arch (1) not matching the
package arch (2)` beim Build, geführt zu `nothing provides
libQt5Core.so.5` beim Installationsversuch auf dem echten Gerät (obwohl
dieselbe Lib dort für die schon laufende v0.10 längst vorhanden ist).
Fix: `rm -f harbour-hacontrol harbour-hacontrol.o Makefile moc_*` vor
jedem Architekturwechsel. (2) `pkcon install-local` über `ssh -tt`
produzierte wie dokumentiert Runaway-Output -- Fix war, wie schon
bekannt, kein PTY zu erzwingen.

Ausserdem eine dritte, kleinere Falle beim Aufräumen alter
App-Instanzen: `devel-su killall harbour-hacontrol firejail invoker`
sollte nur die eigene App treffen, hat aber (Prozessname-Kollision)
gleich noch die gerade laufende Kamera-, E-Mail- und Browser-App des
Nutzers mitbeendet, da die ebenfalls unter `firejail`/`invoker` laufen.
Kein Datenverlust, aber ein Warnzeichen: `killall` nie mit einem so
generischen Namen wie `firejail`/`invoker` auf einem Gerät mit anderen
laufenden Fremd-Apps.

**Auf echter Hardware verifiziert**: Registrierung erzeugte automatisch
ein zweites, sauberes `mobile_app`-Gerät (andere `deviceId` als der
Emulator, daher `_2`-Entity-Suffix in HA) mit realen Werten -- Akkustand
tatsächlich `55`/`56` (kein `-1` wie im Emulator, echte
`get_battery_level()` funktioniert), `ladt: on` (Handy hing zum
Testzeitpunkt am USB-Kabel, korrekt erkannt), `verbindungsart` kurz
`offline` direkt beim allerersten App-Start (`GetServices()` lief
offenbar, bevor ConnMan seine Service-Liste nach dem Verbindungsaufbau
neu sortiert hatte), danach beim nächsten Update korrekt `wifi` --
selbstheilend über den nächsten 10-Minuten-Poll, kein Code-Bug (per
Debug-`console.log` der rohen `GetServices()`-Antwort verifiziert, dann
wieder entfernt). Echter Push (`notify.send_message` auf
`notify.sailfishos_phone_2`) vom Nutzer direkt auf dem Gerät bestätigt
("ja"). `sfdk check -s harbour`/`-s rpmlint` auf allen drei
Architekturen sauber bis auf die bereits akzeptierte
`libkeepalive`-Warnung.

## 21. Update 2026-09-18 (Teil 2): SensorsView nach Raum gruppiert, v0.50

Nutzerwunsch: "Sensor Page auch nach Raum aufteilen und ausklappbar
machen" -- `qml/views/SensorsView.qml` gruppierte Sensoren bisher nach
Messgrösse (Temperatur/Batterie/...), nicht nach Raum. Umgebaut auf
exakt das gleiche Muster wie `RoomsView.qml`: `HaApi.getAreaMap()` für
die Raumzuordnung, `expandedRooms`/`toggleRoom()` fürs Ein-/Ausklappen
(Räume starten eingeklappt), gleicher Header-Zeilen-Stil (▸/▾ +
Raumname + Anzahl). Ein Raum kann jetzt gemischte Sensor-Typen
enthalten (z.B. Temperatur+Energie+Luftdruck im selben Raum
hintereinander) -- Wert+Einheit-Format unverändert. Die
Kategorie-Header (Temperatur/Batterie/...) sind entfallen.

**Swipe-Simulation war diese Session unzuverlässig** (anders als in
früheren Sessions, s. [[sailfishos-sdk-workflow]]) -- mehrere Versuche
mit dem sonst funktionierenden Einzelsprung-Muster landeten inkonsistent
(mal gar keine Bewegung, mal zwei Seiten übersprungen). Statt blind der
Code-Analogie zu RoomsView.qml zu vertrauen, kurzzeitig
`FirstPage.qml`s `SilicaFlickable` um `Component.onCompleted: contentX = page.width`
ergänzt, um direkt auf der Sensor-Seite zu landen, per Screenshot
verifiziert (Räume mit Zähler, Ausklappen funktioniert, gemischte
Sensor-Typen korrekt), Debug-Zeile danach wieder entfernt.

Auf Nutzerrückfrage ("hat jede Seite ein Titel...?") aufgefallen:
`RoomsView.qml`s `PageHeader` zeigte "HA Control" (den App-Namen) statt
eines Seitentitels -- als einzige der drei Sub-Views ohne eigenen Titel
(Sensor-Übersicht/Updates hatten schon einen). Auf "Räume" geändert.

**Versionssprung 0.13 → 0.50**: nach Rückfrage (per AskUserQuestion, da
"0.5" als Wunsch unklar war -- Rücksprung oder Tippfehler für die
fortlaufende Zählung) hat der Nutzer den Sprung auf 0.50 explizit
bestätigt, kein Fortsetzen der fortlaufenden 0.1x-Zählung.

## 22. Update 2026-09-18 (Teil 3): Zugangsdaten verschlüsselt in Sailfish Secrets, v0.51

Ziel: HA-URL und Long-Lived Access Token nicht mehr im Klartext in dconf
(`ConfigurationValue`) ablegen, sondern über Sailfish Secrets verschlüsselt,
an die Gerätesperre gebunden, mit der Sailjail-Berechtigung `Secrets`.
Nutzerauftrag war ausdrücklich "auf dem Handy testen" -- das Ergebnis vorweg:
**läuft auf der realen Jolla Phone**, Details und Belege unten.

**Der erste, rein in QML gebaute Anlauf war nicht reparierbar** (v0.50-3 auf
dem Gerät installiert, Journal-Mitschnitt per `devel-su journalctl -f`):

- `Credentials.qml:125: Error: Cannot assign QJSValue to
  Sailfish::Secrets::Secret::Identifier` -- das JS-Objektliteral, das den
  Identifier für `StoredSecretRequest` setzen sollte. Grund (in den Quellen
  von `sailfish-secrets` nachgelesen, nicht geraten): `Secret::Identifier`
  ist in `lib/Secrets/secret.h` eine einfache C++-Klasse ohne
  `Q_OBJECT`/`Q_GADGET`, und `qml/Secrets/main.cpp` registriert sie
  nirgends -- sie ist in QML damit weder konstruierbar noch zuweisbar. Der
  Lese-Pfad ist über die QML-API also gar nicht bedienbar.
- `Credentials.qml:64: Error: Cannot assign int to an unregistered type`
  (bei jedem Speicherversuch) -- `StoreSecretRequest.secretStorageType` ist
  ein Enum ohne `Q_ENUM`; auch die (im Dateikommentar als funktionierend
  dokumentierte) imperative Zuweisung aus JS scheitert.
- Gegenprobe: in
  `~/.local/share/system/privileged/Secrets/.../secrets.db` kein Treffer für
  `harbour-hacontrol`, WAL-Zeitstempel unverändert -- es wurde nichts
  gespeichert. Die App war nach manueller Eingabe nur im RAM konfiguriert
  (ein Neustart hätte die Werte verloren).

**Umgesetzt: C++-Kapselung** (`src/credentials.{h,cpp}`, erstes natives
Objekt in diesem Projekt -- das README warb bisher explizit mit "kein
C++-Bridge-Objekt"):

- Klasse `Credentials : QObject` mit `baseUrl`/`token`/`loaded`/`lastError`/
  `saveBusy`/`lastSaveOk` als Properties und `save(url, token)`/`reload()`;
  in `main()` als Context-Property `Credentials` gesetzt, dadurch bleiben
  alle QML-Aufrufstellen unverändert (nur die `import "../lib"`-Zeilen
  fielen weg). Das QML-Singleton `qml/lib/Credentials.qml` und `qmldir`
  wurden gelöscht -- damit verschwand auch die Build-Warnung
  `qmldeps: no valid module definition`.
- Requests laufen asynchron (`statusChanged`), nie `waitForFinished()` im
  UI-Thread. Speichern ist ein Upsert: erst `DeleteSecretRequest`, dann
  `StoreSecretRequest` (`SecretAlreadyExistsError` sonst).
- **Plugin-Wahl zur Laufzeit statt fest verdrahtet**: `PluginInfoRequest`
  fragt beim Start beim Daemon, welche Plugins er kennt. Zwei auf dem Gerät
  verifizierte Stolperfallen: (1) `StandaloneDeviceLockSecret` mit dem
  *encrypted storage*-Plugin scheiterte -- `No such storage plugin exists:
  org.sailfishos.secrets.plugin.encryptedstorage.sqlcipher`, obwohl die
  `.so` installiert ist und der Daemon das Plugin in
  `encryptedStoragePlugins` auch auflistet; er akzeptiert es nur nicht als
  *Storage*-Plugin. (2) Ohne `encryptionPluginName` scheitert der Store mit
  `No such encryption plugin exists: ` (leerer Name). Funktionierende
  Kombination auf der Jolla Phone:
  `org.sailfishos.secrets.plugin.storage.sqlite` +
  `org.sailfishos.secrets.plugin.encryption.openssl`.
- **Einmalige Migration** (`qml/harbour-hacontrol.qml`): vorhandene
  Klartextwerte werden beim Start automatisch nach Secrets übernommen,
  danach werden die dconf-Kopien geleert -- aber **erst nach bestätigtem
  Store** (`saveBusy`/`lastSaveOk`). Erste Fassung löschte unbedingt und
  hätte bei fehlgeschlagenem Store die Zugangsdaten vernichtet (ist beim
  ersten Testlauf genau so passiert; die Werte wurden für den weiteren Test
  per `dconf load` aus dem Backup wiederhergestellt).
- SettingsPage schreibt bei Fokusverlust/Seitenwechsel statt bei jedem
  Tastendruck, nur wenn beide Felder vollständig sind und sich geändert
  haben, und zeigt `lastError` des Daemons an.

**Verifiziert auf der realen Jolla Phone (aarch64, 192.168.2.15)**:

- Store + Migration: Journal `Credentials: stored "baseUrl"` /
  `"token"`, danach sind `baseUrl`/`token` in dconf leer.
- Persistenz über einen App-Neustart: `Credentials: loaded -- baseUrl 17
  chars, token 183 chars` (17 = `https://ha.zwx.ch`, 183 = Tokenlänge) --
  ohne jede Neueingabe.
- Echte Verbindung: der App-Prozess hat eine ESTABLISHED-TLS-Verbindung zu
  `109.202.212.70:443`, das ist die aufgelöste `ha.zwx.ch` -- die aus Secrets
  geladenen Werte werden also tatsächlich gegen die reale Instanz benutzt.
- Keine QML-Fehler mehr im Journal (die beiden oben genannten sind weg).
- **Harbour**: `sfdk check -s harbour` läuft sauber durch, nachdem
  `Requires: libsailfishsecrets` entfernt wurde -- der Validator lehnt den
  reinen Paketnamen ab ("Dependency not allowed"), während die von rpmbuild
  automatisch erzeugte Soname-Abhängigkeit `libsailfishsecrets.so.0()(64bit)`
  (steht in Harbours Allowed-APIs-Liste) akzeptiert wird. Nicht selbst als
  Soname hinschreiben -- genau das hatte in v0.7 bei `libkeepalive` die
  echte `pkcon`-Installation zerschossen. `-s rpmlint` weiterhin nur mit der
  akzeptierten `explicit-lib-dependency libkeepalive`-Meldung.

**Nachtrag, selbe Session -- Pull-down-Refresh + Geräte-Sensoren (0.51-2)**:
Nutzerwunsch "refresh pull down soll refresh auf allen seiten machen" plus
"teste noch mal ob home sensor daten von phone erhält".

- Die drei Sub-Views liegen gleichzeitig nebeneinander in einer Row und laden
  ihre Daten selbst; ein Refresh nur der sichtbaren liess die anderen mit
  veralteten Daten zurück. Jede View hat jetzt ein `refreshRequested()`-Signal,
  `FirstPage.qml` bündelt das in `refreshAll()` und ruft alle drei `refresh()`
  auf.
- **Befund zu den Geräte-Sensoren**: In HA standen `sensor.sailfishos_phone_*_2`
  seit Stunden still, obwohl die App lief -- der 10-Minuten-`BackgroundJob`
  feuert nicht, solange die App im Vordergrund ist (nur über den BackgroundJob
  wurden die Sensoren bisher gemeldet). Darum meldet die App den Geräte-Status
  jetzt zusätzlich bei jedem App-Start (`onLoadedChanged`) und bei jedem
  Pull-down-Refresh (`updateDeviceSensors()`), mit Journal-Log
  (`DeviceSensors: 3 Sensoren an HA gemeldet`).
- **Wichtige HA-Eigenschaft, die die Diagnose erst verwirrte**: HAs
  `mobile_app`-Ablauf schreibt einen Sensorwert nur, wenn er sich tatsächlich
  ändert -- `last_updated` bleibt also stehen, auch wenn die App erfolgreich
  meldet (`{"battery_level":{"success":true},...}`). Nachgewiesen per
  Gegenprobe: der Token-Webhook wurde von aussen mit Akkustand `91` beschickt
  (HA zeigte 91), danach der App-Neustart -- HA stand auf `90` mit frischem
  `last_updated`, also dem echten Wert des Handys (`/sys/class/power_supply/
  battery/capacity`). Die Zustellung Handy → HA ist damit belegt, nicht nur
  behauptet.
- Auf der Hardware geprüft: 0.51-2 installiert, Journal ohne QML-Fehler,
  `Credentials: loaded -- baseUrl 17 chars, token 183 chars`, zweimal
  `DeviceSensors: 3 Sensoren an HA gemeldet`. Der Pull-down selbst braucht
  einen Tap aufs Gerät (Touchscreen kann ich nicht bedienen) -- noch vom
  Nutzer zu bestätigen.

**Noch offen**: Emulator-Test (i486) und `armv7hl`-Build/-Check für v0.51
(bisher nur aarch64 gebaut und auf Hardware getestet); Bestätigung des
Pull-down-Refresh durch einen Tap auf dem Gerät; der Zugangsdaten-Backup
`~/sailhacontrol-credentials-backup.txt` kann nach der Migration gelöscht
werden.

## 23. Update 2026-09-18 (Teil 4): Cover nach UI-Guidelines nachgebessert, drei Bugs dabei gefunden, v0.52

Ausgangspunkt war ein Abgleich der App gegen die offiziellen UI-Guidelines
(`docs.sailfishos.org/Develop/Apps/UI/`). Das meiste war schon konform: jede
Sub-View hat einen eigenen `PageHeader` und ein Pull-down-Menü mit nur zwei
Einträgen (die Guideline empfiehlt unter fünf), der horizontale Seitenwechsel
hat mit dem `HorizontalScrollDecorator` den Silica-eigenen Gesten-Hinweis, und
die Detailseiten sind echte gestapelte `Page`s statt Dialoge.

Die eine echte Lücke war `qml/cover/CoverPage.qml`: ein statisches
"HA Control"-Label, obwohl Covers laut Guideline "key information" zeigen und
"Cover Actions for quick tasks without opening apps" anbieten sollen.

**Umgesetzt:**
- Der Cover zeigt jetzt die Anzahl eingeschalteter Lichter ("4 Lichter an" /
  "Alle Lichter aus").
- Eine `CoverAction` schaltet das zuletzt in der App bediente Licht um, ohne
  die App zu öffnen. Icon ist `icon-cover-favorite` -- im Stock-Theme gibt es
  kein Lampen-/Power-Icon (per `sfdk tools exec` in der Icon-Liste des
  Build-Targets geprüft, nicht geraten).
- Beides wird von `RoomsView.qml` über drei `ConfigurationValue`s nachgeführt
  (`coverLightsOnCount`, `coverLastLightId`, `coverLastLightName`), gleiches
  Muster wie `webhookIdSetting`. So braucht der Cover keine eigene HA-Abfrage,
  während die App im Hintergrund ist.

**Bug 1 -- Listen blieben bis zum manuellen Pull-down leer.** Fiel beim Testen
auf und war schon länger da, nur als Gewohnheit abgetan ("man muss halt immer
einmal refreshen"). Ursache: `Component.onCompleted: refresh()` feuert in allen
drei Sub-Views, bevor der asynchrone Sailfish-Secrets-Request von `Credentials`
fertig ist -- `baseUrl`/`token` sind dann noch leer, der Versuch läuft ins Leere
(SensorsView/UpdatesView zeigten sogar sichtbar "Noch nicht konfiguriert"), und
nichts holte ihn danach nach. Fix: RoomsView reagiert zusätzlich auf
`onConfiguredChanged`, SensorsView/UpdatesView auf `Credentials`'
`onBaseUrlChanged`/`onTokenChanged`.

**Bug 2 -- ANR beim Refresh (selbst eingebaut).** Die erste Fassung der
Lichter-Zählung machte einen vollen Scan über `entriesModel` -- einmal pro
Refresh und zusätzlich bei **jedem einzelnen** `light`-`state_changed`-Event
über den WebSocket. Bei der echten Instanz (~1500 Entities, 700+ Zeilen im
Model) und einem Handy unter hoher Last (Android App Support mit mehreren
residenten Apps, `loadavg` > 15) blockierte das den `QSGRenderThread`
dauerhaft: die App lief in ein echtes ANR ("HA Control reagiert nicht"), kein
Absturz. Nachgewiesen per `/proc/<pid>/task/<tid>/stat`-Sampling -- der
Render-Thread sammelte durchgehend ~8-10 CPU-Ticks pro Sekunde, statt in den
Leerlauf zurückzufallen. Fix: die Zählung läuft in `buildEntries()` im selben
Durchlauf mit, der ohnehin über das rohe `states`-Array iteriert, und bei
Live-Updates wird nur noch inkrementell (+1/-1) nachgeführt.

**Bug 3 -- Seitenwechsel zu empfindlich, und der erste Fix war schlimmer.**
Ein etwas kräftigerer Flick liess die `SilicaFlickable` frei weitergleiten;
die Snap-Logik rastete dann auf der nächstgelegenen Seite ein und übersprang
eine (Räume -> direkt Updates). Das Snap-Ziel wird jetzt auf +/-1 Seite
gegenüber der Startseite der Geste begrenzt. Der erste Versuch merkte sich die
Startseite in `onMovementStarted` -- das feuert aber auch bei der
**programmatischen** Snap-Animation, wodurch die Startseite mitten in der
Animation neu gesetzt wurde, das geclampte Ziel sich verschob, die nächste
Animation startete, und so weiter: Endlosschleife, Render-Thread dauerhaft
belegt, ANR rund eine Sekunde nach dem Start, noch vor dem Datenladen. Merkregel
für künftige Flickables: Snap-Logik gehört an `onDragStarted` plus ein
`userGesture`-Flag, nie an die Movement-Signale allein.

**Neu dazugelernt: UI-Tests auf dem echten Gerät sind möglich.** Bisher galt
"über SSH kein Display-Zugriff, visuelle Prüfung nur im Emulator". Tatsächlich
lassen sich Touch-Events direkt in den Touchscreen einspeisen: `hyn_ts` ist
`/dev/input/event5`, seine ABS-Range deckt sich 1:1 mit der Display-Auflösung
(1032x2272), `evemu`-Tools fehlen zwar, aber `python3` ist da und kann rohe
`struct input_event`s schreiben (Type-B-Multitouch: `ABS_MT_SLOT`,
`ABS_MT_TRACKING_ID`, `ABS_MT_POSITION_X/Y`, `BTN_TOUCH`, `SYN_REPORT`; das
Loslassen unbedingt in ein `finally` legen, sonst bleibt der Touchscreen für
den echten Finger blockiert). Damit wurde v0.52 auf der Hardware geprüft statt
nur im Emulator: alle drei Seiten laden beim Start von selbst (Räume,
Sensor-Übersicht, Update-Übersicht je mit echten Daten), ein kräftiger Flick
bewegt genau eine Seite, der Render-Thread bleibt im Leerlauf (1 CPU-Tick über
3 Sekunden), und der Cover zeigt live "4 Lichter an".

**Noch offen**: Der Cover-Stern erscheint erst, nachdem einmal ein Lichtschalter
in der App selbst angetippt wurde -- `coverLastLightId` ist bis dahin leer. Das
ist so gewollt ("zuletzt bedientes Licht"), war beim ersten Test aber
verwirrend.
