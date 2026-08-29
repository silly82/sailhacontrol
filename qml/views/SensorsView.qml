import QtQuick 2.0
import Sailfish.Silica 1.0
import org.nemomobile.configuration 1.0
import "../lib/HaApi.js" as HaApi
import "../components"

// One of two swipeable sub-views of FirstPage.qml (the other is
// RoomsView.qml) -- cross-room overview of Temperatur-/Feuchte-/Luftdruck-
// Sensoren, gruppiert nach Messgrösse statt nach Raum. "Nur aktive" --
// Sensoren mit nicht-numerischem state (unavailable/unknown/...) werden
// ausgeblendet, davon hat eine grössere HA-Instanz oft etliche.
Item {
    id: root

    ConfigurationValue {
        id: baseUrlSetting
        key: "/apps/harbour-hacontrol/baseUrl"
        defaultValue: ""
    }
    ConfigurationValue {
        id: tokenSetting
        key: "/apps/harbour-hacontrol/token"
        defaultValue: ""
    }

    property string errorText: ""

    readonly property var sections: [
        { label: qsTr("Temperatur"), classes: ["temperature"] },
        { label: qsTr("Luftfeuchtigkeit"), classes: ["humidity"] },
        { label: qsTr("Luftdruck"), classes: ["pressure", "atmospheric_pressure"] }
    ]

    ListModel {
        id: entriesModel
    }

    function formatValue(value, unit) {
        var num = parseFloat(value)
        var text = isNaN(num) ? value : num.toFixed(1)
        return text + (unit ? (" " + unit) : "")
    }

    function buildEntries(states) {
        entriesModel.clear()
        for (var s = 0; s < sections.length; s++) {
            var section = sections[s]
            var matches = []
            for (var i = 0; i < states.length; i++) {
                var st = states[i]
                if (st.entity_id.split(".")[0] !== "sensor") {
                    continue
                }
                if (section.classes.indexOf(st.attributes.device_class) < 0) {
                    continue
                }
                var num = parseFloat(st.state)
                if (isNaN(num)) {
                    // "nur aktive" -- unavailable/unknown/etc. ausblenden.
                    continue
                }
                matches.push({
                    friendlyName: st.attributes.friendly_name || st.entity_id,
                    value: st.state,
                    unit: st.attributes.unit_of_measurement || ""
                })
            }
            matches.sort(function (a, b) { return a.friendlyName.localeCompare(b.friendlyName) })

            entriesModel.append({ rowType: "header", label: section.label, count: matches.length, friendlyName: "", value: "", unit: "" })
            for (var m = 0; m < matches.length; m++) {
                var e = matches[m]
                e.rowType = "entity"
                e.label = ""
                e.count = 0
                entriesModel.append(e)
            }
        }
    }

    function refresh() {
        if (baseUrlSetting.value.length === 0 || tokenSetting.value.length === 0) {
            errorText = qsTr("Noch nicht konfiguriert -- unter Settings die Home-Assistant-URL und einen Long-Lived Access Token eintragen.")
            return
        }
        errorText = ""
        busyIndicator.running = true
        HaApi.getStates(baseUrlSetting.value, tokenSetting.value,
            function (states) {
                busyIndicator.running = false
                buildEntries(states)
            },
            function (error) {
                busyIndicator.running = false
                errorText = error.hint || qsTr("Unbekannter Fehler")
            })
    }

    Component.onCompleted: refresh()

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: entriesModel

        header: Column {
            width: listView.width

            PullDownMenu {
                MenuItem {
                    text: qsTr("Settings")
                    onClicked: pageStack.push(Qt.resolvedUrl("../pages/SettingsPage.qml"))
                }
                MenuItem {
                    text: qsTr("Refresh")
                    onClicked: refresh()
                }
            }

            PageHeader {
                title: qsTr("Sensor-Übersicht")
            }

            Label {
                visible: errorText.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: errorText
                color: errorText.indexOf(qsTr("Noch nicht konfiguriert")) === 0 ? Theme.secondaryHighlightColor : Theme.errorColor
            }
        }

        delegate: ListItem {
            id: delegateItem
            width: listView.width
            readonly property bool isHeader: model.rowType === "header"
            contentHeight: isHeader ? Theme.itemSizeExtraSmall : Theme.itemSizeMedium

            Label {
                visible: delegateItem.isHeader
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: model.label + " (" + model.count + ")"
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeMedium
            }

            ScrollingLabel {
                visible: !delegateItem.isHeader
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin - valueLabel.width - Theme.paddingSmall
                anchors.verticalCenter: parent.verticalCenter
                text: model.friendlyName || ""
            }
            Label {
                id: valueLabel
                visible: !delegateItem.isHeader
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: formatValue(model.value, model.unit)
                color: Theme.secondaryHighlightColor
            }
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        id: busyIndicator
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: false
    }
}
