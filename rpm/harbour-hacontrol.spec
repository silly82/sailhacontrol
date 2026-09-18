Name:       harbour-hacontrol

Summary:    Home-Assistant-Steuerung für SailfishOS (Prototyp)
Version:    0.51
Release:    2
License:    MIT
URL:        https://github.com/silly82/sailhacontrol
Source0:    %{name}-%{version}.tar.bz2
Requires:   sailfishsilica-qt5 >= 0.10.9
Requires:   nemo-qml-plugin-notifications-qt5
Requires:   libkeepalive
Requires:   qt5-qtdeclarative-import-websockets
Requires:   qt5-qtwebsockets
Requires:   nemo-qml-plugin-dbus-qt5
# libsailfishsecrets (the C++ API used by src/credentials.{h,cpp}) is *not*
# listed here on purpose: Harbour's validator rejects the plain package name
# ("Dependency not allowed"), while the automatic soname dependency rpmbuild
# derives from the linked binary (libsailfishsecrets.so.0, which is on
# Harbour's allowed APIs list) passes. Hand-writing the soname instead was what
# broke pkcon installation back in v0.7 for libkeepalive, so let it stay
# auto-generated.
BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(sailfishsecrets)
BuildRequires:  desktop-file-utils

%description
Native SailfishOS-App zur Steuerung einer lokalen Home-Assistant-Instanz.
Entity-Liste (Lights/Switches/Fans/Covers) mit Toggle -- Lichter mit
bekannter Farbe zeigen einen Farb-Punkt --, Media Player mit
Play/Pause/Lautstärke, Szenen zum Aktivieren, nach Raum gruppiert und
ein-/ausklappbar, inkl. Temperatur-/Feuchte-/Luftdruck-/Batterie-/
Energie-/Leistungs-Sensoren. Raumübergreifende Übersicht anstehender
Geräte-Updates mit Installieren-Button und Fortschrittsbalken während
der Installation. Live-Updates per WebSocket, erweiterte Lichtsteuerung
(Helligkeit/Farbe/Farbtemperatur) per Tap auf den Namen,
Thermostat-Steuerung (Zieltemperatur/Modus). Periodischer
Background-Poll (BackgroundJob) mit lokaler Benachrichtigung bei
Zustandsänderung beobachteter Entities -- die Benachrichtigung hat einen
Umschalten-Button, direkt vom Sperrbildschirm aus bedienbar. Echte
mobile_app-Integration: Push-Benachrichtigungen aus HA-Automationen
(notify.mobile_app_...) per WebSocket, sowie drei Device-Status-Sensoren
(Akkustand, Lädt, Verbindungsart) zurück an HA. HA-URL und
Long-Lived Access Token liegen verschlüsselt in Sailfish Secrets
(Sailjail-Berechtigung Secrets) statt im Klartext in dconf.


%prep
%autosetup -n %{name}-%{version}

%build

%qmake5

%make_build


%install
%qmake5_install

# sfdk's dev-oriented qmake invocation sets QMAKE_STRIP=: (a no-op), so the
# usual automatic strip never runs -- strip explicitly instead of relying on
# it, otherwise Harbour's rpmlint check flags an unstripped-binary warning.
%{__strip} %{buildroot}%{_bindir}/%{name}

desktop-file-install --delete-original       \
  --dir %{buildroot}%{_datadir}/applications             \
   %{buildroot}%{_datadir}/applications/*.desktop

%files
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png

%changelog
* Fri Sep 18 2026 silly82 <siliwalker@gmail.com> - 0.51-2
- Pull-down-"Refresh" aktualisiert jetzt alle drei Sub-Views statt nur der
  sichtbaren: die drei Views liegen gleichzeitig nebeneinander in einer Row
  und laden ihre Daten selbst, ein Refresh nur der aktiven Seite liess die
  anderen mit veralteten Daten zurück (jede View bittet die Seite per Signal
  um einen Refresh aller drei).
- Geräte-Status-Sensoren (Akkustand/Lädt/Verbindungsart) werden zusätzlich
  bei jedem App-Start und bei jedem Pull-down-Refresh an HA gemeldet. Auf
  dem Gerät verifiziert: der 10-Minuten-BackgroundJob feuert nicht, solange
  die App im Vordergrund ist -- in HA standen die Sensoren deshalb stundenlang
  still, obwohl die App lief.

* Fri Sep 18 2026 silly82 <siliwalker@gmail.com> - 0.51-1
- HA-URL und Long-Lived Access Token liegen nicht mehr im Klartext
  (Nemo.Configuration/dconf), sondern verschlüsselt in Sailfish Secrets.
  Neu: src/credentials.{h,cpp} -- ein C++-Credentials-Objekt, das die
  Secrets-Requests kapselt und per Context-Property als "Credentials" in
  QML sichtbar ist (gleiche API wie zuvor: baseUrl/token/loaded/save()).
  Grund für C++: die QML-Variante konnte beide nötigen Requests nicht
  abbilden. StoredSecretRequest.identifier ist vom Typ
  Secret::Identifier, einer einfachen C++-Klasse ohne Q_GADGET, die das
  QML-Plugin nie registriert (JS-Objektliteral und Gruppenschreibweise
  scheitern beide: "Cannot assign QJSValue to
  Sailfish::Secrets::Secret::Identifier"), und
  StoreSecretRequest.secretStorageType ist ein Enum ohne Q_ENUM
  ("Cannot assign int to an unregistered type", auch imperativ aus JS).
  Beides auf echter Hardware im Journal verifiziert -- Speichern UND
  Lesen waren so nicht möglich, die App war nur im RAM konfiguriert.
- Einmalige Migration: vorhandene Klartextwerte werden beim ersten Start
  automatisch nach Secrets übernommen, danach werden die dconf-Kopien
  geleert (kein Neueintippen nötig).
- SettingsPage: schreibt bei Fokusverlust bzw. beim Verlassen der Seite
  statt bei jedem Tastendruck, und nur wenn beide Felder vollständig
  sind und sich geändert haben; zeigt Fehler des Secrets-Daemons an.
- Spec: Requires: libsailfishsecrets (ersetzt libsailfishsecretsplugin,
  das nur den QML-Import bediente), BuildRequires:
  pkgconfig(sailfishsecrets).

* Fri Sep 18 2026 silly82 <siliwalker@gmail.com> - 0.50-1
- SensorsView.qml: raumbasierte Gruppierung statt Gruppierung nach
  Messgrösse (Temperatur/Batterie/...), ein-/ausklappbar pro Raum --
  gleiches Muster wie RoomsView.qml (getAreaMap(), expandedRooms,
  toggleRoom()). Räume starten eingeklappt; ein Raum kann gemischte
  Sensor-Typen enthalten (z.B. Temperatur+Energie+Luftdruck im selben
  Raum), das Format (Wert+Einheit) bleibt unverändert. Visuell auf dem
  Emulator verifiziert (Swipe-Simulation war diese Session unzuverlässig
  -- stattdessen kurzzeitig FirstPage.qml auf contentX = page.width
  gesetzt, verifiziert, wieder entfernt, statt blind zu vertrauen).
- RoomsView.qml: PageHeader-Titel "HA Control" (App-Name) durch "Räume"
  ersetzt -- war die einzige der drei Sub-Views ohne eigenen Seitentitel
  (Sensor-Übersicht/Updates hatten schon einen), auf Nutzerrückfrage
  ("hat jede Seite ein Titel...?") aufgefallen.
- Versionssprung auf 0.50 (statt fortlaufend 0.13) auf expliziten
  Nutzerwunsch nach Rückfrage.

* Fri Sep 18 2026 silly82 <siliwalker@gmail.com> - 0.12-1
- Real mobile_app integration, nachgebaut aus der offiziellen HA-Companion-App:
  Registrierung (POST /api/mobile_app/registrations) mit
  app_data.push_websocket_channel, wodurch HA einen echten
  notify.mobile_app_<gerät>-Service anbietet, der über die bereits
  bestehende WebSocket-Verbindung zugestellt wird (kein eigener HTTP-Server,
  kein C++ nötig -- Mechanik verifiziert direkt im home-assistant/core-
  Quellcode statt geraten). Ausserdem drei Device-Status-Sensoren
  (Akkustand, Lädt, Verbindungsart) via register_sensor/
  update_sensor_states, gelesen über com.nokia.mce (Akku/Ladezustand) und
  net.connman (Verbindungsart) per Nemo.DBus -- Dienst-/Pfadnamen gegen die
  laufende Instanz verifiziert (SailfishOS nutzt kein UPower). Sensor-Update
  huckepack auf dem bestehenden 10-Minuten-BackgroundJob. Neues
  "Gerätename"-Feld + "Gerät neu registrieren"-Button in den Settings.
- Echter Bug gefunden+gefixt beim Testen gegen die reale Instanz: HAs
  Registrierungs-API dokumentiert/schemaisiert os_version als optional,
  aber mobile_app's async_setup_entry() liest es intern ohne Fallback --
  fehlt es, crasht das Setup NACH dem Erzeugen der webhook_id, aber VOR
  ihrer eigentlichen Registrierung. Das REST-Ergebnis sieht dabei
  trotzdem nach Erfolg aus (webhook_id kommt zurück) -- jeder folgende
  Aufruf gegen diese webhook_id landet aber für immer auf HAs
  Leer-200-Antwort für unbekannte Webhooks. Fix: os_version immer
  mitschicken. Zweiter, kleinerer Bug: der Push-Kanal wurde nur im
  WebSocket-auth_ok-Handler abonniert, die Registrierung (asynchroner
  REST-Call) war zu dem Zeitpunkt oft noch nicht fertig -- Push blieb
  für den Rest der Verbindung unbeobachtet. Fix: zusätzlicher Versuch,
  sobald die webhookId nachträglich gesetzt wird.

* Tue Sep 08 2026 silly82 <siliwalker@gmail.com> - 0.11-1
- UI polish: color swatch next to light rows (real rgb_color, or a
  Tanner-Helland approximation from color_temp_kelvin when only that
  is available; hidden while the light is off, since HA reports both
  attributes as null then). Progress bar replacing the version line
  on updates that are actively installing -- percentage-filled if the
  device reports update_percentage, an animated indeterminate bar
  otherwise; a new 3s poll timer keeps it live while any install is
  in progress. Both features reuse attributes already being fetched,
  no new API calls. Took three height/thickness iterations on the
  progress bar to stop looking like a stray underline under the name.

* Tue Sep 08 2026 silly82 <siliwalker@gmail.com> - 0.10-1
- Add a third swipeable sub-view, UpdatesView.qml, listing update-domain
  entities with a pending update (state == "on") -- name, installed ->
  latest version, and a tap-to-install action (update.install), same
  tap-to-act pattern as v0.9's scene rows. Not grouped by room (updates
  aren't naturally room-scoped) and filtered to only pending updates,
  since most update entities are idle most of the time (107 in the
  real instance, typically only a handful pending). FirstPage.qml's
  swipe-snap logic was hardcoded for exactly two pages -- generalized
  to round-to-nearest-page-width, clamped to the content range, so it
  keeps snapping cleanly with a third (and future) sub-view.

* Mon Sep 07 2026 silly82 <siliwalker@gmail.com> - 0.9-1
- Expand domain coverage: fan/cover joined the existing toggle rows
  (generic <domain>.toggle service; cover's "on"-equivalent state is
  "open", not "on" -- handled via a new isEntityOn() helper). New
  media_player kind with a submenu (play/pause/prev/next, volume slider
  shown only if volume_level is present). New scene kind with no
  switch -- scenes have no on/off state (state is the last-activation
  timestamp) and no toggle service, only scene.turn_on -- tap the row
  to activate directly. Sensor device classes extended with
  battery/energy/power (matching SensorsView.qml sections). Based on a
  device_class/domain gap analysis against a real 1517-entity instance;
  user explicitly asked for full coverage with no artificial per-
  category limit, since an automatic "top 5" selection isn't well-
  defined for e.g. battery sensors.

* Mon Sep 07 2026 silly82 <siliwalker@gmail.com> - 0.8-1
- Add thermostat control (climate domain): tap a thermostat's name to
  open target-temperature slider + HVAC mode selection, same submenu
  pattern as lights. Bug found+fixed during testing: ListModel's
  "value" role is type-locked by its first-seen type (string, from
  toggle/sensor rows) -- assigning a Number for climate rows silently
  produced "Can't assign to existing role" warnings, fixed by always
  storing it as a String. Second bug: read hvac_mode from
  attributes.state, but HA's "state" is a sibling field of attributes,
  not inside it -- mode selector showed blank until fixed via a
  separate hvacMode field threaded through from RoomsView.

* Mon Aug 31 2026 silly82 <siliwalker@gmail.com> - 0.7-1
- Harbour submission prep: migrate deprecated org.nemomobile.* QML
  imports to Nemo.*, bump Nemo.KeepAlive to the allowed 1.2, strip the
  binary explicitly (sfdk's dev qmake run sets QMAKE_STRIP=:, a no-op).
  Tried Requires: libkeepalive.so.1 (soname form, per rpmlint's
  explicit-lib-dependency hint) but reverted it -- passed the local
  harbour/rpmlint checks either way, yet broke real installation on the
  phone ("nothing provides libkeepalive.so.1", zypper wants the
  ()(64bit)-qualified form there) -- plain package-name Requires stays.
  (Also tried %license under /usr/share/licenses -- Harbour's path
  whitelist rejects that location, so no separate license file is
  installed; the License: tag plus the repo's LICENSE file cover it.)
