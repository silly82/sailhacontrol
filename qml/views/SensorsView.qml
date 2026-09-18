import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import "../lib/HaApi.js" as HaApi
import "../components"

// One of two swipeable sub-views of FirstPage.qml (the other is
// RoomsView.qml) -- Temperatur-/Feuchte-/Luftdruck-/Batterie-/Energie-/
// Leistungs-Sensoren, gruppiert nach Raum (gleiches Muster wie
// RoomsView.qml), pro Raum ein-/ausklappbar. "Nur aktive" -- Sensoren mit
// nicht-numerischem state (unavailable/unknown/...) werden ausgeblendet,
// davon hat eine grössere HA-Instanz oft etliche.
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
    readonly property string noRoomLabel: qsTr("Ohne Raum")
    // room name -> bool. Missing key == collapsed (rooms start folded) --
    // gleiches Muster wie RoomsView.qml, hier separat gehalten statt
    // geteilt (jede Sub-View verwaltet ihren eigenen Auf-/Zu-Zustand).
    property var expandedRooms: ({})

    readonly property var sensorDeviceClasses: ["temperature", "humidity", "pressure", "atmospheric_pressure", "battery", "energy", "power"]

    ListModel {
        id: entriesModel
    }

    function formatValue(value, unit) {
        var num = parseFloat(value)
        var text = isNaN(num) ? value : num.toFixed(1)
        return text + (unit ? (" " + unit) : "")
    }

    function toggleRoom(room) {
        var next = {}
        for (var key in expandedRooms) {
            next[key] = expandedRooms[key]
        }
        next[room] = !next[room]
        expandedRooms = next
    }

    function buildEntries(states, areaPairs) {
        var areaMap = {}
        for (var i = 0; i < areaPairs.length; i++) {
            areaMap[areaPairs[i][0]] = areaPairs[i][1]
        }

        var rooms = {}
        for (var j = 0; j < states.length; j++) {
            var st = states[j]
            if (st.entity_id.split(".")[0] !== "sensor") {
                continue
            }
            if (sensorDeviceClasses.indexOf(st.attributes.device_class) < 0) {
                continue
            }
            var num = parseFloat(st.state)
            if (isNaN(num)) {
                // "nur aktive" -- unavailable/unknown/etc. ausblenden.
                continue
            }
            var room = areaMap[st.entity_id] || noRoomLabel
            if (!rooms[room]) {
                rooms[room] = []
            }
            rooms[room].push({
                friendlyName: st.attributes.friendly_name || st.entity_id,
                value: st.state,
                unit: st.attributes.unit_of_measurement || ""
            })
        }

        var roomNames = Object.keys(rooms).sort(function (a, b) {
            if (a === noRoomLabel) return 1
            if (b === noRoomLabel) return -1
            return a.localeCompare(b)
        })

        entriesModel.clear()
        for (var k = 0; k < roomNames.length; k++) {
            var roomName = roomNames[k]
            var matches = rooms[roomName]
            matches.sort(function (a, b) { return a.friendlyName.localeCompare(b.friendlyName) })

            entriesModel.append({ rowType: "header", room: roomName, count: matches.length, friendlyName: "", value: "", unit: "" })
            for (var m = 0; m < matches.length; m++) {
                var e = matches[m]
                e.rowType = "entity"
                e.room = roomName
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
                HaApi.getAreaMap(baseUrlSetting.value, tokenSetting.value,
                    function (areaPairs) {
                        busyIndicator.running = false
                        buildEntries(states, areaPairs)
                    },
                    function (error) {
                        // Area-Zuordnung ist ein Komfort-Feature, kein Muss --
                        // bei Fehlschlag landet einfach alles unter "Ohne
                        // Raum" statt die Seite zu blockieren.
                        busyIndicator.running = false
                        buildEntries(states, [])
                    })
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
            readonly property bool rowVisible: isHeader || expandedRooms[model.room] === true
            contentHeight: rowVisible ? (isHeader ? Theme.itemSizeExtraSmall : Theme.itemSizeMedium) : 0
            visible: rowVisible
            clip: true

            onClicked: {
                if (isHeader) {
                    toggleRoom(model.room)
                }
            }

            Row {
                visible: delegateItem.isHeader
                anchors.left: parent.left
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.paddingSmall

                Label {
                    text: expandedRooms[model.room] === true ? "▾" : "▸"
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeMedium
                }
                Label {
                    text: model.room + " (" + model.count + ")"
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeMedium
                }
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
