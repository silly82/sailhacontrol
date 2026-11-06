import QtQuick 2.0
import Sailfish.Silica 1.0
import "../lib/HaApi.js" as HaApi
import "../components"

// Line chart of one numeric sensor's history, opened per tap from
// SensorsView.qml. Data comes from /api/history/period (HaApi.getHistory) and
// is drawn ONCE per data set (and on resize) into a plain QtQuick Canvas --
// no animation, nothing per frame. Non-numeric states (unavailable/unknown)
// are not drawn; the line is interrupted there instead of bridging the gap.
//
// Same layout as the other detail pages (see LightDetailPage.qml).
Page {
    id: page

    allowedOrientations: Orientation.All

    property string entityId
    property string entityName
    property string unit
    // Value from the sensor list, shown until the history has loaded (and
    // as "current" if the history has no numeric point at all).
    property string currentValue

    readonly property bool configured: Credentials.baseUrl.length > 0 && Credentials.token.length > 0
    readonly property var periodHours: [6, 24, 168]
    property int hours: 24

    property bool loading: false
    property bool loadedOnce: false
    property string errorText: ""
    // Guards against a slow response for a previous period overwriting a
    // newer one.
    property int requestSerial: 0

    // Current data set: [{t: ms, v: number or NaN}], sorted by time.
    property var points: []
    property real startMs: 0
    property real endMs: 0
    property bool hasData: false
    property real minValue: 0
    property real maxValue: 0
    property real lastValue: NaN
    // [{pos: 0..1, text}] -- time axis labels, computed with the data set.
    property var ticks: []

    function formatValue(num) {
        if (isNaN(num)) {
            return currentValue.length > 0 ? currentValue + (unit ? " " + unit : "") : "–"
        }
        return num.toFixed(1) + (unit ? " " + unit : "")
    }

    // HA sends e.g. "2026-11-06T09:41:12.345678+00:00". Parsed by hand
    // because the engine's Date.parse is not guaranteed to accept six
    // fractional digits or a "+00:00" offset.
    function parseTime(text) {
        var m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|([+-])(\d{2}):?(\d{2}))?$/.exec(text || "")
        if (!m) {
            return NaN
        }
        var ms = m[7] ? Math.round(parseFloat("0." + m[7]) * 1000) : 0
        var t = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6], ms)
        if (m[9]) {
            var offset = (+m[10] * 60 + +m[11]) * 60000
            t -= m[9] === "+" ? offset : -offset
        }
        return t
    }

    function computeTicks() {
        var stepHours = hours <= 6 ? 1 : (hours <= 24 ? 6 : 24)
        var d = new Date(startMs)
        if (stepHours >= 24) {
            d.setHours(0, 0, 0, 0)
            d.setDate(d.getDate() + 1)
        } else {
            d.setMinutes(0, 0, 0)
            d.setHours(d.getHours() + 1)
            while (d.getHours() % stepHours !== 0) {
                d.setHours(d.getHours() + 1)
            }
        }
        var list = []
        var span = endMs - startMs
        while (d.getTime() < endMs) {
            list.push({
                pos: (d.getTime() - startMs) / span,
                text: stepHours >= 24 ? Qt.formatDate(d, "ddd") : Qt.formatTime(d, "HH:mm")
            })
            if (stepHours >= 24) {
                d.setDate(d.getDate() + 1)
            } else {
                d.setHours(d.getHours() + stepHours)
            }
        }
        return list
    }

    function applyHistory(result, start, end) {
        var entries = (result && result.length > 0 && result[0]) ? result[0] : []
        var list = []
        var lo = Infinity
        var hi = -Infinity
        var last = NaN
        for (var i = 0; i < entries.length; i++) {
            var e = entries[i]
            var t = parseTime(e.last_changed || e.last_updated)
            if (isNaN(t)) {
                continue
            }
            // The first entry carries the state that was valid at the start
            // of the period and may be older than it.
            t = Math.max(t, start)
            var v = parseFloat(e.state)
            list.push({ t: t, v: v })
            if (!isNaN(v)) {
                lo = Math.min(lo, v)
                hi = Math.max(hi, v)
            }
            last = v
        }
        startMs = start
        endMs = end
        points = list
        hasData = lo !== Infinity
        minValue = hasData ? lo : 0
        maxValue = hasData ? hi : 0
        lastValue = last
        ticks = computeTicks()
        chart.requestPaint()
    }

    function load() {
        if (!configured) {
            return
        }
        var serial = ++requestSerial
        var end = new Date()
        var start = new Date(end.getTime() - hours * 3600000)
        errorText = ""
        loading = true
        requestTimeout.restart()
        HaApi.getHistory(Credentials.baseUrl, Credentials.token, entityId, start, end,
            function (result) {
                if (serial !== requestSerial) {
                    return
                }
                requestTimeout.stop()
                loading = false
                loadedOnce = true
                applyHistory(result, start.getTime(), end.getTime())
            },
            function (error) {
                if (serial !== requestSerial) {
                    return
                }
                requestTimeout.stop()
                loading = false
                hasData = false
                errorText = error.hint || qsTr("Unknown error")
            })
    }

    onHoursChanged: load()
    // Loaded once the push animation is over, so parsing a long history
    // doesn't stutter the page transition.
    onStatusChanged: if (status === PageStatus.Active && !loadedOnce && !loading) load()

    // Same limit as the sub-views (see RoomsView.qml).
    Timer {
        id: requestTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            requestSerial++
            loading = false
            hasData = false
            errorText = qsTr("Home Assistant is not responding.")
        }
    }

    SilicaFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.load()
            }
        }

        Column {
            id: column
            visible: configured
            width: page.width
            spacing: Theme.paddingLarge

            DetailPageHeader {
                title: page.entityName
                description: page.formatValue(page.lastValue)
                busy: page.loading
            }

            DetailStatusBlock {
                domain: "sensor"
                entityId: page.entityId
                unit: page.unit
                // Until the history has loaded, lastValue is NaN and
                // formatValue() falls back to the value from the list.
                value: page.formatValue(page.lastValue)
                detail: page.entityId
            }

            DetailErrorLabel {
                text: page.errorText
            }

            SectionHeader {
                text: qsTr("History")
            }

            ComboBox {
                width: parent.width
                label: qsTr("Period")
                currentIndex: 1
                menu: ContextMenu {
                    MenuItem { text: qsTr("6 hours") }
                    MenuItem { text: qsTr("24 hours") }
                    MenuItem { text: qsTr("7 days") }
                }
                onCurrentIndexChanged: page.hours = page.periodHours[currentIndex]
            }

            // Replaces a ViewPlaceholder, which would overlap the status
            // block.
            Column {
                visible: !page.loading && page.loadedOnce && page.errorText.length === 0 && !page.hasData
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingSmall

                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: qsTr("No history")
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeLarge
                }
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: qsTr("Home Assistant has no numeric values for this sensor in the selected period. Pull down to refresh.")
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Item {
                id: chartArea
                visible: page.hasData
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: Math.min(width * 0.6, page.height * 0.45)

                Canvas {
                    id: chart
                    anchors.fill: parent

                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onVisibleChanged: if (visible) requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        if (!page.hasData || width <= 0 || height <= 0) {
                            return
                        }
                        var w = width
                        var h = height
                        var lineWidth = Math.max(2, Math.round(Theme.paddingSmall / 3))
                        var pad = lineWidth
                        var lo = page.minValue
                        var hi = page.maxValue
                        if (hi - lo < 1e-9) {
                            // Flat line: centre it instead of dividing by 0.
                            var spread = Math.max(Math.abs(lo) * 0.05, 1)
                            lo -= spread
                            hi += spread
                        }
                        var t0 = page.startMs
                        var span = Math.max(1, page.endMs - page.startMs)
                        function xFor(t) { return (t - t0) / span * w }
                        function yFor(v) { return h - pad - (v - lo) / (hi - lo) * (h - 2 * pad) }

                        // Grid: top/bottom = max/min, verticals at the tick marks.
                        ctx.lineWidth = 1
                        ctx.strokeStyle = Theme.secondaryColor
                        ctx.globalAlpha = 0.3
                        ctx.beginPath()
                        ctx.moveTo(0, yFor(page.maxValue)); ctx.lineTo(w, yFor(page.maxValue))
                        ctx.moveTo(0, yFor(page.minValue)); ctx.lineTo(w, yFor(page.minValue))
                        for (var k = 0; k < page.ticks.length; k++) {
                            var tx = Math.round(page.ticks[k].pos * w) + 0.5
                            ctx.moveTo(tx, 0); ctx.lineTo(tx, h)
                        }
                        ctx.stroke()
                        ctx.globalAlpha = 1

                        // Data line. Points falling into the same pixel column
                        // are merged into one min/max stroke, so a chatty
                        // sensor costs at most ~3 segments per pixel.
                        ctx.lineWidth = lineWidth
                        ctx.lineJoin = "round"
                        ctx.lineCap = "round"
                        ctx.strokeStyle = Theme.highlightColor
                        ctx.beginPath()
                        var pts = page.points
                        var penDown = false
                        var col = -1, colMin = 0, colMax = 0, colLast = 0
                        function flush() {
                            if (col < 0) {
                                return
                            }
                            if (!penDown) {
                                ctx.moveTo(col, yFor(colMin))
                                penDown = true
                            } else {
                                ctx.lineTo(col, yFor(colMin))
                            }
                            if (colMax !== colMin) {
                                ctx.lineTo(col, yFor(colMax))
                            }
                            ctx.lineTo(col, yFor(colLast))
                            col = -1
                        }
                        for (var i = 0; i < pts.length; i++) {
                            var p = pts[i]
                            if (isNaN(p.v)) {
                                flush()
                                penDown = false
                                continue
                            }
                            var c = Math.round(xFor(p.t))
                            if (c !== col) {
                                flush()
                                col = c
                                colMin = colMax = colLast = p.v
                            } else {
                                colMin = Math.min(colMin, p.v)
                                colMax = Math.max(colMax, p.v)
                                colLast = p.v
                            }
                        }
                        // The last state is still valid now: hold it to the
                        // right edge (unless the sensor is unavailable).
                        var holdValue = col >= 0 ? colLast : NaN
                        flush()
                        if (penDown && !isNaN(holdValue)) {
                            ctx.lineTo(w, yFor(holdValue))
                        }
                        ctx.stroke()
                    }
                }

                Label {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.paddingSmall
                    text: page.formatValue(page.maxValue)
                    font.pixelSize: Theme.fontSizeTiny
                    color: Theme.secondaryColor
                }
                Label {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.paddingSmall
                    text: page.formatValue(page.minValue)
                    font.pixelSize: Theme.fontSizeTiny
                    color: Theme.secondaryColor
                }
            }

            // Time axis labels, centred under their grid line and kept
            // inside the chart's width.
            Item {
                visible: page.hasData
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: Theme.fontSizeTiny * 1.5

                Repeater {
                    model: page.ticks
                    Label {
                        text: modelData.text
                        font.pixelSize: Theme.fontSizeTiny
                        color: Theme.secondaryColor
                        x: Math.max(0, Math.min(parent.width - width, modelData.pos * parent.width - width / 2))
                    }
                }
            }

            DetailItem {
                visible: page.hasData
                label: qsTr("Minimum")
                value: page.formatValue(page.minValue)
            }
            DetailItem {
                visible: page.hasData
                label: qsTr("Maximum")
                value: page.formatValue(page.maxValue)
            }
        }

        ViewPlaceholder {
            flickable: flickable
            enabled: !configured
            text: qsTr("Not configured yet")
            hintText: qsTr("Enter the Home Assistant URL and a long-lived access token in Settings first.")
        }

        VerticalScrollDecorator {}
    }
}
