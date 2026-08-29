Name:       harbour-hacontrol

Summary:    Home-Assistant-Steuerung für SailfishOS (Prototyp)
Version:    0.4
Release:    1
License:    MIT
URL:        https://github.com/silly82/sailhacontrol
Source0:    %{name}-%{version}.tar.bz2
Requires:   sailfishsilica-qt5 >= 0.10.9
Requires:   nemo-qml-plugin-notifications-qt5
Requires:   libkeepalive
Requires:   qt5-qtdeclarative-import-websockets
Requires:   qt5-qtwebsockets
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
lokaler Benachrichtigung bei Zustandsänderung beobachteter Entities.


%prep
%setup -q -n %{name}-%{version}

%build

%qmake5

%make_build


%install
%qmake5_install


desktop-file-install --delete-original       \
  --dir %{buildroot}%{_datadir}/applications             \
   %{buildroot}%{_datadir}/applications/*.desktop

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png
