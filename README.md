# HA Control

A native [Sailfish Silica](https://sailfishos.org/) app to control a local [Home Assistant](https://www.home-assistant.io/) instance from a SailfishOS phone — no cloud dependency, no Companion App, REST-API only.

See [`KONZEPT.md`](KONZEPT.md) (German) for the full design concept and dated development log.

## Status: v0.2, working prototype

- Entity list (lights/switches) with toggle, grouped by Home Assistant Area/Room, collapsible per room.
- Read-only sensor display (temperature, humidity, atmospheric pressure), rounded to one decimal.
- Local background poll (every 10 min) with a notification when a watched entity's state changes.
- Confirmed working end-to-end against a real, large (1500+ entity) Home Assistant instance, on both the SailfishOS SDK emulator and a real aarch64 device.

Not yet implemented: WebSocket live updates, lockscreen widget, remote (non-local-network) access.

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

---

# HA Control (Deutsch – Schweizer Hochdeutsch)

Eine native [Sailfish-Silica](https://sailfishos.org/)-App zur Steuerung einer lokalen [Home-Assistant](https://www.home-assistant.io/)-Instanz von einem SailfishOS-Telefon aus — ohne Cloud-Abhängigkeit, ohne Companion-App, nur über die REST-API.

Das vollständige Konzept und ein datiertes Entwicklungsprotokoll finden sich in [`KONZEPT.md`](KONZEPT.md).

## Status: v0.2, funktionierender Prototyp

- Entity-Liste (Lights/Switches) mit Toggle, gruppiert nach Home-Assistant-Area/Room, pro Raum ein-/ausklappbar.
- Read-only-Anzeige von Sensoren (Temperatur, Feuchtigkeit, Luftdruck), auf eine Nachkommastelle gerundet.
- Lokaler Hintergrund-Poll (alle 10 Minuten) mit Benachrichtigung bei Zustandsänderung einer beobachteten Entity.
- Bestätigt funktionierend, Ende-zu-Ende, gegen eine echte, grosse (1500+ Entities) Home-Assistant-Instanz — sowohl im SailfishOS-SDK-Emulator als auch auf einem echten aarch64-Gerät.

Noch nicht umgesetzt: WebSocket-Live-Updates, Lockscreen-Widget, Remote-Zugriff (ausserhalb des lokalen Netzes).

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
