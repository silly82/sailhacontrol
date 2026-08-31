Name:       harbour-hacontrol

Summary:    Home-Assistant-Steuerung für SailfishOS (Prototyp)
Version:    0.7
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
Entity-Liste (Lights/Switches) mit Toggle, nach Raum gruppiert und ein-/
ausklappbar, inkl. Temperatur-/Feuchte-/Luftdruck-Sensoren. Live-Updates
per WebSocket, erweiterte Lichtsteuerung (Helligkeit/Farbe/Farbtemperatur)
per Tap auf den Namen. Periodischer Background-Poll (BackgroundJob) mit
lokaler Benachrichtigung bei Zustandsänderung beobachteter Entities --
die Benachrichtigung hat einen Umschalten-Button, direkt vom
Sperrbildschirm aus bedienbar.


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
* Mon Aug 31 2026 silly82 <noreply@example.org> - 0.7-1
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
