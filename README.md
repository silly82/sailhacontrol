# HA Control

A native [Sailfish Silica](https://sailfishos.org/) app to control a local [Home Assistant](https://www.home-assistant.io/) instance from a SailfishOS phone — no cloud dependency, no Companion App.

See [`KONZEPT.md`](KONZEPT.md) (German) for the full design concept and dated development log.

## Status: v0.7, working prototype

- Entity list (lights/switches) with toggle, grouped by Home Assistant Area/Room, collapsible per room.
- Tap a light's name to open brightness / color / color-temperature controls — only the controls that light actually supports are shown. The toggle switch itself is unchanged.
- Cross-room sensor overview (temperature, humidity, atmospheric pressure), rounded to one decimal, only sensors currently reporting a value.
- Swipe left/right between the room view and the sensor overview — no menu navigation needed.
- **Live updates via WebSocket**: an external change (HA web UI, physical switch, automation) shows up in the app immediately, no manual refresh needed.
- Local background poll (every 10 min) with a notification when a watched entity's state changes — the notification itself has a toggle button, actionable right from the lock screen without opening the app. (There's no public lockscreen-widget API on SailfishOS for third-party apps; this is the closest equivalent.)
- Confirmed working end-to-end against a real, large (1500+ entity) Home Assistant instance, on both the SailfishOS SDK emulator and a real aarch64 device.
- Passes Jolla's official Harbour validation (`sfdk check -s harbour` / `-s rpmlint`) cleanly on all three architectures -- not yet actually submitted to the Jolla Store, but the package itself is store-ready.

Not yet implemented: remote (non-local-network) access.

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
2. In HA Control: pull down → **Settings** → enter your Home Assistant URL (e.g. `http://homeassistant.local:8123`) and the token.
3. Pull down → **Refresh**.

Local network only — no Nabu Casa / reverse-proxy support yet.

## Known limitations

- Token is stored in plain text via `org.nemomobile.configuration` (dconf) — fine for a single-user device, not a shared one.
- The `armv7hl` build is untested (see table above).
- Background notifications rely on `Nemo.KeepAlive`'s `BackgroundJob`, which only keeps the app process alive while it's already resident (foreground or recently backgrounded) — a fully terminated app is not woken up by it.
- The WebSocket subscription receives every entity's `state_changed` event (Home Assistant doesn't support server-side domain filtering here) — on a very large instance this is a lot of client-side filtering; not a problem in testing, but a possible future optimization.
- While a light is off, Home Assistant reports `brightness`/`color_temp_kelvin`/`rgb_color` as `null` — the detail page's sliders then show a starting value, not the light's remembered setting. This is a Home Assistant data-model characteristic, not something the app can work around.
- The notification's toggle button only works while the app process is resident (same constraint as the background poll itself) — there's no D-Bus activation `.service` file, so a fully terminated app won't handle the action.

## License

[MIT](LICENSE)

---

# HA Control (Deutsch – Schweizer Hochdeutsch)

Eine native [Sailfish-Silica](https://sailfishos.org/)-App zur Steuerung einer lokalen [Home-Assistant](https://www.home-assistant.io/)-Instanz von einem SailfishOS-Telefon aus — ohne Cloud-Abhängigkeit, ohne Companion-App.

Das vollständige Konzept und ein datiertes Entwicklungsprotokoll finden sich in [`KONZEPT.md`](KONZEPT.md).

## Status: v0.7, funktionierender Prototyp

- Entity-Liste (Lights/Switches) mit Toggle, gruppiert nach Home-Assistant-Area/Room, pro Raum ein-/ausklappbar.
- Tap auf den Namen eines Lichts öffnet Helligkeit-/Farb-/Farbtemperatur-Regler — nur was das jeweilige Licht tatsächlich unterstützt wird angezeigt. Der Toggle-Switch selbst bleibt unverändert.
- Raumübergreifende Sensor-Übersicht (Temperatur, Feuchtigkeit, Luftdruck), auf eine Nachkommastelle gerundet, nur Sensoren mit aktuell gültigem Wert.
- Wischen nach links/rechts zwischen Raumansicht und Sensor-Übersicht — keine Menü-Navigation nötig.
- **Live-Updates per WebSocket**: eine externe Änderung (HA-Weboberfläche, physischer Schalter, Automatisierung) erscheint sofort in der App, kein manuelles Refresh nötig.
- Lokaler Hintergrund-Poll (alle 10 Minuten) mit Benachrichtigung bei Zustandsänderung einer beobachteten Entity — die Benachrichtigung selbst hat einen Umschalten-Button, direkt vom Sperrbildschirm aus bedienbar, ohne die App zu öffnen. (Es gibt keine öffentliche Lockscreen-Widget-API für Drittanbieter-Apps auf SailfishOS -- das ist das nächstliegende Äquivalent.)
- Bestätigt funktionierend, Ende-zu-Ende, gegen eine echte, grosse (1500+ Entities) Home-Assistant-Instanz — sowohl im SailfishOS-SDK-Emulator als auch auf einem echten aarch64-Gerät.
- Besteht Jollas offizielle Harbour-Validierung (`sfdk check -s harbour` / `-s rpmlint`) sauber auf allen drei Architekturen — noch nicht tatsächlich im Jolla Store eingereicht, das Paket selbst ist aber store-fertig.

Noch nicht umgesetzt: Remote-Zugriff (ausserhalb des lokalen Netzes).

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
2. In HA Control: Pull-down → **Settings** → Home-Assistant-URL (z. B. `http://homeassistant.local:8123`) und den Token eintragen.
3. Pull-down → **Refresh**.

Nur lokales Netz — Nabu Casa / Reverse-Proxy wird noch nicht unterstützt.

## Bekannte Einschränkungen

- Der Token wird im Klartext über `org.nemomobile.configuration` (dconf) gespeichert — für ein Einzelbenutzer-Gerät akzeptabel, nicht für ein geteiltes Gerät gedacht.
- Der `armv7hl`-Build ist ungetestet (siehe Tabelle oben).
- Hintergrund-Benachrichtigungen basieren auf `Nemo.KeepAlive`s `BackgroundJob`, welcher den App-Prozess nur wach hält, solange dieser ohnehin bereits resident ist (im Vordergrund oder kürzlich in den Hintergrund geschickt) — eine vollständig beendete App wird dadurch nicht wieder gestartet.
- Das WebSocket-Abo erhält jedes `state_changed`-Event aller Entities (Home Assistant kennt hier keine serverseitige Domain-Filterung) — bei einer sehr grossen Instanz entsprechend viel Client-seitiges Filtern; im Test kein Problem, aber ein möglicher Kandidat für spätere Optimierung.
- Solange ein Licht aus ist, meldet Home Assistant `brightness`/`color_temp_kelvin`/`rgb_color` als `null` — die Regler auf der Detail-Seite zeigen dann einen Startwert, nicht die gespeicherte Einstellung des Lichts. Das liegt am Datenmodell von Home Assistant, nicht an der App.
- Der Umschalten-Button auf der Benachrichtigung funktioniert nur, solange der App-Prozess resident ist (gleiche Einschränkung wie der Hintergrund-Poll selbst) — es gibt kein D-Bus-Activation-`.service`-File, eine vollständig beendete App reagiert also nicht auf den Button.

## Lizenz

[MIT](LICENSE)
