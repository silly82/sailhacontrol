import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

// Settings > Cover & weather (opened from SettingsPage.qml): up to two
// CoverActions, the weather entity (also used by SensorsView's weather card)
// and whether the cover shows it.
// Slot 1 (coverTarget*): empty id means "last used light" -- the v0.52
// behaviour, fed by RoomsView.qml's coverLastLightId. Slot 2
// (coverTarget2*): empty id means "no second button". Each slot opens
// EntityPickerPage.qml; CoverPage.qml triggers the stored entity directly
// (scene/script -> turn_on, light/switch -> toggle). Id, name and domain are
// stored together so the cover can show the name and pick its icon without
// asking HA (it never polls on its own).
Page {
    id: page

    allowedOrientations: Orientation.All

    readonly property var targetDomains: ["scene", "script", "light", "switch"]

    ConfigurationValue {
        id: targetIdSetting
        key: Credentials.settingsPrefix + "coverTargetId"
        defaultValue: ""
    }
    ConfigurationValue {
        id: targetNameSetting
        key: Credentials.settingsPrefix + "coverTargetName"
        defaultValue: ""
    }
    ConfigurationValue {
        id: targetDomainSetting
        key: Credentials.settingsPrefix + "coverTargetDomain"
        defaultValue: ""
    }
    ConfigurationValue {
        id: target2IdSetting
        key: Credentials.settingsPrefix + "coverTarget2Id"
        defaultValue: ""
    }
    ConfigurationValue {
        id: target2NameSetting
        key: Credentials.settingsPrefix + "coverTarget2Name"
        defaultValue: ""
    }
    ConfigurationValue {
        id: target2DomainSetting
        key: Credentials.settingsPrefix + "coverTarget2Domain"
        defaultValue: ""
    }
    // Written by SensorsView.qml, only shown on the cover when enabled here.
    ConfigurationValue {
        id: showWeatherSetting
        key: Credentials.settingsPrefix + "coverShowWeather"
        defaultValue: true
    }

    // Same keys as SensorsView's weather card -- dconf notifies the other
    // instance, so the card switches as soon as a new entity is picked here.
    ConfigurationValue {
        id: weatherEntitySetting
        key: Credentials.settingsPrefix + "weatherEntity"
        defaultValue: ""
    }
    ConfigurationValue {
        id: weatherEntityNameSetting
        key: Credentials.settingsPrefix + "weatherEntityName"
        defaultValue: ""
    }
    function openWeatherPicker() {
        var picker = pageStack.push(Qt.resolvedUrl("EntityPickerPage.qml"), {
            headerTitle: qsTr("Weather"),
            description: qsTr("Shown at the top of the sensor overview and on the app cover."),
            domains: ["weather"],
            defaultLabel: qsTr("Automatic"),
            defaultDescription: qsTr("The first weather entity Home Assistant reports"),
            currentId: weatherEntitySetting.value,
            searchPlaceholder: qsTr("Search weather entities"),
            noMatchesHint: qsTr("No weather entity matches the search."),
            nothingHint: qsTr("Home Assistant has no weather entities.")
        })
        picker.picked.connect(function (entityId, name) {
            weatherEntitySetting.value = entityId
            weatherEntityNameSetting.value = entityId.length > 0 ? name : ""
        })
    }

    function openPicker(slot) {
        var first = slot === 1
        var picker = pageStack.push(Qt.resolvedUrl("EntityPickerPage.qml"), {
            headerTitle: first ? qsTr("First button") : qsTr("Second button"),
            description: qsTr("Scenes and scripts are run, lights and switches are toggled."),
            domains: targetDomains,
            defaultLabel: first ? qsTr("Last used light") : qsTr("None"),
            defaultDescription: first
                ? qsTr("The light you last switched in the app (default)")
                : qsTr("Only one button on the cover (default)"),
            currentId: first ? targetIdSetting.value : target2IdSetting.value,
            searchPlaceholder: qsTr("Search scenes, scripts, lights, switches"),
            noMatchesHint: qsTr("No scene, script, light or switch matches the search."),
            nothingHint: qsTr("Home Assistant has no scenes, scripts, lights or switches.")
        })
        picker.picked.connect(function (entityId, name, domain) {
            if (first) {
                targetIdSetting.value = entityId
                targetNameSetting.value = name
                targetDomainSetting.value = domain
            } else {
                target2IdSetting.value = entityId
                target2NameSetting.value = name
                target2DomainSetting.value = domain
            }
        })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            PageHeader {
                //: Settings: page with the cover buttons and the weather entity
                title: qsTr("Cover & weather")
            }

            SectionHeader {
                text: qsTr("Cover")
            }

            ValueButton {
                //: Cover settings: the first (left) cover action
                label: qsTr("First button")
                value: targetIdSetting.value.length === 0
                    ? qsTr("Last used light")
                    : (targetNameSetting.value || targetIdSetting.value)
                description: qsTr("Scenes and scripts are run, lights and switches are toggled.")
                onClicked: page.openPicker(1)
            }

            ValueButton {
                //: Cover settings: the optional second (right) cover action
                label: qsTr("Second button")
                value: target2IdSetting.value.length === 0
                    ? qsTr("None")
                    : (target2NameSetting.value || target2IdSetting.value)
                description: qsTr("Shown to the right of the first one")
                onClicked: page.openPicker(2)
            }

            SectionHeader {
                text: qsTr("Weather")
            }

            ValueButton {
                label: qsTr("Weather")
                value: weatherEntitySetting.value.length === 0
                    ? qsTr("Automatic")
                    : (weatherEntityNameSetting.value.length > 0 ? weatherEntityNameSetting.value : weatherEntitySetting.value)
                description: qsTr("Shown at the top of the sensor overview and on the app cover.")
                onClicked: page.openWeatherPicker()
            }

            TextSwitch {
                text: qsTr("Show weather")
                //: Cover settings: description of the "Show weather" switch, below the weather entity selector
                description: qsTr("Shows temperature and condition of this weather entity on the cover.")
                checked: showWeatherSetting.value === true
                onClicked: showWeatherSetting.value = checked
            }
        }

        VerticalScrollDecorator {}
    }
}
