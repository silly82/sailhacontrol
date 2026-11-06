# NOTICE:
#
# Application name defined in TARGET has a corresponding QML filename.
# If name defined in TARGET is changed, the following needs to be done
# to match new name:
#   - corresponding QML filename must be changed
#   - desktop icon filename must be changed
#   - desktop filename must be changed
#   - icon definition filename in desktop file must be changed
#   - translation filenames have to be changed

# The name of your application
TARGET = harbour-hacontrol

CONFIG += sailfishapp

# Needed for the Sailfish.Secrets C++ API (src/credentials.{h,cpp}) -- the QML
# plugin can't express what we need (see src/credentials.h), and the C++ API
# uses Q_ENUM values, so it also wants C++11 lambdas in the request handlers.
CONFIG += link_pkgconfig c++11
# sailfishapp listed again on purpose: sailfishapp's own .prf adds itself to
# PKGCONFIG, and the pkgconfig list must be complete whenever qmake evaluates
# it (with only "PKGCONFIG += sailfishsecrets" the sailfishapp libs silently
# dropped out of the link line: "undefined reference to
# SailfishApp::createView()").
PKGCONFIG += sailfishsecrets sailfishapp

# Reachability probe of the internal URL + network-change detection for the
# internal/external URL switch (src/credentials.cpp). Qt5Network is on the
# Harbour allowed-libraries list.
QT += network

SOURCES += src/harbour-hacontrol.cpp \
    src/credentials.cpp

HEADERS += \
    src/credentials.h

DISTFILES += qml/harbour-hacontrol.qml \
    qml/cover/CoverPage.qml \
    qml/components/ScrollingLabel.qml \
    qml/components/DeviceStatusProbe.qml \
    qml/lib/HaApi.js \
    qml/pages/FirstPage.qml \
    qml/pages/SettingsPage.qml \
    qml/pages/LightDetailPage.qml \
    qml/pages/ThermostatDetailPage.qml \
    qml/pages/MediaPlayerDetailPage.qml \
    qml/pages/CoverDetailPage.qml \
    qml/pages/CoverSettingsPage.qml \
    qml/pages/SensorHistoryPage.qml \
    qml/pages/TodoListsPage.qml \
    qml/pages/TodoListPage.qml \
    qml/views/RoomsView.qml \
    qml/views/SensorsView.qml \
    qml/views/UpdatesView.qml \
    rpm/harbour-hacontrol.spec \
    harbour-hacontrol.desktop

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172

# to disable building translations every time, comment out the
# following CONFIG line
CONFIG += sailfishapp_i18n

# Source strings are English. Every translations/harbour-hacontrol-<lang>.ts
# file is picked up automatically -- adding a language needs no change here.
# See TRANSLATING.md.
TRANSLATIONS += $$files(translations/harbour-hacontrol-*.ts)
