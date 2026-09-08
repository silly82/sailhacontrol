Name:       harbour-hacontrol

Summary:    Home-Assistant-Steuerung für SailfishOS (Prototyp)
Version:    0.10
Release:    1
License:    MIT
URL:        https://github.com/silly82/sailhacontrol
Source0:    %{name}-%{version}.tar.bz2
Requires:   sailfishsilica-qt5 >= 0.10.9
Requires:   nemo-qml-plugin-notifications-qt5
Requires:   libkeepalive
Requires:   qt5-qtdeclarative-import-websockets
Requires:   qt5-qtwebsockets
Requires:   nemo-qml-plugin-dbus-qt5
BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  desktop-file-utils

%description
Native SailfishOS-App zur Steuerung einer lokalen Home-Assistant-Instanz.
Entity-Liste (Lights/Switches/Fans/Covers) mit Toggle, Media Player mit
Play/Pause/Lautstärke, Szenen zum Aktivieren, nach Raum gruppiert und
ein-/ausklappbar, inkl. Temperatur-/Feuchte-/Luftdruck-/Batterie-/
Energie-/Leistungs-Sensoren. Raumübergreifende Übersicht anstehender
Geräte-Updates mit Installieren-Button. Live-Updates per WebSocket,
erweiterte Lichtsteuerung (Helligkeit/Farbe/Farbtemperatur) per Tap auf
den Namen, Thermostat-Steuerung (Zieltemperatur/Modus). Periodischer
Background-Poll (BackgroundJob) mit lokaler Benachrichtigung bei
Zustandsänderung beobachteter Entities -- die Benachrichtigung hat einen
Umschalten-Button, direkt vom Sperrbildschirm aus bedienbar.


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
