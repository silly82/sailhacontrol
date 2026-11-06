import QtQuick 2.0
import Sailfish.Silica 1.0
import "../lib/HaApi.js" as HaApi

// All of Home Assistant's to-do lists (todo.* entities, e.g. the Shopping
// List integration or Local To-do), opened from RoomsView.qml's pull-down
// menu. A todo entity's state is the number of open items -- shown as a
// count. Tap opens TodoListPage.qml with the items of that list.
Page {
    id: page

    allowedOrientations: Orientation.All

    // RoomsView.qml (liveStateReceived) -- keeps the open counts current and
    // is passed on to TodoListPage.qml. May be null (then no live updates).
    property var stateSource: null

    readonly property bool configured: Credentials.baseUrl.length > 0 && Credentials.token.length > 0
    property bool loading: false
    property bool loadedOnce: false
    property string errorText: ""

    function countLabel(state) {
        var n = parseInt(state, 10)
        if (state === "unavailable") {
            return qsTr("Unavailable")
        }
        if (isNaN(n)) {
            return state
        }
        return n === 0 ? qsTr("Nothing open") : qsTr("%n open", "to-do items", n)
    }

    function refresh() {
        if (!configured) {
            return
        }
        errorText = ""
        loading = true
        requestTimeout.restart()
        HaApi.getStates(Credentials.baseUrl, Credentials.token,
            function (states) {
                requestTimeout.stop()
                loading = false
                loadedOnce = true
                var list = []
                states = states || []
                for (var i = 0; i < states.length; i++) {
                    var st = states[i]
                    if (!st.entity_id || st.entity_id.indexOf("todo.") !== 0) {
                        continue
                    }
                    list.push({
                        entityId: st.entity_id,
                        name: (st.attributes && st.attributes.friendly_name) || st.entity_id,
                        value: st.state || ""
                    })
                }
                list.sort(function (a, b) { return a.name.localeCompare(b.name) })
                listsModel.clear()
                for (var j = 0; j < list.length; j++) {
                    listsModel.append(list[j])
                }
            },
            function (error) {
                requestTimeout.stop()
                loading = false
                errorText = error.hint || qsTr("Unknown error")
            })
    }

    Timer {
        id: requestTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            loading = false
            errorText = qsTr("Home Assistant is not responding.")
        }
    }

    Connections {
        target: stateSource
        onLiveStateReceived: {
            if (!newState || changedEntityId.indexOf("todo.") !== 0) {
                return
            }
            for (var i = 0; i < listsModel.count; i++) {
                if (listsModel.get(i).entityId === changedEntityId) {
                    listsModel.setProperty(i, "value", newState.state || "")
                    return
                }
            }
        }
    }

    Component.onCompleted: refresh()
    onConfiguredChanged: if (!loadedOnce) refresh()

    ListModel {
        id: listsModel
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: listsModel

        PullDownMenu {
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.refresh()
            }
        }

        header: PageHeader {
            title: qsTr("To-do lists")
        }

        delegate: ListItem {
            id: delegateItem
            width: listView.width
            contentHeight: Theme.itemSizeMedium
            onClicked: pageStack.push(Qt.resolvedUrl("TodoListPage.qml"), {
                entityId: model.entityId,
                entityName: model.name,
                entityState: model.value,
                stateSource: page.stateSource
            })

            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter

                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: model.name
                    color: delegateItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: page.countLabel(model.value)
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: delegateItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
        }

        ViewPlaceholder {
            flickable: listView
            enabled: !configured
            text: qsTr("Not configured yet")
            hintText: qsTr("Enter the Home Assistant URL and a long-lived access token in Settings first.")
        }
        ViewPlaceholder {
            flickable: listView
            enabled: configured && errorText.length > 0 && !loading
            text: qsTr("No connection")
            hintText: errorText
        }
        ViewPlaceholder {
            flickable: listView
            enabled: configured && loadedOnce && !loading && errorText.length === 0 && listsModel.count === 0
            text: qsTr("No to-do lists")
            hintText: qsTr("Home Assistant has no to-do list entities. Add e.g. the Shopping List or Local To-do integration.")
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: page.loading
    }
}
