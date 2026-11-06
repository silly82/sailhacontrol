import QtQuick 2.0
import Nemo.DBus 2.0

// Reads the phone's own battery/connectivity state for the mobile_app
// device-status sensors (see harbour-hacontrol.qml's updateDeviceSensors()).
// Service names, object paths and method names verified directly against
// the running system (SDK emulator, `dbus-send --system ...`), not guessed:
// SailfishOS uses com.nokia.mce for battery/charger state (no UPower) and
// net.connman for connectivity -- both confirmed present via
// org.freedesktop.DBus.ListNames, method signatures via Introspect.
Item {
    id: root

    // battery_level: -1 if unknown (e.g. no real battery, seen on the SDK
    // emulator) -- caller should skip sending that sensor value in that case.
    // charging: true/false. connectionType: "wifi"/"ethernet"/"cellular"/"offline".
    // wifiSsid: SSID of the connected Wi-Fi, "" if none. wifiStrength: 0-100,
    // -1 if not connected/unknown. freeStorageGb: free space in the home
    // directory's filesystem, -1 if unknown (via the C++ DeviceInfo object).
    function query(callback) {
        var result = { batteryLevel: -1, charging: false, connectionType: "offline",
                       wifiSsid: "", wifiStrength: -1,
                       freeStorageGb: DeviceInfo.freeStorageGb() }
        var pending = 3

        function done() {
            pending -= 1
            if (pending === 0) {
                callback(result)
            }
        }

        mce.call("get_battery_level", [], function (level) {
            result.batteryLevel = level
            done()
        }, function (error) { done() })

        mce.call("get_charger_state", [], function (state) {
            result.charging = (state === "on")
            done()
        }, function (error) { done() })

        // GetServices() returns an ordered array of (path, properties)
        // structs, highest-priority/default connection first (verified: the
        // emulator's wired connection came back as element 0 with
        // Type "ethernet"). An empty array (or connman not reachable) means
        // no active connection.
        connman.call("GetServices", [], function (services) {
            if (services && services.length > 0 && services[0].length > 1) {
                var props = services[0][1]
                result.connectionType = props.Type || "offline"
            }
            // Wi-Fi may be connected without being the default route, so
            // look for any connected wifi service rather than only element 0.
            // For wifi services connman's Name property is the SSID and
            // Strength the signal strength in percent (0-100).
            for (var i = 0; services && i < services.length; i++) {
                var p = services[i].length > 1 ? services[i][1] : null
                if (p && p.Type === "wifi" && (p.State === "ready" || p.State === "online")) {
                    result.wifiSsid = p.Name || ""
                    result.wifiStrength = (p.Strength !== undefined) ? Number(p.Strength) : -1
                    break
                }
            }
            done()
        }, function (error) { done() })
    }

    DBusInterface {
        id: mce
        service: "com.nokia.mce"
        path: "/com/nokia/mce/request"
        iface: "com.nokia.mce.request"
        bus: DBus.SystemBus
    }

    DBusInterface {
        id: connman
        service: "net.connman"
        path: "/"
        iface: "net.connman.Manager"
        bus: DBus.SystemBus
    }
}
