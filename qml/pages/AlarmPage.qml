import QtQuick 2.0
import Sailfish.Silica 1.0
import "../lib/HaApi.js" as HaApi

// Alarmanlage (alarm_control_panel), geöffnet per Tap in RoomsView.qml.
// Zeigt den Zustand gross an und bietet die Scharf-Modi, die das Panel laut
// supported_features kann, plus Unscharf.
//
// Code/PIN: verlangt das Panel einen Code (code_format "number" oder
// "text"), gibt es ein Eingabefeld -- Ziffernblock bzw. Passwortfeld. Der
// Code lebt nur in enteredCode, geht ausschliesslich als "code" in die
// Service-Daten (nie in console.log, nie in ConfigurationValue) und wird
// nach jedem Aufruf sowie beim Verlassen der Seite gelöscht.
Page {
    id: page

    allowedOrientations: Orientation.All

    property string entityId
    property string entityName
    property string entityState: ""
    property var attributes: ({})
    // RoomsView.qml (liveStateReceived), wie bei CoverDetailPage.qml. Darf
    // null sein (dann ohne Live-Update).
    property var stateSource: null

    // AlarmControlPanelEntityFeature: ARM_HOME = 1, ARM_AWAY = 2,
    // ARM_NIGHT = 4, TRIGGER = 8, ARM_CUSTOM_BYPASS = 16, ARM_VACATION = 32.
    // Fehlt supported_features ganz: Home + Away als die üblichen Modi.
    readonly property bool hasFeatureInfo: attributes.supported_features !== undefined && attributes.supported_features !== null
    readonly property int alarmFeatures: hasFeatureInfo ? attributes.supported_features : 3
    readonly property bool supportsArmHome: (alarmFeatures & 1) !== 0
    readonly property bool supportsArmAway: (alarmFeatures & 2) !== 0
    readonly property bool supportsArmNight: (alarmFeatures & 4) !== 0
    readonly property bool supportsTrigger: (alarmFeatures & 8) !== 0
    readonly property bool supportsArmCustomBypass: (alarmFeatures & 16) !== 0
    readonly property bool supportsArmVacation: (alarmFeatures & 32) !== 0

    // code_format: "number" | "text" | null. code_arm_required fehlt bei
    // manchen Integrationen -- HAs Default ist true.
    readonly property string codeFormat: attributes.code_format === "number" || attributes.code_format === "text" ? attributes.code_format : ""
    readonly property bool codeRequired: codeFormat.length > 0
    readonly property bool codeArmRequired: codeRequired && attributes.code_arm_required !== false
    readonly property bool isDisarmed: entityState === "disarmed"

    property string enteredCode: ""
    property string errorText: ""

    function alarmStateLabel(state) {
        switch (state) {
        case "disarmed": return qsTr("Disarmed")
        case "armed_home": return qsTr("Armed home")
        case "armed_away": return qsTr("Armed away")
        case "armed_night": return qsTr("Armed night")
        case "armed_vacation": return qsTr("Armed vacation")
        case "armed_custom_bypass": return qsTr("Armed custom bypass")
        case "arming": return qsTr("Arming")
        case "disarming": return qsTr("Disarming")
        case "pending": return qsTr("Pending")
        case "triggered": return qsTr("Triggered")
        case "unavailable": return qsTr("Unavailable")
        default: return state
        }
    }

    function clearCode() {
        enteredCode = ""
        codeField.text = ""
    }

    // needsCode: der Aufruf darf ohne Code gar nicht erst raus (HA würde
    // ihn ablehnen) -- stattdessen Hinweis. Ein eingegebener Code geht auch
    // bei nicht verlangtem Code mit; HA ignoriert ihn dann.
    function callAlarm(service, needsCode) {
        errorText = ""
        if (needsCode && enteredCode.length === 0) {
            errorText = qsTr("Enter the code first.")
            return
        }
        var serviceData = { entity_id: entityId }
        if (enteredCode.length > 0) {
            serviceData.code = enteredCode
        }
        clearCode()
        HaApi.callService(Credentials.baseUrl, Credentials.token, "alarm_control_panel", service, serviceData,
            function () {},
            function (error) {
                // Nur der Hinweis (HTTP-Status), nicht error.detail -- der
                // Antworttext gehört nicht in die Oberfläche.
                errorText = error.hint || qsTr("Unknown error")
            })
    }

    function disarm() {
        if (codeRequired) {
            // Der Code ist schon die Bestätigung.
            callAlarm("alarm_disarm", true)
        } else {
            remorse.execute(qsTr("Disarming"), function () { callAlarm("alarm_disarm", false) })
        }
    }

    onStatusChanged: {
        if (status === PageStatus.Deactivating || status === PageStatus.Inactive) {
            clearCode()
        }
    }

    Connections {
        target: stateSource
        onLiveStateReceived: {
            if (changedEntityId !== page.entityId || !newState) {
                return
            }
            page.entityState = newState.state || ""
            page.attributes = newState.attributes || {}
        }
    }

    RemorsePopup {
        id: remorse
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        VerticalScrollDecorator {}

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: entityName
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: alarmStateLabel(entityState)
                font.pixelSize: Theme.fontSizeExtraLarge
                color: entityState === "triggered" ? Theme.errorColor
                    : (isDisarmed ? Theme.secondaryHighlightColor : Theme.highlightColor)
            }

            Label {
                visible: attributes.changed_by !== undefined && attributes.changed_by !== null && String(attributes.changed_by).length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("Changed by %1").arg(attributes.changed_by)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
            }

            Label {
                visible: errorText.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: errorText
                color: Theme.errorColor
            }

            // -- Code entry --
            // "text": Passwortfeld (keine Vorschläge, kein Lernen).
            PasswordField {
                id: codeField
                visible: codeFormat === "text"
                width: parent.width
                label: qsTr("Code")
                placeholderText: qsTr("Code")
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                onTextChanged: page.enteredCode = text
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            // "number": maskierte Anzeige + Ziffernblock.
            Item {
                visible: codeFormat === "number"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: Math.max(pinDisplay.height, clearButton.height)

                Label {
                    id: pinDisplay
                    anchors.left: parent.left
                    anchors.right: clearButton.left
                    anchors.rightMargin: Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Theme.fontSizeLarge
                    color: enteredCode.length > 0 ? Theme.highlightColor : Theme.secondaryColor
                    text: enteredCode.length > 0 ? new Array(enteredCode.length + 1).join("●") : qsTr("Enter code")
                }
                Button {
                    id: clearButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: enteredCode.length > 0
                    text: qsTr("Clear")
                    onClicked: page.enteredCode = ""
                }
            }

            Keypad {
                visible: codeFormat === "number"
                width: parent.width
                symbolsVisible: false
                vanityDialNumbersVisible: false
                onClicked: {
                    if (enteredCode.length < 16) {
                        page.enteredCode += number
                    }
                }
            }

            // -- Actions --
            SectionHeader {
                text: qsTr("Arm")
                visible: supportsArmHome || supportsArmAway || supportsArmNight || supportsArmVacation || supportsArmCustomBypass
            }

            Flow {
                id: armFlow
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingMedium
                readonly property real buttonWidth: (width - spacing) / 2

                Button {
                    visible: supportsArmHome
                    width: armFlow.buttonWidth
                    text: qsTr("Home", "alarm arm mode")
                    onClicked: callAlarm("alarm_arm_home", codeArmRequired)
                }
                Button {
                    visible: supportsArmAway
                    width: armFlow.buttonWidth
                    text: qsTr("Away", "alarm arm mode")
                    onClicked: callAlarm("alarm_arm_away", codeArmRequired)
                }
                Button {
                    visible: supportsArmNight
                    width: armFlow.buttonWidth
                    text: qsTr("Night", "alarm arm mode")
                    onClicked: callAlarm("alarm_arm_night", codeArmRequired)
                }
                Button {
                    visible: supportsArmVacation
                    width: armFlow.buttonWidth
                    text: qsTr("Vacation", "alarm arm mode")
                    onClicked: callAlarm("alarm_arm_vacation", codeArmRequired)
                }
                Button {
                    visible: supportsArmCustomBypass
                    width: armFlow.buttonWidth
                    text: qsTr("Custom bypass", "alarm arm mode")
                    onClicked: callAlarm("alarm_arm_custom_bypass", codeArmRequired)
                }
            }

            SectionHeader {
                text: qsTr("Disarm")
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Disarm")
                // Auch bei "disarmed" bedienbar -- falls die Live-Anzeige
                // hinterherhinkt, soll Unscharf nie blockiert sein.
                preferredWidth: Theme.buttonWidthLarge
                onClicked: disarm()
            }

            // Löst die Sirene aus -- nur mit Remorse-Frist, und nur wenn das
            // Panel TRIGGER unterstützt.
            Button {
                visible: supportsTrigger
                anchors.horizontalCenter: parent.horizontalCenter
                preferredWidth: Theme.buttonWidthLarge
                text: qsTr("Trigger alarm")
                onClicked: remorse.execute(qsTr("Triggering alarm"), function () { callAlarm("alarm_trigger", false) })
            }
        }
    }
}
