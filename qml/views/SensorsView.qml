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

    // Bittet die Seite (FirstPage.qml) um einen Refresh aller Sub-Views --
    // die drei Views liegen gleichzeitig nebeneinander, ein Refresh nur der
    // sichtbaren würde die anderen mit alten Daten stehen lassen.
    signal refreshRequested()

    // Von FirstPage.qml gesetzt: true, sobald diese Seite vorne ist.
    property bool viewActive: false
    property bool loadedOnce: false

    property bool configured: Credentials.baseUrl.length > 0 && Credentials.token.length > 0
    // errorText steht nur noch für echte Fehler. "Noch nicht konfiguriert"
    // lief früher auch darüber und wurde per Textvergleich wieder
    // herausgefiltert -- das wäre spätestens beim Übersetzen gebrochen.
    property string errorText: ""
    readonly property string noRoomLabel: qsTr("No room")
    // room name -> bool. Missing key == collapsed (rooms start folded) --
    // gleiches Muster wie RoomsView.qml, hier separat gehalten statt
    // geteilt (jede Sub-View verwaltet ihren eigenen Auf-/Zu-Zustand).
    property var expandedRooms: ({})

    readonly property var sensorDeviceClasses: ["temperature", "humidity", "pressure", "atmospheric_pressure", "battery", "energy", "power"]

    ListModel {
        id: entriesModel
    }

    // --- Weather card (list header) --------------------------------------
    // One weather.* entity, chosen via EntityPickerPage.qml (tap the card);
    // empty setting == the first one Home Assistant reports. There is no
    // live update path in this view -- the card refreshes with the list.
    ConfigurationValue {
        id: weatherEntitySetting
        key: Credentials.settingsPrefix + "weatherEntity"
        defaultValue: ""
        // Also fires when the entity is picked in Settings.
        onValueChanged: chooseWeather()
    }
    ConfigurationValue {
        id: weatherEntityNameSetting
        key: Credentials.settingsPrefix + "weatherEntityName"
        defaultValue: ""
    }
    // Read by CoverPage.qml (the cover never polls HA itself) -- same
    // pattern as RoomsView.qml's coverLightsOnCount.
    ConfigurationValue {
        id: coverWeatherTextSetting
        key: Credentials.settingsPrefix + "coverWeatherText"
        defaultValue: ""
    }
    // All weather.* states from the last refresh and the one shown.
    property var weatherStates: []
    property var weather: null
    ListModel {
        id: forecastModel
    }

    function weatherConditionLabel(condition) {
        switch (condition) {
        case "clear-night": return qsTr("Clear night")
        case "cloudy": return qsTr("Cloudy")
        case "exceptional": return qsTr("Exceptional")
        case "fog": return qsTr("Fog")
        case "hail": return qsTr("Hail")
        case "lightning": return qsTr("Thunderstorm")
        case "lightning-rainy": return qsTr("Thunderstorm, rain")
        case "partlycloudy": return qsTr("Partly cloudy")
        case "pouring": return qsTr("Pouring rain")
        case "rainy": return qsTr("Rainy")
        case "snowy": return qsTr("Snowy")
        case "snowy-rainy": return qsTr("Sleet")
        case "sunny": return qsTr("Sunny")
        case "windy": return qsTr("Windy")
        case "windy-variant": return qsTr("Windy, cloudy")
        case "unavailable": return qsTr("Unavailable")
        }
        return condition || ""
    }

    // HA gives wind_bearing in degrees (most integrations) or already as a
    // compass string.
    function compassLabel(bearing) {
        if (bearing === undefined || bearing === null || bearing === "") {
            return ""
        }
        var deg = parseFloat(bearing)
        if (isNaN(deg)) {
            return String(bearing)
        }
        var names = [qsTr("N"), qsTr("NE"), qsTr("E"), qsTr("SE"),
                     qsTr("S"), qsTr("SW"), qsTr("W"), qsTr("NW")]
        return names[Math.round((((deg % 360) + 360) % 360) / 45) % 8]
    }

    function formatTemperature(value, unit) {
        var num = parseFloat(value)
        if (isNaN(num)) {
            return ""
        }
        return num.toFixed(1) + (unit ? (" " + unit) : "")
    }

    function weatherDetails(st) {
        if (!st) {
            return ""
        }
        var a = st.attributes || {}
        var parts = []
        if (a.humidity !== undefined && a.humidity !== null) {
            //: Weather card, %1 = relative humidity in percent
            parts.push(qsTr("Humidity %1 %").arg(Math.round(a.humidity)))
        }
        if (a.wind_speed !== undefined && a.wind_speed !== null) {
            var wind = (Math.round(parseFloat(a.wind_speed) * 10) / 10)
                + (a.wind_speed_unit ? (" " + a.wind_speed_unit) : "")
            var dir = compassLabel(a.wind_bearing)
            //: Weather card, %1 = wind speed with unit and direction, e.g. "12 km/h SW"
            parts.push(qsTr("Wind %1").arg(dir.length > 0 ? wind + " " + dir : wind))
        }
        return parts.join(" · ")
    }

    function buildWeather(states) {
        var list = []
        for (var i = 0; i < states.length; i++) {
            if (states[i].entity_id.split(".")[0] === "weather") {
                list.push(states[i])
            }
        }
        weatherStates = list
        chooseWeather()
    }

    function chooseWeather() {
        var chosen = null
        for (var i = 0; i < weatherStates.length; i++) {
            if (weatherStates[i].entity_id === weatherEntitySetting.value) {
                chosen = weatherStates[i]
                break
            }
        }
        if (!chosen && weatherStates.length > 0) {
            chosen = weatherStates[0]
        }
        weather = chosen
        forecastModel.clear()
        if (!chosen) {
            coverWeatherTextSetting.value = ""
            return
        }
        var a = chosen.attributes || {}
        var temp = formatTemperature(a.temperature, a.temperature_unit)
        var cond = weatherConditionLabel(chosen.state)
        coverWeatherTextSetting.value = temp.length > 0 ? temp + ", " + cond : cond
        loadForecast(chosen)
    }

    // Modern HA (2024.3+) only returns forecasts via the weather.get_forecasts
    // service; attributes.forecast is the pre-2024 fallback. supported_features:
    // 1 = daily, 2 = hourly, 4 = twice daily. Hourly-only entities get no row
    // (unless the old attribute is there).
    function loadForecast(st) {
        var attrs = st.attributes || {}
        var features = attrs.supported_features || 0
        var type = ""
        if ((features & 1) || !(features & 6)) {
            type = "daily"
        } else if (features & 4) {
            type = "twice_daily"
        }
        if (type.length === 0) {
            applyForecast(attrs.forecast)
            return
        }
        var profileId = Credentials.activeProfileId
        var entityId = st.entity_id
        HaApi.callServiceWithResponse(Credentials.baseUrl, Credentials.token,
            "weather", "get_forecasts", { entity_id: entityId, type: type },
            function (response) {
                if (profileId !== Credentials.activeProfileId || !weather || weather.entity_id !== entityId) return
                var entry = response[entityId]
                if (entry && entry.forecast && entry.forecast.length > 0) {
                    applyForecast(entry.forecast)
                } else {
                    applyForecast(attrs.forecast)
                }
            },
            function (error) {
                if (profileId !== Credentials.activeProfileId || !weather || weather.entity_id !== entityId) return
                applyForecast(attrs.forecast)
            })
    }

    // Up to five entries from today on; the row hides itself when empty.
    function applyForecast(list) {
        forecastModel.clear()
        if (!list || !list.length) {
            return
        }
        var today = new Date()
        today.setHours(0, 0, 0, 0)
        for (var i = 0; i < list.length && forecastModel.count < 5; i++) {
            var f = list[i]
            // twice_daily: keep the day part only.
            if (f.is_daytime === false) {
                continue
            }
            var date = new Date(f.datetime)
            if (isNaN(date.getTime())) {
                continue
            }
            var day = new Date(date.getTime())
            day.setHours(0, 0, 0, 0)
            if (day.getTime() < today.getTime()) {
                continue
            }
            var high = parseFloat(f.temperature)
            var low = parseFloat(f.templow)
            var temps = isNaN(high) ? "" : Math.round(high) + "°"
            if (!isNaN(low)) {
                temps += (temps.length > 0 ? " / " : "") + Math.round(low) + "°"
            }
            forecastModel.append({
                //: Weather forecast column for the current day
                dayLabel: day.getTime() === today.getTime() ? qsTr("Today") : Qt.formatDate(date, "ddd"),
                temps: temps,
                condition: weatherConditionLabel(f.condition)
            })
        }
    }

    function openWeatherPicker() {
        var picker = pageStack.push(Qt.resolvedUrl("../pages/EntityPickerPage.qml"), {
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
                entityId: st.entity_id,
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

            entriesModel.append({ rowType: "header", room: roomName, count: matches.length, entityId: "", friendlyName: "", value: "", unit: "" })
            for (var m = 0; m < matches.length; m++) {
                var e = matches[m]
                e.rowType = "entity"
                e.room = roomName
                e.count = 0
                entriesModel.append(e)
            }
        }
    }

    // S. RoomsView.qml: ohne diese Schranke dreht der BusyIndicator endlos
    // weiter, wenn Home Assistant nicht erreichbar ist.
    Timer {
        id: requestTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            busyIndicator.running = false
            errorText = qsTr("Home Assistant is not responding.")
        }
    }

    function refresh() {
        if (!configured) {
            return
        }
        errorText = ""
        busyIndicator.running = true
        requestTimeout.restart()
        // Answers from the previous instance after a profile switch are
        // dropped (the profile-switch handler below cleared the view).
        var profileId = Credentials.activeProfileId
        HaApi.getStates(Credentials.baseUrl, Credentials.token,
            function (states) {
                if (profileId !== Credentials.activeProfileId) return
                buildWeather(states || [])
                HaApi.getAreaMap(Credentials.baseUrl, Credentials.token,
                    function (areaPairs) {
                        if (profileId !== Credentials.activeProfileId) return
                        requestTimeout.stop()
                        busyIndicator.running = false
                        buildEntries(states, areaPairs)
                    },
                    function (error) {
                        if (profileId !== Credentials.activeProfileId) return
                        // Area-Zuordnung ist ein Komfort-Feature, kein Muss --
                        // bei Fehlschlag landet einfach alles unter "Ohne
                        // Raum" statt die Seite zu blockieren.
                        requestTimeout.stop()
                        busyIndicator.running = false
                        buildEntries(states, [])
                    })
            },
            function (error) {
                if (profileId !== Credentials.activeProfileId) return
                requestTimeout.stop()
                busyIndicator.running = false
                errorText = error.hint || qsTr("Unknown error")
            })
    }

    // Lädt erst beim ersten Sichtbarwerden und erst mit Zugangsdaten --
    // Begründung s. RoomsView.qml.
    function loadIfNeeded() {
        if (viewActive && configured && !loadedOnce) {
            loadedOnce = true
            refresh()
        }
    }

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

    // Another Home Assistant instance (profile switch): clear and load again
    // lazily, like on startup -- see RoomsView.qml.
    Connections {
        target: Credentials
        onActiveProfileIdChanged: {
            requestTimeout.stop()
            busyIndicator.running = false
            errorText = ""
            entriesModel.clear()
            forecastModel.clear()
            weatherStates = []
            weather = null
            expandedRooms = ({})
            loadedOnce = false
            loadIfNeeded()
        }
    }

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
                    // Tapping the card does the same; the menu entry only
                    // shows up when there is something to choose.
                    visible: root.weatherStates.length > 1
                    text: qsTr("Choose weather")
                    onClicked: root.openWeatherPicker()
                }
                MenuItem {
                    text: qsTr("Refresh")
                    onClicked: root.refreshRequested()
                }
            }

            PageHeader {
                title: qsTr("Sensors")
            }

            BackgroundItem {
                id: weatherCard
                visible: root.weather !== null
                width: parent.width
                height: visible ? weatherColumn.height + 2 * Theme.paddingMedium : 0
                onClicked: root.openWeatherPicker()

                Column {
                    id: weatherColumn
                    x: Theme.horizontalPageMargin
                    y: Theme.paddingMedium
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    spacing: Theme.paddingSmall

                    Item {
                        width: parent.width
                        height: Math.max(nowColumn.height, tempLabel.height)

                        Column {
                            id: nowColumn
                            anchors.left: parent.left
                            anchors.right: tempLabel.left
                            anchors.rightMargin: Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter

                            Label {
                                width: parent.width
                                truncationMode: TruncationMode.Fade
                                text: root.weather ? root.weatherConditionLabel(root.weather.state) : ""
                                font.pixelSize: Theme.fontSizeLarge
                                color: weatherCard.highlighted ? Theme.highlightColor : Theme.primaryColor
                            }
                            Label {
                                width: parent.width
                                truncationMode: TruncationMode.Fade
                                text: root.weather ? (root.weather.attributes.friendly_name || root.weather.entity_id) : ""
                                font.pixelSize: Theme.fontSizeExtraSmall
                                color: Theme.secondaryHighlightColor
                            }
                        }
                        Label {
                            id: tempLabel
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.weather ? root.formatTemperature(root.weather.attributes.temperature,
                                                                        root.weather.attributes.temperature_unit) : ""
                            font.pixelSize: Theme.fontSizeExtraLarge
                            color: Theme.highlightColor
                        }
                    }

                    Label {
                        visible: text.length > 0
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: root.weatherDetails(root.weather)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryColor
                    }

                    Row {
                        visible: forecastModel.count > 0
                        width: parent.width

                        Repeater {
                            model: forecastModel

                            Column {
                                width: weatherColumn.width / Math.max(1, forecastModel.count)

                                Label {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    truncationMode: TruncationMode.Fade
                                    text: model.dayLabel
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    color: Theme.highlightColor
                                }
                                Label {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    truncationMode: TruncationMode.Fade
                                    text: model.temps
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    color: Theme.primaryColor
                                }
                                Label {
                                    x: Theme.paddingSmall / 2
                                    width: parent.width - Theme.paddingSmall
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    truncationMode: TruncationMode.Elide
                                    text: model.condition
                                    font.pixelSize: Theme.fontSizeTiny
                                    color: Theme.secondaryColor
                                }
                            }
                        }
                    }
                }
            }
        }

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
            // Below the weather card when there is one.
            verticalOffset: weather !== null && listView.headerItem ? listView.headerItem.height / 2 : 0
            enabled: configured && errorText.length === 0 && entriesModel.count === 0 && !busyIndicator.running
            text: qsTr("No sensors")
            hintText: qsTr("No sensor is reporting a value right now. Pull down to refresh.")
        }

        delegate: ListItem {
            id: delegateItem
            width: listView.width
            readonly property bool isHeader: model.rowType === "header"
            readonly property bool rowVisible: isHeader || expandedRooms[model.room] === true
            contentHeight: rowVisible ? (isHeader ? Theme.itemSizeSmall : Theme.itemSizeMedium) : 0
            visible: rowVisible
            clip: true

            onClicked: {
                if (isHeader) {
                    toggleRoom(model.room)
                } else {
                    // Only numeric sensors make it into this list (see
                    // buildEntries), so every row can show a graph.
                    pageStack.push(Qt.resolvedUrl("../pages/SensorHistoryPage.qml"), {
                        entityId: model.entityId,
                        entityName: model.friendlyName,
                        unit: model.unit,
                        currentValue: model.value
                    })
                }
            }

            // Same header look as RoomsView.qml; Loader so the sensor rows
            // don't each carry a header item.
            Loader {
                anchors.fill: parent
                active: delegateItem.isHeader
                sourceComponent: Component {
                    RoomSectionHeader {
                        title: model.room
                        count: model.count
                        expanded: expandedRooms[model.room] === true
                        highlighted: delegateItem.highlighted
                    }
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
