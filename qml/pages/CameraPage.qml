import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import "../lib/HaApi.js" as HaApi

// Standbild einer camera-Entity, geöffnet per Tap in RoomsView.qml.
//
// Auth: QMLs Image kann keinen Authorization-Header senden. HA gibt jeder
// Kamera ein access_token-Attribut, mit dem /api/camera_proxy/<entity_id>
// ?token=... ohne Bearer-Header funktioniert. Das Token rotiert (etwa alle
// 5 min) -- es kommt deshalb immer aus den Live-Attributen (stateSource,
// wie bei CoverDetailPage.qml); schlägt ein Laden fehl, wird der Zustand
// einmal per REST nachgeholt und erneut versucht.
//
// Das Token (und damit jede Snapshot-URL) wird nie geloggt.
//
// Doppelpuffer: zwei Image-Items, das neue Bild wird erst sichtbar, wenn es
// Image.Ready erreicht -- kein Flackern beim Nachladen.
Page {
    id: page

    allowedOrientations: Orientation.All

    property string entityId
    property string entityName
    // HAs "state" (idle/recording/streaming/unavailable).
    property string entityState: ""
    property var attributes: ({})
    // RoomsView.qml (liveStateReceived) -- liefert u.a. das rotierte
    // access_token. Darf null sein.
    property var stateSource: null

    ConfigurationValue {
        id: intervalSetting
        key: "/apps/harbour-hacontrol/cameraRefreshSeconds"
        defaultValue: 5
    }
    readonly property var intervalChoices: [2, 5, 10, 30]
    readonly property int refreshSeconds: Math.max(1, Number(intervalSetting.value) || 5)

    readonly property string accessToken: attributes && attributes.access_token ? String(attributes.access_token) : ""
    // Nur nachladen, solange die Seite vorne ist und die App im
    // Vordergrund -- sonst steht der Timer.
    readonly property bool refreshActive: status === PageStatus.Active
        && Qt.application.state === Qt.ApplicationActive

    // 0: imageA ist vorne, 1: imageB.
    property int frontIndex: 0
    property bool hasFrame: false
    property bool loadFailed: false
    // Pro Fehlerserie nur einmal den Zustand (Token) per REST nachholen;
    // zurückgesetzt beim nächsten erfolgreichen Bild.
    property bool tokenRetried: false
    property bool refetching: false

    function cameraStateLabel(state) {
        switch (state) {
        case "idle": return qsTr("Idle")
        case "recording": return qsTr("Recording")
        case "streaming": return qsTr("Streaming")
        case "unavailable": return qsTr("Unavailable")
        default: return qsTr("Camera")
        }
    }

    function frontImage() {
        return frontIndex === 0 ? imageA : imageB
    }

    function backImage() {
        return frontIndex === 0 ? imageB : imageA
    }

    // Credentials.baseUrl bei jedem Aufruf neu lesen -- es ist die
    // *effektive* URL und kann zwischen intern/extern wechseln.
    // &t= gegen Caching, sonst lädt Image dieselbe URL nicht neu.
    function snapshotUrl() {
        var base = Credentials.baseUrl
        if (!base || accessToken.length === 0) {
            return ""
        }
        return base.replace(/\/+$/, "") + "/api/camera_proxy/" + encodeURIComponent(entityId)
            + "?token=" + encodeURIComponent(accessToken) + "&t=" + Date.now()
    }

    function loadFrame() {
        var back = backImage()
        if (refetching || back.status === Image.Loading) {
            return
        }
        var url = snapshotUrl()
        if (url.length === 0) {
            handleLoadError()
            return
        }
        back.source = url
        loadTimeout.restart()
    }

    function handleLoadError() {
        if (!tokenRetried) {
            tokenRetried = true
            refetchState()
        } else {
            loadFailed = true
        }
    }

    function refetchState() {
        refetching = true
        refetchTimeout.restart()
        HaApi.getState(Credentials.baseUrl, Credentials.token, entityId,
            function (newState) {
                if (!refetching) {
                    return  // schon per Timeout aufgegeben
                }
                refetchTimeout.stop()
                refetching = false
                if (newState) {
                    entityState = newState.state || ""
                    attributes = newState.attributes || {}
                }
                if (refreshActive) {
                    loadFrame()
                }
            },
            function () {
                if (!refetching) {
                    return
                }
                refetchTimeout.stop()
                refetching = false
                loadFailed = true
            })
    }

    function frameStatusChanged(img) {
        if (img !== backImage()) {
            return
        }
        if (img.status === Image.Ready) {
            loadTimeout.stop()
            frontIndex = (img === imageA) ? 0 : 1
            hasFrame = true
            loadFailed = false
            tokenRetried = false
        } else if (img.status === Image.Error) {
            loadTimeout.stop()
            img.source = ""
            handleLoadError()
        }
    }

    function manualRefresh() {
        tokenRetried = false
        loadFrame()
    }

    onRefreshActiveChanged: if (refreshActive) loadFrame()

    Timer {
        id: refreshTimer
        interval: refreshSeconds * 1000
        repeat: true
        running: refreshActive
        onTriggered: loadFrame()
    }

    // Image hat kein eigenes Timeout -- bei unerreichbarem Host bliebe es
    // bis zum TCP-Timeout in Loading und der BusyIndicator drehte endlos.
    Timer {
        id: loadTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            var back = backImage()
            if (back.status === Image.Loading) {
                back.source = ""
                handleLoadError()
            }
        }
    }

    // HaApi.request() hat kein Timeout.
    Timer {
        id: refetchTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            refetching = false
            loadFailed = true
        }
    }

    Connections {
        target: stateSource
        onLiveStateReceived: {
            if (changedEntityId !== page.entityId || !newState) {
                return
            }
            page.entityState = newState.state || ""
            page.attributes = newState.attributes || {}
        }
    }

    SilicaFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Refresh")
                onClicked: manualRefresh()
            }
        }

        VerticalScrollDecorator {}

        Column {
            id: column
            width: page.width

            PageHeader {
                title: entityName
                description: cameraStateLabel(entityState)
            }

            Item {
                id: frameArea
                readonly property real aspect: frontImage().implicitWidth > 0
                    ? frontImage().implicitHeight / frontImage().implicitWidth : 9 / 16
                width: parent.width
                height: Math.min(width * aspect, page.height)

                Image {
                    id: imageA
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    smooth: true
                    visible: hasFrame && frontIndex === 0
                    onStatusChanged: frameStatusChanged(imageA)
                }
                Image {
                    id: imageB
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    smooth: true
                    visible: hasFrame && frontIndex === 1
                    onStatusChanged: frameStatusChanged(imageB)
                }

                BusyIndicator {
                    anchors.centerIn: parent
                    size: BusyIndicatorSize.Large
                    running: !hasFrame && !loadFailed
                }
            }

            // Ein altes Bild bleibt stehen, wenn nur das Nachladen scheitert.
            Label {
                visible: hasFrame && loadFailed
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("The image could not be refreshed.")
                color: Theme.errorColor
            }

            ComboBox {
                width: parent.width
                label: qsTr("Refresh interval")
                currentIndex: Math.max(0, intervalChoices.indexOf(refreshSeconds))
                menu: ContextMenu {
                    // Gleiche Reihenfolge wie intervalChoices.
                    MenuItem { text: qsTr("%1 s").arg(2) }
                    MenuItem { text: qsTr("%1 s").arg(5) }
                    MenuItem { text: qsTr("%1 s").arg(10) }
                    MenuItem { text: qsTr("%1 s").arg(30) }
                }
                onCurrentIndexChanged: {
                    var seconds = intervalChoices[currentIndex]
                    if (seconds !== undefined && seconds !== refreshSeconds) {
                        intervalSetting.value = seconds
                    }
                }
            }
        }

        ViewPlaceholder {
            flickable: flickable
            enabled: loadFailed && !hasFrame
            text: qsTr("Could not load the image")
            hintText: entityState === "unavailable"
                ? qsTr("The camera is unavailable.")
                : qsTr("Pull down to try again.")
        }
    }
}
