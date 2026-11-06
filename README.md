# HA Control

A native [Sailfish Silica](https://sailfishos.org/) app to control a local [Home Assistant](https://www.home-assistant.io/) instance from a SailfishOS phone — no cloud dependency, no Companion App.

See [`KONZEPT.md`](KONZEPT.md) for the full design concept and dated development log. ([`KONZEPT_DE.md`](KONZEPT_DE.md) holds the original German text up to section 24; it is no longer updated.)

## Status: v0.58, ready for use

- Entity list (lights/switches/fans/covers) with toggle, grouped by Home Assistant Area/Room, collapsible per room. Lights with a known color/color-temperature show a small color swatch next to the switch.
- Tap a light's name to open brightness / color / color-temperature controls — only the controls that light actually supports are shown. The toggle switch itself is unchanged.
- Tap a thermostat's name to open a target-temperature slider and HVAC mode selection (off/heat/auto/...).
- Tap a media player's name to open play/pause/skip controls and a volume slider (shown only if the player reports `volume_level`).
- Scenes show up as an "Activate" row — tap activates them directly (`scene.turn_on`); scenes have no meaningful on/off state, so there's no switch.
- Sensor overview (temperature, humidity, atmospheric pressure, battery, energy, power), rounded to one decimal, only sensors currently reporting a value — grouped by room and collapsible, same as the room view.
- Cross-room updates overview — only devices that actually have a pending update, with current → new version and a one-tap "Install" action, which gives you five seconds to cancel before the firmware update actually starts. While an install is running, the version line becomes a progress bar (percentage if the device reports one, an animated indeterminate bar otherwise).
- Swipe left/right between the room view, the sensor overview, and the updates overview — no menu navigation needed. One swipe moves exactly one page, however hard you flick.
- The app cover (home screen / task switcher) shows how many lights are currently on and, optionally, the current weather, and offers up to **two cover buttons** — by default one that toggles the light you last switched from the app. Under Settings → **Cover & weather** each button can be set to any scene, script, light or switch.
- **Clearer layout** (v0.57): rooms are proper section headers, every entity has a small icon that lights up when the device is on, detail pages share one structure (big status, action buttons, controls), Settings is an overview with sub-pages (Connection, Device & sensors, Cover & weather), completed to-do items are folded away, and dots show which of the three swipe pages you're on.
- **Favorites**: long-press any entity → "Add to favorites". Favorites appear as an always-open group at the top of the room view (and stay in their room too).
- **Search**: a search field at the top of the room view filters by name or entity ID across all rooms.
- More entity types: `input_boolean` (switch), `script` / `button` / `input_button` (tap to run or press), **locks** (lock directly, unlock/open only after a five-second cancel window) and **covers with position** (tap the name for a position slider plus Open/Stop/Close).
- **Sensor history**: tap a sensor in the sensor overview for a chart of the last 6 hours, 24 hours or 7 days, with current, minimum and maximum.
- **Remote access**: an optional external URL (Nabu Casa, Tailscale, reverse proxy). The app uses the home URL when it is reachable and switches to the external one automatically when it isn't (or you fix the choice in Settings).
- **Cameras**: camera entities show up in their room; tap one for a still image that refreshes every few seconds while the page is open.
- **To-do and shopping lists**: pull down → "To-do lists" — check items off, add, rename or delete them; changes from other devices show up live.
- **Multiple Home Assistant instances** (e.g. home and camper): pick the instance at the top of Settings, add/rename/delete instances from its pull-down menu. Favorites, notifications, cover action and the device registration are kept per instance.
- **Assist**: pull down → "Assist" — type commands or questions in your own language ("Turn off the office light", "What's the temperature in the kitchen?"); Home Assistant answers in a chat view.
- **Weather**: a weather card at the top of the sensor overview with a five-day forecast; pick the weather entity in Settings → **Cover & weather** or by tapping the card.
- More entity types: **alarm panels** (arm home/away/night/vacation, disarm, PIN keypad when the panel needs a code), **vacuums** (start, pause, stop, return to dock, locate, fan speed), and **media players** now offer source selection, mute, power, cover art and a play/pause button right in the room list.
- **Actionable push notifications**: `actions` in a `notify.mobile_app_…` call become buttons on the notification; tapping one fires `mobile_app_notification_action` in Home Assistant. `tag` replaces an earlier notification, `clear_notification` removes it.
- **Notification buttons work when the app is closed**: tapping a button starts HA Control through D-Bus activation and performs the action.
- More device sensors reported to Home Assistant: Wi-Fi network and signal strength, free storage, and — only if you switch it on in Settings — the phone's location as a device tracker.
- **Live updates via WebSocket**: an external change (HA web UI, physical switch, automation) shows up in the app immediately, no manual refresh needed.
- Local background poll (every 10 min) with a notification when a watched entity's state changes — the notification itself has a toggle button, actionable right from the lock screen without opening the app. (There's no public lockscreen-widget API on SailfishOS for third-party apps; this is the closest equivalent.)
- **Real `mobile_app` integration**: the device registers with HA and gets a genuine `notify.mobile_app_<device>` target, delivered instantly over the app's existing WebSocket connection while it's running (no cloud/Google/Apple push infrastructure involved). Three device-status sensors (battery level, charging, connection type) are reported back to HA every 10 minutes (piggybacking on the same background poll) and also on every app start and every pull-down refresh — the background job does not fire while the app is in the foreground, and HA only rewrites a sensor when its value actually changes, so a silent timestamp does not mean the app stopped reporting.
- **HA URL and token are stored in Sailfish Secrets** (encrypted, tied to the device lock) rather than plaintext — see the C++ note under Known limitations. An existing installation's values are migrated automatically once and the plaintext copies are then cleared.
- Pages load their data by themselves, but only the one you are looking at: loading all three at startup meant fetching and parsing the full entity list three times over, which made startup crawl on a loaded device. The others load the first time you swipe to them. Pull-down "Refresh" still refreshes every page you have actually opened. If Home Assistant does not answer within 15 seconds, the page says so instead of spinning forever, and it recovers on its own once the connection is back.
- Confirmed working end-to-end against a real, large (1500+ entity) Home Assistant instance, on both the SailfishOS SDK emulator and a real aarch64 device.
- Passes Jolla's official Harbour validation (`sfdk check -s harbour` / `-s rpmlint`) cleanly on all three architectures -- not yet actually submitted to the Jolla Store, but the package itself is store-ready.

## Installing

Three RPMs are attached to each [release](../../releases) — pick the one matching your device:

| File | Target | Status |
|---|---|---|
| `harbour-hacontrol-<version>.i486.rpm` | SailfishOS SDK Emulator | Tested |
| `harbour-hacontrol-<version>.aarch64.rpm` | Newer 64-bit phones (e.g. Jolla Phone, most current devices) | Tested on real hardware |
| `harbour-hacontrol-<version>.armv7hl.rpm` | Older 32-bit ARM phones (e.g. Jolla 1, Xperia X-era devices) | **Builds cleanly, but untested — no armv7hl hardware was available to verify it on** |

Install via `pkcon install-local -y <file>.rpm` over SSH (as `devel-su`), or `sfdk deploy` from a development machine. Not published on the Jolla Store — Sailjail will show a one-time permission prompt (Internet access) on first launch that needs to be confirmed on-device.

## Setup

1. In Home Assistant: your profile (bottom of the sidebar) → **Security** tab → **Long-lived access tokens** → **Create Token**. Copy it immediately, it's shown only once.
2. In HA Control: pull down → **Settings** → **Connection** → enter your Home Assistant URL (e.g. `http://homeassistant.local:8123`) and the token.
3. Swipe back. The list loads by itself once both fields are filled in; pull down → **Refresh** forces a reload at any time.

Away from home: enter an **External URL** (e.g. `https://xxxx.ui.nabu.casa` or a Tailscale address) in Settings → **Connection**. The same token is used for both URLs.

## Translations

The app is in English, with a complete German translation. It follows the phone's language. Translations into more languages are very welcome: copy one template file, translate it (e.g. with Qt Linguist) and send it in. No build changes are needed. See [TRANSLATING.md](TRANSLATING.md).

## Known limitations

- HTTPS connections use TLS 1.2: the app's Qt 5.6 deadlocks on TLS 1.3 handshakes (see KONZEPT.md section 29). Every reverse proxy, Nabu Casa and Tailscale serve still support TLS 1.2.

- URL and token are stored via **Sailfish Secrets** (encrypted, tied to the device lock), not in plaintext in dconf. That needs C++ (`src/credentials.h/.cpp`): the QML `Sailfish.Secrets` module cannot express the two requests involved — `StoredSecretRequest.identifier` is of a type the plugin never registers, and `StoreSecretRequest.secretStorageType` is an enum without `Q_ENUM`, so both fail from QML (verified on-device). Which storage/encryption plugin to use is asked from the daemon at startup rather than hardcoded, because the image may not register the encrypted-storage plugin.
- The `armv7hl` build is untested (see table above).
- Background notifications rely on `Nemo.KeepAlive`'s `BackgroundJob`, which only keeps the app process alive while it's already resident (foreground or recently backgrounded) — a fully terminated app is not woken up by it.
- The WebSocket subscription receives every entity's `state_changed` event (Home Assistant doesn't support server-side domain filtering here) — on a very large instance this is a lot of client-side filtering; not a problem in testing, but a possible future optimization.
- While a light is off, Home Assistant reports `brightness`/`color_temp_kelvin`/`rgb_color` as `null` — the detail page's sliders then show a starting value, not the light's remembered setting. This is a Home Assistant data-model characteristic, not something the app can work around.
- Notification buttons (Toggle, and the action buttons of Home Assistant push notifications) also work when the app is closed: tapping one starts HA Control through D-Bus activation (`ExecDBus`; Sailjail generates the activation file) and performs the action; the app window opens. The background poll for watched entities and *receiving* new push notifications still need the app to be running, because the push channel is the app's WebSocket connection.
- Real push (`notify.mobile_app_...`) and the device-status sensors likewise only work while the app process is resident — the WebSocket connection they rely on is gone once the app is fully closed.

## License

[MIT](LICENSE)

---

# HA Control (Deutsch 🇨🇭)

Eine native [Sailfish-Silica](https://sailfishos.org/)-App zur Steuerung einer lokalen [Home-Assistant](https://www.home-assistant.io/)-Instanz von einem SailfishOS-Telefon aus — ohne Cloud-Abhängigkeit, ohne Companion-App.

Das vollständige Konzept und ein datiertes Entwicklungsprotokoll finden sich in [`KONZEPT.md`](KONZEPT.md) (Englisch). Die ursprüngliche deutsche Fassung bis Abschnitt 24 steht in [`KONZEPT_DE.md`](KONZEPT_DE.md) und wird nicht mehr fortgeschrieben.

## Status: v0.58, einsatzbereit

- Entity-Liste (Lights/Switches/Fans/Covers) mit Toggle, gruppiert nach Home-Assistant-Area/Room, pro Raum ein-/ausklappbar. Lichter mit bekannter Farbe/Farbtemperatur zeigen einen kleinen Farb-Punkt neben dem Switch.
- Tap auf den Namen eines Lichts öffnet Helligkeit-/Farb-/Farbtemperatur-Regler — nur was das jeweilige Licht tatsächlich unterstützt wird angezeigt. Der Toggle-Switch selbst bleibt unverändert.
- Tap auf den Namen eines Thermostats öffnet einen Zieltemperatur-Regler und die Modus-Auswahl (Aus/Heizen/Automatik/...).
- Tap auf den Namen eines Media Players öffnet Play/Pause/Vor/Zurück und einen Lautstärke-Regler (nur sichtbar, falls die Entity `volume_level` liefert).
- Szenen erscheinen als "Aktivieren"-Zeile — Tap aktiviert sie direkt (`scene.turn_on`); Szenen haben keinen sinnvollen on/off-Zustand, darum kein Switch.
- Sensor-Übersicht (Temperatur, Feuchtigkeit, Luftdruck, Batterie, Energie, Leistung), auf eine Nachkommastelle gerundet, nur Sensoren mit aktuell gültigem Wert — gruppiert nach Raum und ein-/ausklappbar, gleich wie die Raumansicht.
- Raumübergreifende Update-Übersicht — nur Geräte mit tatsächlich anstehendem Update, mit aktueller → neuer Version und einem "Installieren"-Button per Tap, der fünf Sekunden Zeit zum Abbrechen lässt, bevor das Firmware-Update wirklich startet. Während der Installation wird aus der Versions-Zeile ein Fortschrittsbalken (Prozentzahl falls vom Gerät geliefert, sonst ein animierter unbestimmter Balken).
- Wischen nach links/rechts zwischen Raumansicht, Sensor-Übersicht und Update-Übersicht — keine Menü-Navigation nötig. Ein Wisch bewegt genau eine Seite weit, egal wie kräftig gewischt wird.
- Der App-Cover (Startbildschirm / Task-Switcher) zeigt, wie viele Lichter gerade an sind und auf Wunsch das aktuelle Wetter, und bietet bis zu **zwei Cover-Tasten** — standardmässig eine, die das zuletzt in der App geschaltete Licht umschaltet. Unter Einstellungen → **Cover & Wetter** lässt sich jede Taste auf eine Szene, ein Skript, ein Licht oder einen Schalter legen.
- **Übersichtlichere Oberfläche** (v0.57): Räume als richtige Abschnitts-Überschriften, ein kleines Symbol pro Gerät, das bei eingeschaltetem Gerät hervorgehoben wird, Detailseiten mit einheitlichem Aufbau (grosser Status, Aktionsknöpfe, Steuerung), Einstellungen als Übersicht mit Unterseiten (Verbindung, Gerät & Sensoren, Cover & Wetter), erledigte To-do-Einträge eingeklappt und Punkte, die zeigen, auf welcher der drei Wischseiten man ist.
- **Favoriten**: langes Drücken auf einen Eintrag → "Zu Favoriten hinzufügen". Favoriten erscheinen als immer offene Gruppe oben in der Raumansicht (und bleiben auch in ihrem Raum).
- **Suche**: ein Suchfeld oben in der Raumansicht filtert über alle Räume nach Name oder Entity-ID.
- Mehr Gerätetypen: `input_boolean` (Schalter), `script` / `button` / `input_button` (Antippen führt aus bzw. drückt), **Schlösser** (Abschliessen direkt, Aufschliessen/Öffnen erst nach fünf Sekunden Abbruchfrist) und **Rollläden mit Position** (Antippen des Namens öffnet einen Positionsregler plus Öffnen/Stopp/Schliessen).
- **Sensor-Verlauf**: Antippen eines Sensors in der Sensor-Übersicht zeigt eine Kurve der letzten 6 Stunden, 24 Stunden oder 7 Tage, mit aktuellem Wert, Minimum und Maximum.
- **Zugriff von unterwegs**: eine optionale externe URL (Nabu Casa, Tailscale, Reverse-Proxy). Die App nimmt die Heim-URL, wenn sie erreichbar ist, und wechselt sonst automatisch auf die externe (oder man legt es in den Einstellungen fest).
- **Kameras**: Kamera-Entities erscheinen in ihrem Raum; Antippen zeigt ein Standbild, das sich alle paar Sekunden erneuert, solange die Seite offen ist.
- **To-do- und Einkaufslisten**: Pull-down → "To-do-Listen" — Einträge abhaken, hinzufügen, umbenennen oder löschen; Änderungen von anderen Geräten erscheinen live.
- **Mehrere Home-Assistant-Instanzen** (z. B. Zuhause und Camper): Instanz oben in den Einstellungen wählen, über deren Pull-down-Menü hinzufügen/umbenennen/löschen. Favoriten, Benachrichtigungen, Cover-Aktion und die Geräteregistrierung gelten jeweils pro Instanz.
- **Assist**: Pull-down → "Assist" — Befehle oder Fragen in der eigenen Sprache eintippen ("Schalte das Licht im Büro aus", "Wie warm ist es in der Küche?"); Home Assistant antwortet in einer Chat-Ansicht.
- **Wetter**: eine Wetter-Karte oben in der Sensor-Übersicht mit Vorhersage für fünf Tage; die Wetter-Entity wird in Einstellungen → **Cover & Wetter** oder durch Antippen der Karte gewählt.
- Mehr Gerätetypen: **Alarmanlagen** (scharf Zuhause/Abwesend/Nacht/Urlaub, unscharf, PIN-Tastenfeld, wenn die Anlage einen Code verlangt), **Saugroboter** (Start, Pause, Stopp, zur Station, Orten, Saugstufe), und **Mediaplayer** bieten jetzt Quellenwahl, Stummschalten, Ein/Aus, Albumcover und Play/Pause direkt in der Raumliste.
- **Push-Benachrichtigungen mit Aktionsknöpfen**: `actions` in einem `notify.mobile_app_…`-Aufruf werden zu Knöpfen in der Benachrichtigung; Antippen löst in Home Assistant `mobile_app_notification_action` aus. `tag` ersetzt eine frühere Benachrichtigung, `clear_notification` entfernt sie.
- **Benachrichtigungs-Knöpfe funktionieren auch bei geschlossener App**: Antippen startet HA Control per D-Bus-Aktivierung und führt die Aktion aus.
- Mehr Gerätesensoren an Home Assistant: WLAN-Name und Signalstärke, freier Speicher und — nur wenn in den Einstellungen eingeschaltet — der Standort des Telefons als Device-Tracker.
- **Live-Updates per WebSocket**: eine externe Änderung (HA-Weboberfläche, physischer Schalter, Automatisierung) erscheint sofort in der App, kein manuelles Refresh nötig.
- Lokaler Hintergrund-Poll (alle 10 Minuten) mit Benachrichtigung bei Zustandsänderung einer beobachteten Entity — die Benachrichtigung selbst hat einen Umschalten-Button, direkt vom Sperrbildschirm aus bedienbar, ohne die App zu öffnen. (Es gibt keine öffentliche Lockscreen-Widget-API für Drittanbieter-Apps auf SailfishOS -- das ist das nächstliegende Äquivalent.)
- **Echte `mobile_app`-Integration**: Das Gerät registriert sich bei HA und erhält ein echtes `notify.mobile_app_<gerät>`-Ziel, zugestellt sofort über die bestehende WebSocket-Verbindung der App, solange sie läuft (keine Cloud-/Google-/Apple-Push-Infrastruktur nötig). Drei Device-Status-Sensoren (Akkustand, Lädt, Verbindungsart) werden alle 10 Minuten an HA zurückgemeldet (huckepack auf dem bestehenden Hintergrund-Poll) und zusätzlich bei jedem App-Start und jedem Pull-down-Refresh — der Hintergrund-Job feuert nicht, solange die App im Vordergrund ist, und HA schreibt einen Sensor nur, wenn sich sein Wert tatsächlich ändert; ein unveränderter Zeitstempel heisst also nicht, dass die App nicht mehr meldet.
- **HA-URL und Token liegen in Sailfish Secrets** (verschlüsselt, an die Gerätesperre gebunden) statt im Klartext — siehe die C++-Anmerkung unter Bekannte Einschränkungen. Bestandsinstallationen werden einmalig automatisch migriert, danach werden die Klartext-Kopien gelöscht.
- Die Seiten laden ihre Daten von selbst, aber nur die gerade sichtbare: alle drei beim Start zu laden hiess, die komplette Entity-Liste dreimal zu holen und zu parsen — auf einem ausgelasteten Gerät wurde der Start dadurch zäh. Die übrigen laden beim ersten Hinwischen. Pull-down-"Refresh" aktualisiert weiterhin jede Seite, die man tatsächlich geöffnet hat. Antwortet Home Assistant 15 Sekunden lang nicht, sagt die Seite das, statt endlos zu drehen — und erholt sich von selbst, sobald die Verbindung wieder steht.
- Bestätigt funktionierend, Ende-zu-Ende, gegen eine echte, grosse (1500+ Entities) Home-Assistant-Instanz — sowohl im SailfishOS-SDK-Emulator als auch auf einem echten aarch64-Gerät.
- Besteht Jollas offizielle Harbour-Validierung (`sfdk check -s harbour` / `-s rpmlint`) sauber auf allen drei Architekturen — noch nicht tatsächlich im Jolla Store eingereicht, das Paket selbst ist aber store-fertig.

## Installation

Jedem [Release](../../releases) liegen drei RPMs bei — das passende für dein Gerät auswählen:

| Datei | Zielgerät | Status |
|---|---|---|
| `harbour-hacontrol-<version>.i486.rpm` | SailfishOS-SDK-Emulator | Getestet |
| `harbour-hacontrol-<version>.aarch64.rpm` | Neuere 64-Bit-Telefone (z. B. Jolla Phone, die meisten aktuellen Geräte) | Auf echter Hardware getestet |
| `harbour-hacontrol-<version>.armv7hl.rpm` | Ältere 32-Bit-ARM-Telefone (z. B. Jolla 1, Geräte aus der Xperia-X-Ära) | **Baut sauber, ist aber ungetestet — es stand keine armv7hl-Hardware zur Verifikation zur Verfügung** |

Installation via `pkcon install-local -y <datei>.rpm` über SSH (als `devel-su`), oder via `sfdk deploy` von einem Entwicklungsrechner aus. Nicht im Jolla Store veröffentlicht — Sailjail zeigt beim ersten Start einmalig eine Berechtigungsabfrage (Internetzugriff), die direkt auf dem Gerät bestätigt werden muss.

## Einrichtung

1. In Home Assistant: Profil (unten in der Seitenleiste) → Tab **Sicherheit** → **Langlebige Zugangs-Token** → **Token erstellen**. Sofort kopieren, er wird nur einmal angezeigt.
2. In HA Control: Pull-down → **Einstellungen** → **Verbindung** → Home-Assistant-URL (z. B. `http://homeassistant.local:8123`) und den Token eintragen.
3. Zurückwischen. Die Liste lädt von selbst, sobald beide Felder ausgefüllt sind; Pull-down → **Aktualisieren** erzwingt jederzeit ein Neuladen.

Unterwegs: unter Einstellungen → **Verbindung** eine **Externe URL** eintragen (z. B. `https://xxxx.ui.nabu.casa` oder eine Tailscale-Adresse). Für beide URLs wird derselbe Token verwendet.

## Übersetzungen

Die App ist auf Englisch und vollständig ins Deutsche übersetzt. Sie richtet sich nach der Sprache des Telefons. Weitere Sprachen sind sehr willkommen: eine Vorlagedatei kopieren, übersetzen (z. B. mit Qt Linguist) und einschicken. Am Build muss nichts geändert werden. Details in [TRANSLATING.md](TRANSLATING.md) (Englisch).

## Bekannte Einschränkungen

- HTTPS-Verbindungen nutzen TLS 1.2: Das Qt 5.6 der App verklemmt sich bei TLS-1.3-Verbindungsaufbauten (siehe KONZEPT.md Abschnitt 29). Reverse-Proxys, Nabu Casa und Tailscale serve unterstützen TLS 1.2 weiterhin.

- URL und Token werden über **Sailfish Secrets** verschlüsselt und an die Gerätesperre gebunden gespeichert, nicht mehr im Klartext in dconf. Dafür braucht es C++ (`src/credentials.h/.cpp`): das QML-Modul `Sailfish.Secrets` kann die beiden nötigen Requests nicht abbilden — `StoredSecretRequest.identifier` ist von einem Typ, den das Plugin nie registriert, und `StoreSecretRequest.secretStorageType` ist ein Enum ohne `Q_ENUM`; aus QML scheitern beide (auf dem Gerät verifiziert). Welches Storage-/Encryption-Plugin zu verwenden ist, wird beim Start beim Daemon erfragt statt fest verdrahtet, weil das Image das Encrypted-Storage-Plugin nicht unbedingt registriert.
- Der `armv7hl`-Build ist ungetestet (siehe Tabelle oben).
- Hintergrund-Benachrichtigungen basieren auf `Nemo.KeepAlive`s `BackgroundJob`, welcher den App-Prozess nur wach hält, solange dieser ohnehin bereits resident ist (im Vordergrund oder kürzlich in den Hintergrund geschickt) — eine vollständig beendete App wird dadurch nicht wieder gestartet.
- Das WebSocket-Abo erhält jedes `state_changed`-Event aller Entities (Home Assistant kennt hier keine serverseitige Domain-Filterung) — bei einer sehr grossen Instanz entsprechend viel Client-seitiges Filtern; im Test kein Problem, aber ein möglicher Kandidat für spätere Optimierung.
- Solange ein Licht aus ist, meldet Home Assistant `brightness`/`color_temp_kelvin`/`rgb_color` als `null` — die Regler auf der Detail-Seite zeigen dann einen Startwert, nicht die gespeicherte Einstellung des Lichts. Das liegt am Datenmodell von Home Assistant, nicht an der App.
- Benachrichtigungs-Knöpfe (Umschalten und die Aktionsknöpfe von Home-Assistant-Push-Nachrichten) funktionieren auch bei geschlossener App: Antippen startet HA Control per D-Bus-Aktivierung (`ExecDBus`; Sailjail erzeugt die Aktivierungsdatei) und führt die Aktion aus; das App-Fenster öffnet sich. Der Hintergrund-Poll für beobachtete Geräte und das *Empfangen* neuer Push-Nachrichten brauchen weiterhin die laufende App, weil der Push-Kanal die WebSocket-Verbindung der App ist.
- Echter Push (`notify.mobile_app_...`) und die Device-Status-Sensoren funktionieren ebenfalls nur, solange der App-Prozess resident ist — die dafür genutzte WebSocket-Verbindung existiert nicht mehr, sobald die App vollständig beendet ist.

## Lizenz

[MIT](LICENSE)
