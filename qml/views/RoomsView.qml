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
    // Jedes state_changed-Event vom WebSocket, ungefiltert weitergereicht --
    // Detailseiten (CoverDetailPage.qml) hängen sich per Connections daran,
    // um z.B. die Position eines fahrenden Rollos live nachzuziehen.
    signal liveStateReceived(string changedEntityId, var newState)

    // Comma-separated entity_ids -- shared with the BackgroundJob poller
    // in harbour-hacontrol.qml (Ausbaustufe 3, Variante B).
    ConfigurationValue {
        id: watchedSetting
        key: "/apps/harbour-hacontrol/watchedEntities"
        defaultValue: ""
    }
    // Comma-separated entity_ids, same format as watchedEntities -- only
    // used here. Favorites get a second copy of their row in an always-
    // expanded group at the top of the list (s. buildEntries()).
    ConfigurationValue {
        id: favoritesSetting
        key: "/apps/harbour-hacontrol/favoriteEntities"
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
    // Read by CoverPage.qml (separate ConfigurationValue instances on the
    // same keys, same pattern as webhookIdSetting above) so the cover can
    // show "key information" and offer a Cover Action without needing its
    // own HA query while minimized.
    ConfigurationValue {
        id: coverLightsOnCountSetting
        key: "/apps/harbour-hacontrol/coverLightsOnCount"
        defaultValue: 0
    }
    ConfigurationValue {
        id: coverLastLightIdSetting
        key: "/apps/harbour-hacontrol/coverLastLightId"
        defaultValue: ""
    }
    ConfigurationValue {
        id: coverLastLightNameSetting
        key: "/apps/harbour-hacontrol/coverLastLightName"
        defaultValue: ""
    }

    // Von FirstPage.qml gesetzt: true, sobald diese Seite vorne ist. Geladen
    // wird erst dann -- s. loadIfNeeded().
    property bool viewActive: false
    property bool loadedOnce: false

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
    readonly property string noRoomLabel: qsTr("No room")
    // room name -> bool. Missing key == collapsed (rooms start folded).
    property var expandedRooms: ({})
    readonly property string favoritesLabel: qsTr("Favorites")

    // Suche: searchText folgt dem SearchField sofort, searchQuery erst nach
    // dem Debounce (searchTimer) -- nur searchQuery löst den Scan über
    // entriesModel aus. Das Ergebnis liegt als zwei Maps vor, an denen die
    // Delegates per Lookup ihre Sichtbarkeit festmachen, statt dass jeder
    // Delegate selbst Strings vergleicht. expandedRooms bleibt dabei
    // unberührt -- nach dem Leeren des Felds ist der alte Auf-/Zuklapp-
    // Zustand wieder da.
    property string searchText: ""
    property string searchQuery: ""
    readonly property bool searchActive: searchQuery.length > 0
    property var searchMatches: ({})     // entityId -> true
    property var searchRoomCounts: ({})  // room -> number of matches
    property int searchMatchCount: 0

    // "toggle" umfasst alle Domains, die HAs generischen <domain>.toggle-
    // Service unterstützen -- fan/cover haben kein eigenes Submenu, nur
    // Ein-/Aus (bzw. Auf/Zu) über den bestehenden Switch-Mechanismus.
    // input_boolean (Helfer) verhält sich wie ein Schalter, inkl.
    // input_boolean.toggle.
    readonly property var toggleDomains: ["light", "switch", "fan", "cover", "input_boolean"]
    readonly property var climateDomains: ["climate"]
    readonly property var mediaPlayerDomains: ["media_player"]
    // scene hat keinen sinnvollen on/off-state (state ist der Zeitpunkt der
    // letzten Aktivierung) und keinen toggle-Service -- eigener kind mit
    // Tap-zum-Aktivieren statt Switch.
    // script/button/input_button teilen sich diesen kind: ebenfalls kein
    // sinnvoller on/off-state (bei button/input_button ist state wie bei
    // Szenen der Zeitpunkt des letzten Drucks), Tap löst aus -- Service je
    // Domain s. runServiceFor().
    readonly property var sceneDomains: ["scene", "script", "button", "input_button"]
    // lock: Zustand anzeigen, Abschliessen direkt, Aufschliessen/Öffnen nur
    // mit Remorse-Frist (s. Delegate).
    readonly property var lockDomains: ["lock"]
    readonly property var sensorDeviceClasses: ["temperature", "humidity", "pressure", "atmospheric_pressure", "battery", "energy", "power"]
    // Reihenfolge innerhalb eines Raums: steuerbare Entities zuerst,
    // read-only Sensoren zuletzt.
    readonly property var kindOrder: ({ toggle: 0, lock: 1, climate: 2, mediaplayer: 3, scene: 4, sensor: 5 })
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

    function lockStateLabel(state) {
        switch (state) {
        case "locked": return qsTr("Locked")
        case "unlocked": return qsTr("Unlocked")
        case "locking": return qsTr("Locking")
        case "unlocking": return qsTr("Unlocking")
        case "jammed": return qsTr("Jammed")
        case "open": return qsTr("Open", "lock state")
        case "opening": return qsTr("Opening")
        case "unavailable": return qsTr("Unavailable")
        default: return state
        }
    }

    // Rollos mit Positionsangabe (supported_features SET_POSITION = 4 oder
    // ein gemeldetes current_position) bekommen eine Detailseite mit
    // Positions-Slider; alle anderen bleiben reiner Auf/Zu-Toggle.
    function coverHasPosition(attrs) {
        if (!attrs) {
            return false
        }
        return ((attrs.supported_features || 0) & 4) !== 0
            || (attrs.current_position !== undefined && attrs.current_position !== null)
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
        // Favoriten stehen doppelt im Model (Raum + Favoriten-Gruppe) --
        // beide Kopien nachführen.
        setPropertyForEntity(entry.entityId, "notify", pos < 0)
    }

    function setPropertyForEntity(entityId, role, value) {
        for (var i = 0; i < entriesModel.count; i++) {
            var row = entriesModel.get(i)
            if (row.rowType === "entity" && row.entityId === entityId) {
                entriesModel.setProperty(i, role, value)
            }
        }
    }

    function favoriteIds() {
        return favoritesSetting.value.split(",").map(function (s) { return s.trim() }).filter(function (s) { return s.length > 0 })
    }

    // Gleiche Reihenfolge wie innerhalb eines Raums: nach kind, dann Name.
    function compareEntities(x, y) {
        if (x.kind !== y.kind) {
            return kindOrder[x.kind] - kindOrder[y.kind]
        }
        return x.friendlyName.localeCompare(y.friendlyName)
    }

    function headerRow(roomName, count, isFavGroup) {
        return { rowType: "header", room: roomName, count: count, entityId: "", domain: "", kind: "", friendlyName: "", isOn: false, notify: false, favorite: false, favGroup: isFavGroup, value: "", unit: "", hvacMode: "", attributes: ({}) }
    }

    // Plain-JS-Kopie einer Entity-Zeile (entriesModel.get() liefert ein an
    // das Model gebundenes Objekt, das nach insert/remove nicht mehr
    // verlässlich ist).
    function copyEntityRow(row) {
        return { rowType: "entity", room: row.room, count: 0, entityId: row.entityId, domain: row.domain, kind: row.kind, friendlyName: row.friendlyName, isOn: row.isOn, notify: row.notify, favorite: row.favorite, favGroup: row.favGroup, value: row.value, unit: row.unit, hvacMode: row.hvacMode, attributes: row.attributes }
    }

    // Inkrementell statt buildEntries() neu aufzurufen: dafür fehlen hier
    // die Rohdaten, und ein Neuaufbau über alle Zeilen wäre für einen
    // einzelnen Stern unnötig teuer. Die Favoriten-Gruppe steht, falls
    // vorhanden, immer ab Index 0 (Header) mit `count` Zeilen danach.
    function toggleFavorite(index) {
        var entry = copyEntityRow(entriesModel.get(index))
        var ids = favoriteIds()
        var pos = ids.indexOf(entry.entityId)
        var nowFavorite = pos < 0
        if (nowFavorite) {
            ids.push(entry.entityId)
        } else {
            ids.splice(pos, 1)
        }
        favoritesSetting.value = ids.join(",")

        var favCount = (entriesModel.count > 0 && entriesModel.get(0).favGroup === true) ? entriesModel.get(0).count : -1
        if (nowFavorite) {
            if (favCount < 0) {
                entriesModel.insert(0, headerRow(favoritesLabel, 0, true))
                favCount = 0
            }
            entry.room = favoritesLabel
            entry.favGroup = true
            entry.favorite = true
            var insertAt = 1 + favCount
            for (var i = 1; i <= favCount; i++) {
                if (compareEntities(entry, entriesModel.get(i)) < 0) {
                    insertAt = i
                    break
                }
            }
            entriesModel.insert(insertAt, entry)
            entriesModel.setProperty(0, "count", favCount + 1)
        } else if (favCount > 0) {
            for (var j = 1; j <= favCount; j++) {
                if (entriesModel.get(j).entityId === entry.entityId) {
                    entriesModel.remove(j)
                    favCount--
                    break
                }
            }
            if (favCount === 0) {
                entriesModel.remove(0)
            } else {
                entriesModel.setProperty(0, "count", favCount)
            }
        }
        setPropertyForEntity(entry.entityId, "favorite", nowFavorite)
    }

    Timer {
        id: searchTimer
        interval: 250
        repeat: false
        onTriggered: searchQuery = searchText.trim().toLowerCase()
    }

    onSearchTextChanged: {
        // Leeren wirkt sofort -- nur das Tippen wird entprellt.
        if (searchText.trim().length === 0) {
            searchTimer.stop()
            searchQuery = ""
        } else {
            searchTimer.restart()
        }
    }

    onSearchQueryChanged: updateSearch()

    // Ein Durchlauf über entriesModel (~400 Zeilen) pro entprellter
    // Eingabe. Die Kopien in der Favoriten-Gruppe zählen nicht mit -- die
    // Gruppe ist während der Suche ausgeblendet, sonst stünden Favoriten
    // doppelt im Ergebnis.
    function updateSearch() {
        var matches = {}
        var roomCounts = {}
        var total = 0
        if (searchQuery.length > 0) {
            for (var i = 0; i < entriesModel.count; i++) {
                var row = entriesModel.get(i)
                if (row.rowType !== "entity" || row.favGroup === true) {
                    continue
                }
                if (row.friendlyName.toLowerCase().indexOf(searchQuery) >= 0
                        || row.entityId.toLowerCase().indexOf(searchQuery) >= 0) {
                    matches[row.entityId] = true
                    roomCounts[row.room] = (roomCounts[row.room] || 0) + 1
                    total++
                }
            }
        }
        searchMatches = matches
        searchRoomCounts = roomCounts
        searchMatchCount = total
    }

    function formatSensorValue(value, unit) {
        var num = parseFloat(value)
        var text = isNaN(num) ? value : num.toFixed(1)
        return text + (unit ? (" " + unit) : "")
    }

    function mediaStateLabel(state) {
        switch (state) {
        case "playing": return qsTr("Playing")
        case "paused": return qsTr("Paused")
        case "idle": return qsTr("Idle")
        case "off": return qsTr("Off")
        case "on": return qsTr("On")
        case "buffering": return qsTr("Buffering")
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
        var favorites = favoriteIds()
        var favoriteEntities = []
        var rooms = {}
        // Für CoverPage.qml -- im selben Durchlauf mitgezählt statt per
        // separatem O(n)-Scan über das fertig gebaute entriesModel danach
        // (das kostete auf einem Gerät mit ~700+ Zeilen und schon hoher
        // Systemlast spürbar Zeit auf dem GUI-Thread -- ANR beim Refresh).
        var lightsOnCount = 0

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
            } else if (lockDomains.indexOf(domain) >= 0) {
                kind = "lock"
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
            var isOnValue = isEntityOn(domain, s.state)
            if (kind === "toggle" && domain === "light" && isOnValue) {
                lightsOnCount++
            }
            rooms[room].push({
                entityId: s.entity_id,
                domain: domain,
                kind: kind,
                friendlyName: s.attributes.friendly_name || s.entity_id,
                isOn: isOnValue,
                notify: watched.indexOf(s.entity_id) >= 0,
                favorite: favorites.indexOf(s.entity_id) >= 0,
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
                // cover: supported_features/current_position für
                // CoverDetailPage.qml, lock: supported_features (OPEN).
                attributes: (domain === "light" || domain === "climate" || domain === "media_player" || domain === "cover" || domain === "lock") ? s.attributes : ({})
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
            entities.sort(compareEntities)
            for (var m = 0; m < entities.length; m++) {
                var e = entities[m]
                e.rowType = "entity"
                e.room = roomName
                e.count = 0
                e.favGroup = false
                if (e.favorite) {
                    favoriteEntities.push(e)
                }
            }
        }

        // Favoriten-Gruppe zuerst, als eigene Kopien der Zeilen (die
        // Raum-Zeile bleibt zusätzlich bestehen).
        if (favoriteEntities.length > 0) {
            favoriteEntities.sort(compareEntities)
            entriesModel.append(headerRow(favoritesLabel, favoriteEntities.length, true))
            for (var f = 0; f < favoriteEntities.length; f++) {
                var fav = copyEntityRow(favoriteEntities[f])
                fav.room = favoritesLabel
                fav.favGroup = true
                entriesModel.append(fav)
            }
        }
        for (var r = 0; r < roomNames.length; r++) {
            var rn = roomNames[r]
            var list = rooms[rn]
            entriesModel.append(headerRow(rn, list.length, false))
            for (var n = 0; n < list.length; n++) {
                entriesModel.append(list[n])
            }
        }
        coverLightsOnCountSetting.value = lightsOnCount
        if (searchActive) {
            updateSearch()
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

    function openCoverDetail(index) {
        var entry = entriesModel.get(index)
        pageStack.push(Qt.resolvedUrl("../pages/CoverDetailPage.qml"), {
            entityId: entry.entityId,
            entityName: entry.friendlyName,
            entityState: entry.value,
            attributes: entry.attributes,
            stateSource: root
        })
    }

    // entityId der zuletzt ausgelösten Szene/Skript/Taste -- deren Zeile
    // zeigt kurz "Done" als Rückmeldung (ein einzelner Timer hier statt
    // einer pro Delegate).
    property string triggeredEntityId: ""
    Timer {
        id: triggeredFeedbackTimer
        interval: 2000
        repeat: false
        onTriggered: triggeredEntityId = ""
    }

    function runServiceFor(domain) {
        return (domain === "button" || domain === "input_button") ? "press" : "turn_on"
    }

    function runHintFor(domain, state, entityId) {
        if (entityId === triggeredEntityId) {
            return qsTr("Done")
        }
        if (domain === "script") {
            return state === "on" ? qsTr("Running") : qsTr("Run")
        }
        if (domain === "button" || domain === "input_button") {
            return qsTr("Press")
        }
        return qsTr("Activate")
    }

    // Szenen/Skripte/Tasten haben keinen on/off-Zustand und keinen toggle-
    // Service -- Tap löst sie direkt aus, statt eine Detailseite zu öffnen.
    // script.turn_on startet das Skript im Hintergrund (wartet nicht auf
    // dessen Ende), button/input_button.press drückt die Taste.
    function activateScene(index) {
        var entry = entriesModel.get(index)
        var entityId = entry.entityId
        HaApi.callService(Credentials.baseUrl, Credentials.token,
            entry.domain, runServiceFor(entry.domain), { entity_id: entityId },
            function () {
                triggeredEntityId = entityId
                triggeredFeedbackTimer.restart()
            },
            function (error) { errorText = error.hint || qsTr("Unknown error") })
    }

    // Per entityId statt Zeilenindex -- Aufschliessen läuft über eine
    // Remorse-Frist, in der ein Refresh die Liste neu aufbauen kann (gleiche
    // Begründung wie installUpdate() in UpdatesView.qml).
    function callLock(entityId, service) {
        HaApi.callService(Credentials.baseUrl, Credentials.token,
            "lock", service, { entity_id: entityId },
            function () {},
            function (error) { errorText = error.hint || qsTr("Unknown error") })
    }

    // Nach einem WebSocket-(Re)Connect die per REST geladene Struktur
    // nachziehen, aber nur wenn gerade nichts Brauchbares dasteht: war HA
    // kurz weg, blieb sonst "Keine Verbindung" stehen, obwohl die Live-
    // Verbindung längst wieder läuft (der WS bringt nur Deltas, keine
    // Struktur). Die Bedingung verhindert zugleich einen überflüssigen
    // zweiten Ladevorgang beim normalen Start, wo onConfiguredChanged schon
    // geladen hat. refresh() berührt wsSubscribed nicht -- keine Schleife.
    // Entprellt: nach einer längeren Störung kommen mehrere pending
    // Reconnects fast gleichzeitig durch, wsSubscribed wechselt mehrfach
    // hintereinander. Ungebremst lief refreshAll() dadurch dreimal in
    // derselben Sekunde (gemessen) -- dreimal getStates über ~1500 Entities,
    // genau die Lastspitze, die auf dem Gerät schon zu einem ANR geführt hat.
    // Ein `!busyIndicator.running`-Guard allein reichte nicht (immer noch
    // zweimal), der Timer schon: jeder weitere Wechsel startet ihn neu, es
    // feuert nur einer, eine Sekunde nach dem letzten Reconnect.
    Timer {
        id: reconnectRefresh
        interval: 1000
        repeat: false
        onTriggered: {
            if (errorText.length > 0 || entriesModel.count === 0) {
                refreshRequested()
            }
        }
    }

    onWsSubscribedChanged: if (wsSubscribed) reconnectRefresh.restart()

    // Ist Home Assistant nicht erreichbar, feuert bei QMLs XMLHttpRequest
    // weder der Erfolgs- noch der Fehler-Callback (bis das TCP-Timeout des
    // Systems zuschlägt, vergehen Minuten) -- der BusyIndicator drehte dann
    // endlos und die App wirkte eingefroren, statt den "Keine
    // Verbindung"-Platzhalter zu zeigen. Dieser Timer begrenzt das: bei
    // jedem Ladeversuch neu gestartet, von jedem Callback gestoppt. Trifft
    // die Antwort später doch noch ein, überschreibt sie den Fehler wieder.
    Timer {
        id: requestTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            busyIndicator.running = false
            errorText = qsTr("Home Assistant is not responding.")
            Credentials.reportConnectionProblem()
        }
    }

    function refresh() {
        if (!configured) {
            return
        }
        errorText = ""
        busyIndicator.running = true
        requestTimeout.restart()
        HaApi.getStates(Credentials.baseUrl, Credentials.token,
            function (states) {
                HaApi.getAreaMap(Credentials.baseUrl, Credentials.token,
                    function (areaPairs) {
                        requestTimeout.stop()
                        busyIndicator.running = false
                        buildEntries(states, areaPairs)
                    },
                    function (error) {
                        // Area-Zuordnung ist ein Komfort-Feature, kein Muss --
                        // bei Fehlschlag (z.B. zu alte HA-Version) landet
                        // einfach alles unter "Ohne Raum" statt die Seite zu
                        // blockieren.
                        requestTimeout.stop()
                        busyIndicator.running = false
                        buildEntries(states, [])
                    })
            },
            function (error) {
                requestTimeout.stop()
                busyIndicator.running = false
                errorText = error.hint || qsTr("Unknown error")
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
            function () {
                postToggleRefreshTimer.restart()
                // Merkt sich das zuletzt umgeschaltete Licht für die
                // CoverAction in CoverPage.qml -- andere Domains (switch/
                // fan/cover) haben dort keinen sinnvollen Anwendungsfall.
                if (entry.domain === "light") {
                    coverLastLightIdSetting.value = entry.entityId
                    coverLastLightNameSetting.value = entry.friendlyName
                }
            },
            function (error) { errorText = error.hint || qsTr("Unknown error") })
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

    // Favoriten stehen doppelt im Model -- darum kein Abbruch nach dem
    // ersten Treffer, alle Kopien werden gepatcht. Der Cover-Zähler wird
    // nur einmal pro Entity nachgeführt (countedLight).
    function applyStateChange(entityId, newState) {
        var countedLight = false
        for (var i = 0; i < entriesModel.count; i++) {
            var row = entriesModel.get(i)
            if (row.rowType !== "entity" || row.entityId !== entityId) {
                continue
            }
            if (row.kind === "toggle") {
                var wasOn = row.isOn === true
                var nowOn = isEntityOn(row.domain, newState.state)
                entriesModel.setProperty(i, "isOn", nowOn)
                // Nur für Lichter tatsächlich befüllt (s. buildEntries()) --
                // hier trotzdem generisch mitgeführt, damit der Farb-Swatch
                // auch bei externen Änderungen (Live-Update) sofort
                // nachzieht, statt erst beim nächsten Pull-to-refresh.
                if (row.domain === "cover") {
                    entriesModel.setProperty(i, "value", newState.state)
                    entriesModel.setProperty(i, "attributes", newState.attributes || {})
                }
                if (row.domain === "light") {
                    entriesModel.setProperty(i, "attributes", newState.attributes || {})
                    // O(1) nachführen statt eines vollen Rescans über
                    // entriesModel bei jedem einzelnen Live-Update -- ein
                    // Rescan pro Event kostete auf einem Gerät mit ~700+
                    // Zeilen und schon hoher Systemlast spürbar GUI-Thread-
                    // Zeit (ANR).
                    if (wasOn !== nowOn && !countedLight) {
                        coverLightsOnCountSetting.value += nowOn ? 1 : -1
                    }
                    countedLight = true
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
            } else if (row.kind === "scene") {
                // Für script ("on" == läuft gerade) -- bei scene/button nur
                // der Zeitpunkt, schadet aber nicht.
                entriesModel.setProperty(i, "value", newState.state)
            } else if (row.kind === "lock") {
                entriesModel.setProperty(i, "value", newState.state)
                entriesModel.setProperty(i, "attributes", newState.attributes || {})
            }
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
            // Host unreachable (left home, VPN down, ...): let Credentials
            // re-check the internal URL; if that switches baseUrl, the url
            // binding above reconnects to the other host, and the
            // wsSubscribed -> reconnectRefresh path reloads as after any
            // reconnect. Rate-limited in C++.
            if (status === WebSocket.Error) {
                Credentials.reportConnectionProblem()
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
                    liveStateReceived(data.entity_id, data.new_state)
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
        onTriggered: reconnectSocket()
    }

    function reconnectSocket() {
        liveSocket.active = false
        liveSocket.active = Qt.binding(function () { return configured })
    }

    // Credentials.baseUrl is the *effective* URL and flips between the
    // internal and the external one (src/credentials.h). The url binding
    // alone would leave a connect attempt that is hanging on the
    // unreachable old host alone until its TCP timeout, so reconnect
    // explicitly -- the same path as wsReconnectTimer, just right away.
    Connections {
        target: Credentials
        onBaseUrlChanged: if (configured) reconnectSocket()
    }

    // Lädt beim ersten Sichtbarwerden, sobald Zugangsdaten da sind. Beides
    // kann in beliebiger Reihenfolge eintreten: `configured` wird erst wahr,
    // wenn Credentials' asynchroner Sailfish-Secrets-Request durch ist (oft
    // nach dem Erzeugen dieser View), und `viewActive` erst, wenn der Nutzer
    // hierher wischt. Darum hängt das Laden an beiden Signalen statt an
    // Component.onCompleted, das früher regelmässig zu früh feuerte.
    function loadIfNeeded() {
        if (viewActive && configured && !loadedOnce) {
            loadedOnce = true
            refresh()
        }
    }

    // Für den Pull-down-Refresh aus FirstPage: Seiten, die noch nie geladen
    // haben, bleiben ungeladen (sie holen sich ihre Daten beim Hinwischen).
    function refreshIfLoaded() {
        if (loadedOnce) {
            refresh()
        } else {
            loadIfNeeded()
        }
    }

    Component.onCompleted: loadIfNeeded()
    onViewActiveChanged: loadIfNeeded()
    onConfiguredChanged: loadIfNeeded()

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
                title: qsTr("Rooms")
                description: wsSubscribed ? qsTr("Live") : ""
            }

            SearchField {
                width: parent.width
                visible: configured
                placeholderText: qsTr("Search devices")
                onTextChanged: root.searchText = text
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }
        }

        // Leere Zustände über Silicas ViewPlaceholder statt über eigene
        // Labels im Header -- zentriert, plattformtypisch, und der hintText
        // nennt gleich den Weg zurück (Settings bzw. Pull-down-Refresh),
        // statt den Nutzer vor einer leeren Seite stehen zu lassen.
        ViewPlaceholder {
            flickable: listView
            enabled: !configured
            text: qsTr("Not configured yet")
            hintText: qsTr("Open Settings in the pull-down menu and enter the Home Assistant URL and a long-lived access token.")
        }
        ViewPlaceholder {
            flickable: listView
            enabled: configured && errorText.length > 0
            text: qsTr("No connection")
            hintText: errorText
        }
        ViewPlaceholder {
            flickable: listView
            enabled: configured && errorText.length === 0 && entriesModel.count === 0 && !busyIndicator.running
            text: qsTr("No devices")
            hintText: qsTr("Home Assistant reports no controllable entities. Pull down to refresh.")
        }
        ViewPlaceholder {
            flickable: listView
            enabled: configured && errorText.length === 0 && entriesModel.count > 0 && searchActive && searchMatchCount === 0
            text: qsTr("No matches")
            hintText: qsTr("No device name or entity ID contains \"%1\".").arg(searchQuery)
        }

        delegate: ListItem {
            id: delegateItem
            width: listView.width
            readonly property bool isHeader: model.rowType === "header"
            readonly property bool isFavGroup: model.favGroup === true
            // Während der Suche: Favoriten-Gruppe aus, Räume nur mit
            // Treffern, und dort nur die Treffer (aufgeklappt, egal ob der
            // Raum sonst zu ist). Sonst: Favoriten immer offen, Räume nach
            // expandedRooms.
            readonly property bool rowVisible: searchActive
                ? (!isFavGroup && (isHeader ? searchRoomCounts[model.room] > 0 : searchMatches[model.entityId] === true))
                : (isHeader || isFavGroup || expandedRooms[model.room] === true)
            contentHeight: rowVisible ? (isHeader ? Theme.itemSizeExtraSmall : Theme.itemSizeMedium) : 0
            visible: rowVisible
            clip: true

            // Bei Szenen ergibt "bei Änderung benachrichtigen" keinen Sinn
            // -- ihr state ist nur der Zeitpunkt der letzten Aktivierung,
            // kein sinnvoller on/off-Zustand.
            // Favorit geht für alle kinds, "Benachrichtigen" nur für die
            // drei unten -- eine Menükomponente, der Notify-Eintrag blendet
            // sich bei Bedarf aus.
            readonly property bool canNotify: model.kind === "toggle" || model.kind === "climate" || model.kind === "mediaplayer"
            menu: !isHeader ? entityMenuComponent : null
            // Schlösser: kein "Notify on change" (canNotify schliesst lock
            // aus) -- die Benachrichtigung bietet "Toggle" an, das liefe
            // ohne Bestätigung, und lock hat keinen toggle-Service. Die
            // Lock-Einträge stehen stattdessen im selben Menü.

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
                } else if (model.kind === "toggle" && model.domain === "cover" && coverHasPosition(model.attributes)) {
                    openCoverDetail(index)
                } else if (model.kind === "lock") {
                    // Abschliessen sofort, Aufschliessen erst nach Remorse-
                    // Frist. Während eines Übergangs (locking/unlocking/
                    // opening) oder unavailable: nichts tun.
                    var lockEntityId = model.entityId
                    if (model.value === "locked") {
                        remorseAction(qsTr("Unlocking"), function () { callLock(lockEntityId, "unlock") })
                    } else if (model.value === "unlocked" || model.value === "open" || model.value === "jammed") {
                        callLock(lockEntityId, "lock")
                    }
                } else if (model.kind === "climate") {
                    openThermostatDetail(index)
                } else if (model.kind === "mediaplayer") {
                    openMediaPlayerDetail(index)
                } else if (model.kind === "scene") {
                    activateScene(index)
                }
            }

            Component {
                id: entityMenuComponent
                ContextMenu {
                    MenuItem {
                        text: model.favorite ? qsTr("Remove from favorites") : qsTr("Add to favorites")
                        // Erst nach dem Schliessen des Menüs: das Entfernen
                        // kann genau diese Zeile (Kopie in der Favoriten-
                        // Gruppe) aus dem Model löschen.
                        onDelayedClick: toggleFavorite(index)
                    }
                    MenuItem {
                        visible: delegateItem.canNotify
                        text: model.notify ? qsTr("Disable notification") : qsTr("Notify on change")
                        onClicked: toggleWatch(index)
                    }
                    MenuItem {
                        visible: model.kind === "lock"
                        text: qsTr("Lock")
                        onClicked: callLock(model.entityId, "lock")
                    }
                    MenuItem {
                        visible: model.kind === "lock"
                        text: qsTr("Unlock")
                        onClicked: {
                            var entityId = model.entityId
                            delegateItem.remorseAction(qsTr("Unlocking"), function () { callLock(entityId, "unlock") })
                        }
                    }
                    // lock.open (Falle ziehen) nur, wenn das Schloss es kann
                    // -- LockEntityFeature.OPEN = 1.
                    MenuItem {
                        visible: model.kind === "lock" && (model.attributes ? ((model.attributes.supported_features || 0) & 1) !== 0 : false)
                        text: qsTr("Open")
                        onClicked: {
                            var entityId = model.entityId
                            delegateItem.remorseAction(qsTr("Opening"), function () { callLock(entityId, "open") })
                        }
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
                    text: delegateItem.isFavGroup ? "★" : ((searchActive || expandedRooms[model.room] === true) ? "▾" : "▸")
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeMedium
                }
                Label {
                    text: model.room + " (" + (searchActive ? (searchRoomCounts[model.room] || 0) : model.count) + ")"
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeMedium
                }
            }
            MouseArea {
                anchors.fill: parent
                // Favoriten sind immer offen; während der Suche ist das
                // Aufklappen durch die Treffer bestimmt.
                enabled: delegateItem.isHeader && !delegateItem.isFavGroup && !searchActive
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
                text: qsTr("notifies")
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
                text: runHintFor(model.domain, model.value, model.entityId)
                color: model.entityId === triggeredEntityId || (model.domain === "script" && model.value === "on")
                    ? Theme.highlightColor : Theme.secondaryHighlightColor
            }

            // -- Entity row: lock -- Tap schliesst ab bzw. (mit Remorse)
            // auf, Long-Press-Menü für Lock/Unlock/Open.
            ScrollingLabel {
                visible: !delegateItem.isHeader && model.kind === "lock"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin - lockValueLabel.width - Theme.paddingSmall
                anchors.verticalCenter: parent.verticalCenter
                text: model.friendlyName || ""
            }
            Label {
                id: lockValueLabel
                visible: !delegateItem.isHeader && model.kind === "lock"
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: lockStateLabel(model.value)
                color: model.value === "jammed" ? Theme.errorColor
                    : ((model.value === "unlocked" || model.value === "open") ? Theme.highlightColor : Theme.secondaryHighlightColor)
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
