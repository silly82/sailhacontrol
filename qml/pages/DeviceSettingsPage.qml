import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

// Settings > Device & sensors (opened from SettingsPage.qml): the
// mobile_app registration of this phone with the active instance and the
// opt-in location reporting.
Page {
    id: page

    allowedOrientations: Orientation.All

    // Global, not per profile: one phone, one identity (see
    // harbour-hacontrol.qml).
    ConfigurationValue {
        id: deviceNameSetting
        key: "/apps/harbour-hacontrol/deviceName"
        defaultValue: qsTr("SailfishOS Phone")
    }
    // Cleared here to trigger harbour-hacontrol.qml's ensureMobileAppRegistered()
    // to re-run (it watches this value, see there) -- kept empty until a
    // registration actually succeeds.
    ConfigurationValue {
        id: webhookIdSetting
        key: Credentials.settingsPrefix + "webhookId"
        defaultValue: ""
    }
    // Same key as in harbour-hacontrol.qml (opt-in location reporting).
    ConfigurationValue {
        id: reportLocationSetting
        key: Credentials.settingsPrefix + "reportLocation"
        defaultValue: false
    }

    // Assigned once the field is complete rather than bound: a TextField
    // created with a non-empty text logs a Silica-internal width binding
    // loop (see ConnectionSettingsPage.qml).
    Component.onCompleted: deviceNameField.text = deviceNameSetting.value

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: page.width

            PageHeader {
                //: Settings: page with the mobile_app registration and location reporting
                title: qsTr("Device & sensors")
            }

            SectionHeader {
                text: qsTr("Home Assistant device registration")
            }

            TextField {
                id: deviceNameField
                width: parent.width
                label: qsTr("Device name")
                placeholderText: qsTr("SailfishOS Phone")
                description: webhookIdSetting.value.length > 0
                    ? qsTr("Registered as its own device in Home Assistant, with battery and connection sensors.")
                    : qsTr("Not registered yet. Tried automatically once URL and token are valid.")
                onTextChanged: deviceNameSetting.value = text
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Re-register device")
                onClicked: webhookIdSetting.value = ""
            }

            SectionHeader {
                //: Settings > Device & sensors: section with the location switch
                text: qsTr("Location")
            }

            TextSwitch {
                text: qsTr("Report location to Home Assistant")
                description: qsTr("Sends this phone's position as its device tracker: at app start, on refresh and every 10 minutes in the background. Turning it off doesn't delete positions already stored.")
                checked: reportLocationSetting.value === true
                onClicked: reportLocationSetting.value = checked
            }
        }

        VerticalScrollDecorator {}
    }
}
