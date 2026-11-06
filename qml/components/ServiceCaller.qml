import QtQuick 2.0
import "../lib/HaApi.js" as HaApi

// Service calls of the entity detail pages with shared busy/error state:
// busy drives DetailPageHeader.busy, errorText DetailErrorLabel.text.
// serviceData is passed through untouched and never logged (AlarmPage puts
// the alarm code in it).
Item {
    id: caller

    property string errorText: ""
    property int pending: 0
    readonly property bool busy: pending > 0

    function call(domain, service, serviceData, onSuccess) {
        errorText = ""
        pending++
        timeout.restart()
        HaApi.callService(Credentials.baseUrl, Credentials.token, domain, service, serviceData,
            function () {
                finish()
                if (onSuccess) {
                    onSuccess()
                }
            },
            function (error) {
                finish()
                // Only the hint (HTTP status), not error.detail -- the
                // response text does not belong in the UI.
                errorText = (error && error.hint) || qsTr("Unknown error")
            })
    }

    function finish() {
        if (pending > 0) {
            pending--
        }
        if (pending === 0) {
            timeout.stop()
        }
    }

    // HaApi.request() has no timeout of its own; same limit as elsewhere.
    Timer {
        id: timeout
        interval: 15000
        repeat: false
        onTriggered: {
            caller.pending = 0
            caller.errorText = qsTr("Home Assistant is not responding.")
        }
    }
}
