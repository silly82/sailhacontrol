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

SOURCES += src/harbour-hacontrol.cpp

DISTFILES += qml/harbour-hacontrol.qml \
    qml/cover/CoverPage.qml \
    qml/components/ScrollingLabel.qml \
    qml/lib/HaApi.js \
    qml/pages/FirstPage.qml \
    qml/pages/SettingsPage.qml \
    rpm/harbour-hacontrol.spec \
    harbour-hacontrol.desktop

# TODO: no app icon yet -- add icons/<size>/harbour-hacontrol.png for each
# size below before packaging (see KONZEPT.md).
SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172

# to disable building translations every time, comment out the
# following CONFIG line
CONFIG += sailfishapp_i18n

# German translation is enabled as an example. If you aren't
# planning to localize your app, remember to comment out the
# following TRANSLATIONS line. And also do not forget to
# modify the localized app name in the the .desktop file.
TRANSLATIONS += translations/harbour-hacontrol-de.ts
