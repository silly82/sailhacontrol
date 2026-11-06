import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import "../lib/HaApi.js" as HaApi

// Picks what the cover's CoverAction does (opened from SettingsPage.qml).
// An empty coverTargetId means "last used light" -- the v0.52 behaviour, fed
// by RoomsView.qml's coverLastLightId. Otherwise CoverPage.qml triggers the
// stored entity directly: scene/script -> turn_on, light/switch -> toggle.
// Id, name and domain are stored together so the cover can show the name and
// pick its icon without asking HA (it never polls on its own).
Page {
    id: page

    allowedOrientations: Orientation.All

    readonly property bool configured: Credentials.baseUrl.length > 0 && Credentials.token.length > 0
    readonly property var targetDomains: ["scene", "script", "light", "switch"]
    property bool loading: false
    property bool loadedOnce: false
    property string errorText: ""
    // Full candidate list from the last getStates, already sorted; the
    // ListModel only holds the rows matching the current search text.
    property var allCandidates: []

    ConfigurationValue {
        id: targetIdSetting
        key: "/apps/harbour-hacontrol/coverTargetId"
        defaultValue: ""
    }
    ConfigurationValue {
        id: targetNameSetting
        key: "/apps/harbour-hacontrol/coverTargetName"
        defaultValue: ""
    }
    ConfigurationValue {
        id: targetDomainSetting
        key: "/apps/harbour-hacontrol/coverTargetDomain"
        defaultValue: ""
    }

    function domainLabel(domain) {
        switch (domain) {
        case "scene": return qsTr("Scenes")
        case "script": return qsTr("Scripts")
        case "light": return qsTr("Lights")
        case "switch": return qsTr("Switches")
        }
        return domain
    }

    function select(entityId, name, domain) {
        targetIdSetting.value = entityId
        targetNameSetting.value = name
        targetDomainSetting.value = domain
        pageStack.pop()
    }

    function buildCandidates(states) {
        var list = []
        for (var i = 0; i < states.length; i++) {
            var st = states[i]
            var domain = st.entity_id.split(".")[0]
            if (targetDomains.indexOf(domain) < 0) {
                continue
            }
            list.push({
                entityId: st.entity_id,
                name: (st.attributes && st.attributes.friendly_name) || st.entity_id,
                domain: domain
            })
        }
        list.sort(function (a, b) {
            var d = targetDomains.indexOf(a.domain) - targetDomains.indexOf(b.domain)
            return d !== 0 ? d : a.name.localeCompare(b.name)
        })
        allCandidates = list
        applyFilter()
    }

    function applyFilter() {
        var needle = searchText.toLowerCase()
        candidatesModel.clear()
        for (var i = 0; i < allCandidates.length; i++) {
            var c = allCandidates[i]
            if (needle.length > 0
                    && c.name.toLowerCase().indexOf(needle) < 0
                    && c.entityId.toLowerCase().indexOf(needle) < 0) {
                continue
            }
            candidatesModel.append(c)
        }
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
                buildCandidates(states || [])
            },
            function (error) {
                requestTimeout.stop()
                loading = false
                errorText = error.hint || qsTr("Unknown error")
            })
    }

    property string searchText: ""
    onSearchTextChanged: filterDelay.restart()

    // Same limit as the sub-views: without it the BusyIndicator would spin
    // forever when Home Assistant is unreachable.
    Timer {
        id: requestTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            loading = false
            errorText = qsTr("Home Assistant is not responding.")
        }
    }
    // Rebuilding the model on every keystroke is cheap for a few hundred
    // rows, but a short delay keeps fast typing from doing it repeatedly.
    Timer {
        id: filterDelay
        interval: 200
        repeat: false
        onTriggered: applyFilter()
    }

    Component.onCompleted: refresh()
    onConfiguredChanged: if (!loadedOnce) refresh()

    ListModel {
        id: candidatesModel
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: candidatesModel

        PullDownMenu {
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.refresh()
            }
        }

        header: Column {
            width: listView.width

            PageHeader {
                title: qsTr("Cover action")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: qsTr("Choose what the button on the app cover does. Scenes and scripts are run, lights and switches are toggled.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            ListItem {
                id: lastLightItem
                width: parent.width
                contentHeight: Theme.itemSizeMedium
                onClicked: page.select("", "", "")

                Column {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter

                    Label {
                        width: parent.width
                        truncationMode: TruncationMode.Fade
                        text: qsTr("Last used light")
                        color: targetIdSetting.value.length === 0 || lastLightItem.highlighted
                            ? Theme.highlightColor : Theme.primaryColor
                    }
                    Label {
                        width: parent.width
                        truncationMode: TruncationMode.Fade
                        text: qsTr("The light you last switched in the app (default)")
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                    }
                }
            }

            SearchField {
                id: searchField
                width: parent.width
                placeholderText: qsTr("Search scenes, scripts, lights, switches")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onTextChanged: page.searchText = text
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }
        }

        section.property: "domain"
        section.delegate: SectionHeader {
            text: page.domainLabel(section)
        }

        delegate: ListItem {
            id: delegateItem
            width: listView.width
            contentHeight: Theme.itemSizeSmall
            readonly property bool selected: model.entityId === targetIdSetting.value
            onClicked: page.select(model.entityId, model.name, model.domain)

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                truncationMode: TruncationMode.Fade
                text: model.name
                color: delegateItem.selected || delegateItem.highlighted
                    ? Theme.highlightColor : Theme.primaryColor
            }
        }

        ViewPlaceholder {
            flickable: listView
            // Der Listen-Header (Erklärtext, Standard-Eintrag, Suche) ist
            // hoch -- ohne Versatz läge der Platzhalter darüber.
            verticalOffset: listView.headerItem ? listView.headerItem.height + Theme.itemSizeSmall : 0
            enabled: !configured
            text: qsTr("Not configured yet")
            hintText: qsTr("Enter the Home Assistant URL and a long-lived access token in Settings first.")
        }
        ViewPlaceholder {
            flickable: listView
            // Der Listen-Header (Erklärtext, Standard-Eintrag, Suche) ist
            // hoch -- ohne Versatz läge der Platzhalter darüber.
            verticalOffset: listView.headerItem ? listView.headerItem.height + Theme.itemSizeSmall : 0
            enabled: configured && errorText.length > 0 && !loading
            text: qsTr("No connection")
            hintText: errorText
        }
        ViewPlaceholder {
            flickable: listView
            // Der Listen-Header (Erklärtext, Standard-Eintrag, Suche) ist
            // hoch -- ohne Versatz läge der Platzhalter darüber.
            verticalOffset: listView.headerItem ? listView.headerItem.height + Theme.itemSizeSmall : 0
            enabled: configured && loadedOnce && !loading && errorText.length === 0 && candidatesModel.count === 0
            text: page.searchText.length > 0 ? qsTr("No matches") : qsTr("Nothing to choose from")
            hintText: page.searchText.length > 0
                ? qsTr("No scene, script, light or switch matches the search.")
                : qsTr("Home Assistant has no scenes, scripts, lights or switches.")
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: page.loading
    }
}
