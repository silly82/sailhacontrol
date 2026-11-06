import QtQuick 2.0
import QtPositioning 5.4

// One-shot position fix for the opt-in mobile_app device_tracker (see
// harbour-hacontrol.qml's updateDeviceSensors() and the "Report location to
// Home Assistant" switch in SettingsPage.qml). The source only runs between
// query() and the first good fix (or the timeout), so GPS isn't kept on
// between the 10-minute reports. Never log coordinates.
Item {
    id: root

    // Fixes worse than this (in metres) are not reported.
    property real maxAccuracy: 500
    // How long to wait for a good enough fix before giving up.
    property int timeoutMs: 60000
    // A fix older than this (e.g. a cached one delivered right at start) is
    // ignored and the source keeps waiting for a fresh one.
    property int maxAgeMs: 5 * 60 * 1000

    property var _callbacks: []

    // callback(location) with location = { gps: [lat, lon], gps_accuracy,
    // altitude?, speed?, course? } in the shape HA's update_location webhook
    // expects -- or callback(null) if no usable fix arrived in time.
    function query(callback) {
        _callbacks.push(callback)
        if (_callbacks.length > 1) {
            return // a fix is already being waited for; share it
        }
        if (!source.valid) {
            _finish(null)
            return
        }
        timeout.restart()
        source.start()
    }

    function _finish(location) {
        timeout.stop()
        source.stop()
        var callbacks = _callbacks
        _callbacks = []
        for (var i = 0; i < callbacks.length; i++) {
            callbacks[i](location)
        }
    }

    function _check() {
        if (_callbacks.length === 0) {
            return
        }
        var pos = source.position
        if (!pos.latitudeValid || !pos.longitudeValid || !pos.horizontalAccuracyValid
                || pos.horizontalAccuracy > maxAccuracy) {
            return
        }
        if (pos.timestamp && (new Date() - pos.timestamp) > maxAgeMs) {
            return
        }
        var location = {
            gps: [pos.coordinate.latitude, pos.coordinate.longitude],
            gps_accuracy: Math.round(pos.horizontalAccuracy)
        }
        if (pos.altitudeValid && !isNaN(pos.coordinate.altitude)) {
            location.altitude = Math.round(pos.coordinate.altitude)
        }
        if (pos.verticalAccuracyValid) {
            location.vertical_accuracy = Math.round(pos.verticalAccuracy)
        }
        if (pos.speedValid) {
            location.speed = Math.round(pos.speed) // m/s
        }
        if (pos.directionValid) {
            location.course = Math.round(pos.direction)
        }
        _finish(location)
    }

    PositionSource {
        id: source
        active: false
        updateInterval: 1000
        preferredPositioningMethods: PositionSource.AllPositioningMethods
        onPositionChanged: root._check()
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError && root._callbacks.length > 0) {
                console.log("LocationProbe: position source error " + sourceError)
                root._finish(null)
            }
        }
    }

    Timer {
        id: timeout
        interval: root.timeoutMs
        onTriggered: {
            console.log("LocationProbe: no fix within " + root.maxAccuracy + " m in time, skipped")
            root._finish(null)
        }
    }
}
