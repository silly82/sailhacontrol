import QtQuick 2.0
import Sailfish.Silica 1.0
import QtWebSockets 1.0
import Nemo.Configuration 1.0
import Nemo.Notifications 1.0
import "../lib/HaApi.js" as HaApi
import "../components"

// One of two swipeable sub-views of FirstPage.qml (the other is
// SensorsView.qml) -- entity list grouped by room, collapsible.
Item {
    id: root

    // Bittet die Seite (FirstPage.qml) um einen Refresh aller Sub-Views --
    // die drei Views liegen gleichzeitig nebeneinander, ein Refresh nur der
    // sichtbaren würde die anderen mit alten Daten stehen lassen.
    signal refreshRequested()

    // Comma-separated entity_ids -- shared with the BackgroundJob poller
    // in harbour-hacontrol.qml (Ausbaustufe 3, Variante B).
    ConfigurationValue {
        id: watchedSetting
        key: "/apps/harbour-hacontrol/watchedEntities"
        defaultValue: ""
    }
    // Set by harbour-hacontrol.qml's ensureMobileAppRegistered() once this
    // device is registered as a mobile_app entry -- used here to open the
    // real push-notification channel over this same WebSocket connection.
    ConfigurationValue {
        id: webhookIdSetting
        key: "/apps/harbour-hacontrol/webhookId"
        defaultValue: ""
    }

    property bool configured: Credentials.baseUrl.length > 0 && Credentials.token.length > 0
    property string errorText: ""
    // true once HA has confirmed our WS auth + subscribe_events -- drives
    // the "Live"-Hinweis im PageHeader.
    property bool wsSubscribed: false
    property int wsMessageId: 1
    // id of the mobile_app/push_notification_channel subscribe message --
    // incoming push events carry this as their "id" (no event_type field,
    // unlike state_changed events), used to tell the two apart in
    // onTextMessageReceived. 0 == not subscribed yet.
    property int pushChannelMsgId: 0
    readonly property string noRoomLabel: qsTr("Ohne Raum")
    // room name -> bool. Missing key == collapsed (rooms start folded).
    property var expandedRooms: ({})

    // "toggle" umfasst alle Domains, die HAs generischen <domain>.toggle-
    // Service unterstützen -- fan/cover haben kein eigenes Submenu, nur
    // Ein-/Aus (bzw. Auf/Zu) über den bestehenden Switch-Mechanismus.
    readonly property var toggleDomains: ["light", "switch", "fan", "cover"]
    readonly property var climateDomains: ["climate"]
    readonly property var mediaPlayerDomains: ["media_player"]
    // scene hat keinen sinnvollen on/off-state (state ist der Zeitpunkt der
    // letzten Aktivierung) und keinen toggle-Service -- eigener kind mit
    // Tap-zum-Aktivieren statt Switch.
    readonly property var sceneDomains: ["scene"]
    readonly property var sensorDeviceClasses: ["temperature", "humidity", "pressure", "atmospheric_pressure", "battery", "energy", "power"]
    // Reihenfolge innerhalb eines Raums: steuerbare Entities zuerst,
    // read-only Sensoren zuletzt.
    readonly property var kindOrder: ({ toggle: 0, climate: 1, mediaplayer: 2, scene: 3, sensor: 4 })
    readonly property real colorSwatchDiameter: Theme.iconSizeExtraSmall

    // "Aus"-Gegenstück ist bei den meisten toggle-Domains state === "on",
    // bei cover aber state === "open" (closed/opening/closing sind die
    // anderen Werte) -- zentral an einer Stelle, statt an jeder Prüfstelle
    // einzeln zu unterscheiden.
    function isEntityOn(domain, state) {
        return domain === "cover" ? state === "open" : state === "on"
    }

    // Farb-Swatch neben Licht-Zeilen: bevorzugt echtes rgb_color, sonst eine
    // Näherung aus color_temp_kelvin (Tanner-Helland-Approximation -- kein
    // exaktes Colorimetrie-Modell, aber für einen kleinen Vorschau-Kreis
    // ausreichend). null, wenn das Licht aus ist oder keins von beidem
    // liefert (HA meldet beide Attribute als null solange das Licht aus
    // ist, siehe LightDetailPage.qml).
    function kelvinToRgb(kelvin) {
        var temp = kelvin / 100
        var r, g, b
        if (temp <= 66) {
            r = 255
        } else {
            r = Math.max(0, Math.min(255, 329.698727446 * Math.pow(temp - 60, -0.1332047592)))
        }
        if (temp <= 66) {
            g = Math.max(0, Math.min(255, 99.4708025861 * Math.log(temp) - 161.1195681661))
        } else {
            g = Math.max(0, Math.min(255, 288.1221695283 * Math.pow(temp - 60, -0.0755148492)))
        }
        if (temp >= 66) {
            b = 255
        } else if (temp <= 19) {
            b = 0
        } else {
            b = Math.max(0, Math.min(255, 138.5177312231 * Math.log(temp - 10) - 305.0447927307))
        }
        return Qt.rgba(r / 255, g / 255, b / 255, 1)
    }

    function colorForLight(attrs, isOn) {
        if (!isOn || !attrs) {
            return null
        }
        if (attrs.rgb_color) {
            return Qt.rgba(attrs.rgb_color[0] / 255, attrs.rgb_color[1] / 255, attrs.rgb_color[2] / 255, 1)
        }
        if (attrs.color_temp_kelvin) {
            return kelvinToRgb(attrs.color_temp_kelvin)
        }
        return null
    }

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

    function mediaStateLabel(state) {
        switch (state) {
        case "playing": return qsTr("Spielt")
        case "paused": return qsTr("Pausiert")
        case "idle": return qsTr("Bereit")
        case "off": return qsTr("Aus")
        case "on": return qsTr("Ein")
        case "buffering": return qsTr("Lädt")
        case "standby": return qsTr("Standby")
        default: return state
        }
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
            } else if (climateDomains.indexOf(domain) >= 0) {
                kind = "climate"
            } else if (mediaPlayerDomains.indexOf(domain) >= 0) {
                kind = "mediaplayer"
            } else if (sceneDomains.indexOf(domain) >= 0) {
                kind = "scene"
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
                isOn: isEntityOn(domain, s.state),
                notify: watched.indexOf(s.entity_id) >= 0,
                // Bei Thermostaten: Zieltemperatur statt hvac_mode-state
                // in der Zeile anzeigen, mit "°C" statt der (meist
                // fehlenden) unit_of_measurement. Als String, da die
                // "value"-Rolle im ListModel typgebunden ist (erster
                // Eintrag legt den Typ fest) -- ein Number-Wert hier würde
                // mit den String-Werten der anderen Kinds kollidieren.
                value: kind === "climate" ? String(s.attributes.temperature !== undefined ? s.attributes.temperature : "") : s.state,
                unit: kind === "climate" ? "°C" : (s.attributes.unit_of_measurement || ""),
                // HAs "state" (bei climate == aktueller hvac_mode wie
                // "off"/"heat") liegt NICHT in attributes, sondern als
                // Geschwisterfeld daneben -- eigenes Feld nötig, "value"
                // ist für climate-Zeilen schon mit der Zieltemperatur belegt.
                hvacMode: kind === "climate" ? s.state : "",
                // Für Lichter, Thermostate und Media Player: Rohattribute
                // (u.a. supported_color_modes/brightness bzw. hvac_modes/
                // min_temp/max_temp bzw. volume_level/media_title) fürs
                // Submenu -- s.u. openLightDetail()/openThermostatDetail()/
                // openMediaPlayerDetail().
                attributes: (domain === "light" || domain === "climate" || domain === "media_player") ? s.attributes : ({})
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
                    return kindOrder[x.kind] - kindOrder[y.kind]
                }
                return x.friendlyName.localeCompare(y.friendlyName)
            })
            entriesModel.append({ rowType: "header", room: roomName, count: entities.length, entityId: "", domain: "", kind: "", friendlyName: "", isOn: false, notify: false, value: "", unit: "", hvacMode: "", attributes: ({}) })
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

    function openThermostatDetail(index) {
        var entry = entriesModel.get(index)
        pageStack.push(Qt.resolvedUrl("../pages/ThermostatDetailPage.qml"), {
            entityId: entry.entityId,
            entityName: entry.friendlyName,
            entityHvacMode: entry.hvacMode,
            attributes: entry.attributes
        })
    }

    function openMediaPlayerDetail(index) {
        var entry = entriesModel.get(index)
        pageStack.push(Qt.resolvedUrl("../pages/MediaPlayerDetailPage.qml"), {
            entityId: entry.entityId,
            entityName: entry.friendlyName,
            entityState: entry.value,
            attributes: entry.attributes
        })
    }

    // Szenen haben keinen on/off-Zustand und keinen toggle-Service -- Tap
    // aktiviert sie direkt, statt eine Detailseite zu öffnen.
    function activateScene(index) {
        var entry = entriesModel.get(index)
        HaApi.callService(Credentials.baseUrl, Credentials.token,
            "scene", "turn_on", { entity_id: entry.entityId },
            function () {},
            function (error) { errorText = error.hint || qsTr("Unbekannter Fehler") })
    }

    function refresh() {
        if (!configured) {
            return
        }
        errorText = ""
        busyIndicator.running = true
        HaApi.getStates(Credentials.baseUrl, Credentials.token,
            function (states) {
                HaApi.getAreaMap(Credentials.baseUrl, Credentials.token,
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
        HaApi.callService(Credentials.baseUrl, Credentials.token,
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
                entriesModel.setProperty(i, "isOn", isEntityOn(row.domain, newState.state))
                // Nur für Lichter tatsächlich befüllt (s. buildEntries()) --
                // hier trotzdem generisch mitgeführt, damit der Farb-Swatch
                // auch bei externen Änderungen (Live-Update) sofort
                // nachzieht, statt erst beim nächsten Pull-to-refresh.
                if (row.domain === "light") {
                    entriesModel.setProperty(i, "attributes", newState.attributes || {})
                }
            } else if (row.kind === "sensor") {
                entriesModel.setProperty(i, "value", newState.state)
                entriesModel.setProperty(i, "unit", (newState.attributes && newState.attributes.unit_of_measurement) || "")
            } else if (row.kind === "climate") {
                var newTemp = newState.attributes && newState.attributes.temperature
                entriesModel.setProperty(i, "value", newTemp !== undefined && newTemp !== null ? String(newTemp) : "")
                entriesModel.setProperty(i, "hvacMode", newState.state || "")
                entriesModel.setProperty(i, "attributes", newState.attributes || {})
            } else if (row.kind === "mediaplayer") {
                entriesModel.setProperty(i, "value", newState.state)
                entriesModel.setProperty(i, "attributes", newState.attributes || {})
            }
            return
        }
    }

    // Called both right after auth_ok and whenever webhookIdSetting changes
    // (Connections below) -- registration in harbour-hacontrol.qml is an
    // async REST call that often hasn't finished by the time auth_ok fires
    // on a fresh install/reconnect, so subscribing only from auth_ok would
    // silently miss the push channel for the rest of that connection's
    // lifetime. Guarded so it only ever sends once per connection.
    function subscribePushChannelIfReady() {
        if (!wsSubscribed || pushChannelMsgId > 0 || webhookIdSetting.value.length === 0) {
            return
        }
        pushChannelMsgId = wsMessageId
        liveSocket.sendTextMessage(JSON.stringify({
            id: pushChannelMsgId, type: "mobile_app/push_notification_channel",
            webhook_id: webhookIdSetting.value, support_confirm: false
        }))
        wsMessageId += 1
    }

    Connections {
        target: webhookIdSetting
        onValueChanged: subscribePushChannelIfReady()
    }

    WebSocket {
        id: liveSocket
        url: Credentials.baseUrl.length > 0 ? wsUrlFor(Credentials.baseUrl) : ""
        active: configured

        onStatusChanged: {
            if (status === WebSocket.Closed || status === WebSocket.Error) {
                wsSubscribed = false
                pushChannelMsgId = 0
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
                sendTextMessage(JSON.stringify({ type: "auth", access_token: Credentials.token }))
            } else if (msg.type === "auth_ok") {
                wsMessageId = 1
                sendTextMessage(JSON.stringify({ id: wsMessageId, type: "subscribe_events", event_type: "state_changed" }))
                wsMessageId += 1
                wsSubscribed = true
                subscribePushChannelIfReady()
            } else if (msg.type === "auth_invalid") {
                wsSubscribed = false
            } else if (msg.type === "event" && msg.event && msg.event.event_type === "state_changed") {
                var data = msg.event.data
                if (data && data.new_state) {
                    applyStateChange(data.entity_id, data.new_state)
                }
            } else if (msg.type === "event" && pushChannelMsgId > 0 && msg.id === pushChannelMsgId) {
                showPushNotification(msg.event)
            }
        }
    }

    // Gleiches Qt.createQmlObject()-Muster wie notifyStateChange() in
    // harbour-hacontrol.qml, hier lokal statt geteilt -- kein Grund, für eine
    // einzelne Notification über Dateigrenzen zu koppeln.
    function showPushNotification(event) {
        var component = 'import QtQuick 2.0\nimport Nemo.Notifications 1.0\nNotification { appName: "HA Control"; category: "x-nemo.example" }'
        var notification = Qt.createQmlObject(component, root, "HaControlPushNotification")
        notification.summary = event.title || qsTr("Home Assistant")
        notification.body = event.message || ""
        notification.publish()
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
                    onClicked: root.refreshRequested()
                }
            }

            PageHeader {
                title: qsTr("Räume")
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

            // Bei Szenen ergibt "bei Änderung benachrichtigen" keinen Sinn
            // -- ihr state ist nur der Zeitpunkt der letzten Aktivierung,
            // kein sinnvoller on/off-Zustand.
            menu: (!isHeader && (model.kind === "toggle" || model.kind === "climate" || model.kind === "mediaplayer")) ? notifyMenuComponent : null

            // Bei Lichtern/Thermostaten/Media-Playern: Tap auf den Namen
            // öffnet das jeweilige Submenu. Bei Szenen aktiviert der Tap
            // direkt (kein Submenu, kein on/off). Der Switch hat sein
            // eigenes onClicked und "gewinnt" für Taps auf seinem eigenen
            // Bereich; koexistiert mit dem Long-Press-Kontextmenü oben
            // (ListItem unterstützt onClicked + menu: gleichzeitig).
            onClicked: {
                if (isHeader) {
                    return
                }
                if (model.kind === "toggle" && model.domain === "light") {
                    openLightDetail(index)
                } else if (model.kind === "climate") {
                    openThermostatDetail(index)
                } else if (model.kind === "mediaplayer") {
                    openMediaPlayerDetail(index)
                } else if (model.kind === "scene") {
                    activateScene(index)
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
                width: parent.width - 2 * Theme.horizontalPageMargin - notifyLabel.width - toggleSwitch.width - colorSwatchDiameter - Theme.paddingSmall
                anchors.verticalCenter: parent.verticalCenter
                text: model.friendlyName || ""
            }
            // Farbvorschau bei Lichtern mit bekannter Farbe/Farbtemperatur --
            // nur sichtbar wenn an (HA liefert rgb_color/color_temp_kelvin
            // sonst als null, s. colorForLight()).
            Rectangle {
                id: colorSwatch
                readonly property var swatchColor: !delegateItem.isHeader && model.kind === "toggle" && model.domain === "light"
                    ? colorForLight(model.attributes, model.isOn) : null
                visible: swatchColor !== null
                anchors.right: notifyLabel.left
                anchors.rightMargin: Theme.paddingSmall
                anchors.verticalCenter: parent.verticalCenter
                width: colorSwatchDiameter
                height: colorSwatchDiameter
                radius: width / 2
                color: swatchColor || "transparent"
                border.width: 1
                border.color: Theme.primaryColor
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

            // -- Entity row: climate (Thermostat) -- Tap öffnet Submenu mit
            // Zieltemperatur-Regler + Modus, wie bei Lichtern.
            ScrollingLabel {
                visible: !delegateItem.isHeader && model.kind === "climate"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin - climateValueLabel.width - Theme.paddingSmall
                anchors.verticalCenter: parent.verticalCenter
                text: model.friendlyName || ""
            }
            Label {
                id: climateValueLabel
                visible: !delegateItem.isHeader && model.kind === "climate"
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: formatSensorValue(model.value, model.unit)
                color: model.attributes && model.attributes.hvac_action === "heating" ? Theme.highlightColor : Theme.secondaryHighlightColor
            }

            // -- Entity row: media_player -- Tap öffnet Submenu mit
            // Play/Pause und Lautstärke, wie bei Lichtern/Thermostaten.
            ScrollingLabel {
                visible: !delegateItem.isHeader && model.kind === "mediaplayer"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin - mediaValueLabel.width - Theme.paddingSmall
                anchors.verticalCenter: parent.verticalCenter
                text: model.friendlyName || ""
            }
            Label {
                id: mediaValueLabel
                visible: !delegateItem.isHeader && model.kind === "mediaplayer"
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: mediaStateLabel(model.value)
                color: model.value === "playing" ? Theme.highlightColor : Theme.secondaryHighlightColor
            }

            // -- Entity row: scene -- kein on/off, Tap aktiviert direkt.
            ScrollingLabel {
                visible: !delegateItem.isHeader && model.kind === "scene"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin - sceneHintLabel.width - Theme.paddingSmall
                anchors.verticalCenter: parent.verticalCenter
                text: model.friendlyName || ""
            }
            Label {
                id: sceneHintLabel
                visible: !delegateItem.isHeader && model.kind === "scene"
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Aktivieren")
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
