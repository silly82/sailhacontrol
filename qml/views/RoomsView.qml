import QtQuick 2.0
import Sailfish.Silica 1.0
import QtWebSockets 1.0
import org.nemomobile.configuration 1.0
import "../lib/HaApi.js" as HaApi
import "../components"

// One of two swipeable sub-views of FirstPage.qml (the other is
// SensorsView.qml) -- entity list grouped by room, collapsible.
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
    // Comma-separated entity_ids -- shared with the BackgroundJob poller
    // in harbour-hacontrol.qml (Ausbaustufe 3, Variante B).
    ConfigurationValue {
        id: watchedSetting
        key: "/apps/harbour-hacontrol/watchedEntities"
        defaultValue: ""
    }

    property bool configured: baseUrlSetting.value.length > 0 && tokenSetting.value.length > 0
    property string errorText: ""
    // true once HA has confirmed our WS auth + subscribe_events -- drives
    // the "Live"-Hinweis im PageHeader.
    property bool wsSubscribed: false
    property int wsMessageId: 1
    readonly property string noRoomLabel: qsTr("Ohne Raum")
    // room name -> bool. Missing key == collapsed (rooms start folded).
    property var expandedRooms: ({})

    readonly property var toggleDomains: ["light", "switch"]
    readonly property var sensorDeviceClasses: ["temperature", "humidity", "pressure", "atmospheric_pressure"]

    // Flat list, mixed row types: {rowType: "header", room, count} and
    // {rowType: "entity", room, kind: "toggle"|"sensor", ...}. Flat + a
    // per-row visible/height toggle (rather than nested ListModels) keeps
    // SilicaListView's virtualization working even with the couple hundred
    // sensor rows a larger HA instance can have.
    ListModel {
        id: entriesModel
    }

    function watchedIds() {
        return watchedSetting.value.split(",").map(function (s) { return s.trim() }).filter(function (s) { return s.length > 0 })
    }

    function toggleWatch(index) {
        var entry = entriesModel.get(index)
        var ids = watchedIds()
        var pos = ids.indexOf(entry.entityId)
        if (pos >= 0) {
            ids.splice(pos, 1)
        } else {
            ids.push(entry.entityId)
        }
        watchedSetting.value = ids.join(",")
        entriesModel.setProperty(index, "notify", pos < 0)
    }

    function formatSensorValue(value, unit) {
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

        var watched = watchedIds()
        var rooms = {}

        for (var j = 0; j < states.length; j++) {
            var s = states[j]
            var domain = s.entity_id.split(".")[0]
            var deviceClass = s.attributes.device_class
            var kind = null
            if (toggleDomains.indexOf(domain) >= 0) {
                kind = "toggle"
            } else if (domain === "sensor" && sensorDeviceClasses.indexOf(deviceClass) >= 0) {
                kind = "sensor"
            }
            if (!kind) {
                continue
            }

            var room = areaMap[s.entity_id] || noRoomLabel
            if (!rooms[room]) {
                rooms[room] = []
            }
            rooms[room].push({
                entityId: s.entity_id,
                domain: domain,
                kind: kind,
                friendlyName: s.attributes.friendly_name || s.entity_id,
                isOn: s.state === "on",
                notify: watched.indexOf(s.entity_id) >= 0,
                value: s.state,
                unit: s.attributes.unit_of_measurement || "",
                // Für Lichter: Rohattribute (supported_color_modes,
                // brightness, color_temp_kelvin, ...) fürs Submenu
                // in LightDetailPage.qml -- s.u. openLightDetail().
                attributes: domain === "light" ? s.attributes : ({})
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
            var entities = rooms[roomName]
            entities.sort(function (x, y) {
                if (x.kind !== y.kind) {
                    return x.kind === "toggle" ? -1 : 1
                }
                return x.friendlyName.localeCompare(y.friendlyName)
            })
            entriesModel.append({ rowType: "header", room: roomName, count: entities.length, entityId: "", domain: "", kind: "", friendlyName: "", isOn: false, notify: false, value: "", unit: "", attributes: ({}) })
            for (var m = 0; m < entities.length; m++) {
                var e = entities[m]
                e.rowType = "entity"
                e.room = roomName
                e.count = 0
                entriesModel.append(e)
            }
        }
    }

    function openLightDetail(index) {
        var entry = entriesModel.get(index)
        pageStack.push(Qt.resolvedUrl("../pages/LightDetailPage.qml"), {
            entityId: entry.entityId,
            entityName: entry.friendlyName,
            entityIsOn: entry.isOn,
            attributes: entry.attributes
        })
    }

    function refresh() {
        if (!configured) {
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
                        // bei Fehlschlag (z.B. zu alte HA-Version) landet
                        // einfach alles unter "Ohne Raum" statt die Seite zu
                        // blockieren.
                        busyIndicator.running = false
                        buildEntries(states, [])
                    })
            },
            function (error) {
                busyIndicator.running = false
                errorText = error.hint || qsTr("Unbekannter Fehler")
            })
    }

    // HA's toggle-service response only confirms the command was accepted,
    // not that the physical device (Zigbee/Matter/etc.) already reports its
    // new state back -- an immediate refresh() right after can still show
    // the pre-toggle state. Wait a second, then re-check.
    Timer {
        id: postToggleRefreshTimer
        interval: 1000
        repeat: false
        onTriggered: refresh()
    }

    function toggle(index) {
        var entry = entriesModel.get(index)
        HaApi.callService(baseUrlSetting.value, tokenSetting.value,
            entry.domain, "toggle", { entity_id: entry.entityId },
            function () { postToggleRefreshTimer.restart() },
            function (error) { errorText = error.hint || qsTr("Unbekannter Fehler") })
    }

    // Ausbaustufe 2: WebSocket-Live-Updates statt reinem REST-Poll. Die
    // REST-Calls in refresh() bleiben die Quelle für Struktur (Räume,
    // Sortierung, initialer Zustand) -- der Socket liefert danach nur noch
    // Deltas (state_changed), die per-Zeile in entriesModel gepatcht
    // werden, ohne komplettes Neu-Aufbauen der Liste.
    //
    // Bekannte Einschränkung: HAs subscribe_events(state_changed) kennt
    // keine serverseitige Domain-Filterung -- bei grossen Instanzen (hier:
    // 1499 Entities) kommen laufend Events für Entities, die gar nicht in
    // unserem Model sind (z.B. Energie-Sensoren im Sekundentakt). Wird pro
    // Event mit einem linearen Scan über entriesModel verworfen -- für die
    // hier relevanten Listengrössen (wenige hundert Zeilen) unkritisch,
    // könnte bei Bedarf später per entityId->index-Map optimiert werden.
    function wsUrlFor(url) {
        return url.replace(/\/+$/, "").replace(/^http/, "ws") + "/api/websocket"
    }

    function applyStateChange(entityId, newState) {
        for (var i = 0; i < entriesModel.count; i++) {
            var row = entriesModel.get(i)
            if (row.rowType !== "entity" || row.entityId !== entityId) {
                continue
            }
            if (row.kind === "toggle") {
                entriesModel.setProperty(i, "isOn", newState.state === "on")
            } else if (row.kind === "sensor") {
                entriesModel.setProperty(i, "value", newState.state)
                entriesModel.setProperty(i, "unit", (newState.attributes && newState.attributes.unit_of_measurement) || "")
            }
            return
        }
    }

    WebSocket {
        id: liveSocket
        url: baseUrlSetting.value.length > 0 ? wsUrlFor(baseUrlSetting.value) : ""
        active: configured

        onStatusChanged: {
            if (status === WebSocket.Closed || status === WebSocket.Error) {
                wsSubscribed = false
                wsReconnectTimer.restart()
            }
        }

        onTextMessageReceived: {
            var msg
            try {
                msg = JSON.parse(message)
            } catch (e) {
                return
            }
            if (msg.type === "auth_required") {
                sendTextMessage(JSON.stringify({ type: "auth", access_token: tokenSetting.value }))
            } else if (msg.type === "auth_ok") {
                wsMessageId = 1
                sendTextMessage(JSON.stringify({ id: wsMessageId, type: "subscribe_events", event_type: "state_changed" }))
                wsMessageId += 1
                wsSubscribed = true
            } else if (msg.type === "auth_invalid") {
                wsSubscribed = false
            } else if (msg.type === "event" && msg.event && msg.event.event_type === "state_changed") {
                var data = msg.event.data
                if (data && data.new_state) {
                    applyStateChange(data.entity_id, data.new_state)
                }
            }
        }
    }

    // Kein automatisches Reconnect im WebSocket-Typ selbst -- bei
    // Closed/Error nach 5s erneut versuchen, solange noch konfiguriert.
    // active wird per Qt.binding() wiederhergestellt, damit spätere
    // Änderungen an "configured" (z.B. Token in Settings gelöscht) den
    // Socket weiterhin korrekt reaktiv deaktivieren.
    Timer {
        id: wsReconnectTimer
        interval: 5000
        repeat: false
        onTriggered: {
            liveSocket.active = false
            liveSocket.active = Qt.binding(function () { return configured })
        }
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
                title: qsTr("HA Control")
                description: wsSubscribed ? qsTr("Live") : ""
            }

            Label {
                visible: !configured
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("Noch nicht konfiguriert -- unter Settings die Home-Assistant-URL und einen Long-Lived Access Token eintragen.")
                color: Theme.secondaryHighlightColor
            }
            Label {
                visible: errorText.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: errorText
                color: Theme.errorColor
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

            menu: (!isHeader && model.kind === "toggle") ? notifyMenuComponent : null

            // Bei Lichtern: Tap auf den Namen öffnet das Submenu mit
            // Helligkeit/Farbe/Farbtemperatur. Der Switch hat sein eigenes
            // onClicked und "gewinnt" für Taps auf seinem eigenen Bereich;
            // koexistiert mit dem Long-Press-Kontextmenü oben (ListItem
            // unterstützt onClicked + menu: gleichzeitig).
            onClicked: {
                if (!isHeader && model.kind === "toggle" && model.domain === "light") {
                    openLightDetail(index)
                }
            }

            Component {
                id: notifyMenuComponent
                ContextMenu {
                    MenuItem {
                        text: model.notify ? qsTr("Benachrichtigung deaktivieren") : qsTr("Bei Änderung benachrichtigen")
                        onClicked: toggleWatch(index)
                    }
                }
            }

            // -- Room header row --
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
            MouseArea {
                anchors.fill: parent
                enabled: delegateItem.isHeader
                onClicked: toggleRoom(model.room)
            }

            // -- Entity row: toggle (light/switch) --
            ScrollingLabel {
                visible: !delegateItem.isHeader && model.kind === "toggle"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin - notifyLabel.width - toggleSwitch.width
                anchors.verticalCenter: parent.verticalCenter
                text: model.friendlyName || ""
            }
            Label {
                id: notifyLabel
                visible: !delegateItem.isHeader && model.kind === "toggle" && model.notify === true
                anchors.right: toggleSwitch.left
                anchors.rightMargin: Theme.paddingSmall
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("benachrichtigt")
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
            }
            Switch {
                id: toggleSwitch
                visible: !delegateItem.isHeader && model.kind === "toggle"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: model.isOn === true
                onClicked: toggle(index)
            }

            // -- Entity row: read-only sensor (Temperatur/Feuchte/Luftdruck) --
            ScrollingLabel {
                visible: !delegateItem.isHeader && model.kind === "sensor"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin - sensorValueLabel.width - Theme.paddingSmall
                anchors.verticalCenter: parent.verticalCenter
                text: model.friendlyName || ""
            }
            Label {
                id: sensorValueLabel
                visible: !delegateItem.isHeader && model.kind === "sensor"
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: formatSensorValue(model.value, model.unit)
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
