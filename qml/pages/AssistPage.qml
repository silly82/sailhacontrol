import QtQuick 2.0
import Sailfish.Silica 1.0
import "../lib/HaApi.js" as HaApi

// Assist: text conversation with Home Assistant's default conversation agent
// (POST /api/conversation/process). Opened from the Rooms view PullDownMenu.
// The chat lives in memory only (last maxMessages bubbles) and is gone when
// the page is closed. conversation_id from each answer is sent with the next
// turn so HA keeps context ("and in the kitchen?").
//
// Layout: the list sits above an input row anchored to the page bottom.
// Silica's ApplicationWindow shrinks the page area while the virtual keyboard
// is open (_resizeContent / VirtualKeyboardObserver.panelSize), so the input
// row stays directly above the keyboard without a DockedPanel.
Page {
    id: page

    allowedOrientations: Orientation.All

    readonly property bool configured: Credentials.baseUrl.length > 0 && Credentials.token.length > 0
    readonly property int maxMessages: 50
    property string conversationId: ""
    property bool busy: false
    // Incremented per request and by "New conversation"; answers of an older
    // request (timed out, or from a cleared conversation) are dropped.
    property int requestGeneration: 0

    // HA parses the command in this language -- the phone's UI language.
    // "C"/unusual locale names are left out so HA falls back to its default.
    function phoneLanguage() {
        var lang = Qt.locale().name.split("_")[0].toLowerCase()
        return /^[a-z]{2,3}$/.test(lang) ? lang : ""
    }

    function trimMessages() {
        while (messagesModel.count > maxMessages) {
            messagesModel.remove(0)
        }
    }

    function appendMessage(fromUser, text, isError, details, pending) {
        messagesModel.append({
            fromUser: fromUser,
            text: text,
            isError: isError,
            details: details,
            pending: pending
        })
        trimMessages()
        scrollToEnd.restart()
    }

    // Replaces the trailing "…" bubble with the answer (or appends one if it
    // was already trimmed away).
    function finishPending(text, isError, details) {
        busy = false
        requestTimeout.stop()
        var last = messagesModel.count - 1
        if (last >= 0 && messagesModel.get(last).pending) {
            messagesModel.set(last, { text: text, isError: isError, details: details, pending: false })
            scrollToEnd.restart()
        } else {
            appendMessage(false, text, isError, details, false)
        }
    }

    function targetNames(list) {
        if (!Array.isArray(list)) {
            return ""
        }
        var names = []
        for (var i = 0; i < list.length; i++) {
            var t = list[i]
            if (t && t.name) {
                names.push(String(t.name))
            }
        }
        return names.join(", ")
    }

    function handleAnswer(result) {
        if (result && result.conversation_id) {
            conversationId = String(result.conversation_id)
        }
        var response = result && result.response ? result.response : null
        if (!response) {
            finishPending(qsTr("Unexpected answer from Home Assistant."), true, "")
            return
        }
        var speech = response.speech && response.speech.plain && response.speech.plain.speech
            ? String(response.speech.plain.speech) : ""
        var isError = response.response_type === "error"
        var details = isError ? "" : targetNames(response.data ? response.data.success : null)
        if (speech.length === 0) {
            speech = isError ? qsTr("Home Assistant did not understand that.") : qsTr("Done.")
        }
        finishPending(speech, isError, details)
    }

    function send(rawText) {
        var text = rawText.trim()
        if (text.length === 0 || busy || !configured) {
            return false
        }
        appendMessage(true, text, false, "", false)
        appendMessage(false, "", false, "", true)
        busy = true
        requestGeneration += 1
        var generation = requestGeneration
        requestTimeout.restart()
        HaApi.conversationProcess(Credentials.baseUrl, Credentials.token,
            text, phoneLanguage(), conversationId,
            function (result) {
                if (generation !== requestGeneration) {
                    return
                }
                handleAnswer(result)
            },
            function (error) {
                if (generation !== requestGeneration) {
                    return
                }
                finishPending((error && error.hint) || qsTr("Unknown error"), true, "")
            })
        return true
    }

    function newConversation() {
        requestGeneration += 1
        requestTimeout.stop()
        busy = false
        conversationId = ""
        messagesModel.clear()
    }

    Timer {
        id: requestTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            // Drop a late answer -- the bubble already shows the timeout.
            page.requestGeneration += 1
            page.finishPending(qsTr("Home Assistant is not responding."), true, "")
        }
    }

    // Let the ListView lay out the new delegate (or its new height) first.
    Timer {
        id: scrollToEnd
        interval: 0
        repeat: false
        onTriggered: listView.positionViewAtEnd()
    }

    ListModel {
        id: messagesModel
    }

    SilicaListView {
        id: listView
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: inputRow.top
        }
        clip: true
        model: messagesModel
        spacing: Theme.paddingMedium
        // Keyboard opening shrinks the list -- keep the latest bubble visible.
        onHeightChanged: scrollToEnd.restart()

        PullDownMenu {
            MenuItem {
                text: qsTr("New conversation")
                enabled: messagesModel.count > 0 || page.conversationId.length > 0
                onClicked: page.newConversation()
            }
        }

        header: PageHeader {
            title: qsTr("Assist")
        }

        footer: Item {
            width: listView.width
            height: Theme.paddingMedium
        }

        delegate: Item {
            id: bubbleRow

            readonly property real maxBubbleWidth: listView.width * 0.8 - 2 * Theme.paddingMedium

            width: listView.width
            height: bubble.height

            Rectangle {
                id: bubble
                anchors {
                    right: model.fromUser ? parent.right : undefined
                    left: model.fromUser ? undefined : parent.left
                    rightMargin: Theme.horizontalPageMargin
                    leftMargin: Theme.horizontalPageMargin
                }
                width: bubbleContent.width + 2 * Theme.paddingMedium
                height: bubbleContent.height + 2 * Theme.paddingSmall
                radius: Theme.paddingMedium
                color: model.fromUser
                    ? Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)
                    : Theme.rgba(Theme.primaryColor, Theme.opacityFaint)

                Column {
                    id: bubbleContent
                    x: Theme.paddingMedium
                    y: Theme.paddingSmall
                    width: model.pending
                        ? pendingIndicator.width
                        : Math.max(textLabel.width, detailsLabel.visible ? detailsLabel.width : 0)

                    BusyIndicator {
                        id: pendingIndicator
                        visible: model.pending
                        running: model.pending
                        size: BusyIndicatorSize.ExtraSmall
                    }

                    Label {
                        id: textLabel
                        visible: !model.pending
                        width: Math.min(implicitWidth, bubbleRow.maxBubbleWidth)
                        wrapMode: Text.Wrap
                        text: model.text
                        color: model.isError ? Theme.errorColor
                            : (model.fromUser ? Theme.highlightColor : Theme.primaryColor)
                    }

                    Label {
                        id: detailsLabel
                        visible: !model.pending && model.details.length > 0
                        width: Math.min(implicitWidth, bubbleRow.maxBubbleWidth)
                        wrapMode: Text.Wrap
                        text: model.details
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                }
            }
        }

        ViewPlaceholder {
            flickable: listView
            enabled: !page.configured
            text: qsTr("Not configured yet")
            hintText: qsTr("Enter the Home Assistant URL and a long-lived access token in Settings first.")
        }
        ViewPlaceholder {
            flickable: listView
            enabled: page.configured && messagesModel.count === 0
            text: qsTr("Ask Home Assistant")
            // Examples are translated on purpose: HA parses the command in
            // the phone's language, so they must be valid commands in it.
            hintText: qsTr("For example:") + "\n“" + qsTr("Turn off the office light") + "”\n“"
                + qsTr("What's the temperature in the kitchen?") + "”"
        }

        VerticalScrollDecorator {}
    }

    Item {
        id: inputRow
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: inputField.height + Theme.paddingSmall

        TextField {
            id: inputField
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                bottomMargin: Theme.paddingSmall
            }
            enabled: page.configured
            label: qsTr("Message to Home Assistant")
            placeholderText: qsTr("Message to Home Assistant")
            EnterKey.enabled: text.trim().length > 0 && !page.busy
            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
            EnterKey.onClicked: {
                if (page.send(text)) {
                    text = ""
                }
            }

            rightItem: IconButton {
                icon.source: "image://theme/icon-m-enter-accept"
                enabled: page.configured && !page.busy && inputField.text.trim().length > 0
                opacity: enabled ? 1.0 : Theme.opacityLow
                onClicked: {
                    if (page.send(inputField.text)) {
                        inputField.text = ""
                    }
                }
            }
        }
    }
}
