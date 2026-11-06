import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

// Configures the app cover (opened from SettingsPage.qml): up to two
// CoverActions plus the optional weather line.
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
                title: qsTr("Cover")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("The app cover can have up to two buttons. Scenes and scripts are run, lights and switches are toggled.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Item { width: 1; height: Theme.paddingMedium }

            ValueButton {
                //: Cover settings: the first (left) cover action
                label: qsTr("First button")
                value: targetIdSetting.value.length === 0
                    ? qsTr("Last used light")
                    : (targetNameSetting.value || targetIdSetting.value)
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

            TextSwitch {
                text: qsTr("Show weather")
                description: qsTr("Current temperature and condition of the weather entity chosen in the sensor overview. Updated whenever the sensor overview refreshes.")
                checked: showWeatherSetting.value === true
                onClicked: showWeatherSetting.value = checked
            }
        }

        VerticalScrollDecorator {}
    }
}
