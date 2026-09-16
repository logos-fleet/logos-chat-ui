import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// The strip across the foot of the canvas, where the app says what it could not
// do. It holds the newest failure until someone deals with it and counts the
// ones queued behind it, so a burst is visible rather than collapsing to
// whichever arrived last.
//
// Activating the message quiets the strip; nothing is discarded, because the
// failures are retained behind the button. That button is the way to the run's
// log files and to the whole list, and is the one thing on the bar that is there
// whether or not anything failed.
//
// IT READS THE RETAINED LIST, not a signal (logos-workspace#205). The strip used
// to be told what to say by the view, out of the backend's one-shot `error`
// signal -- and chat_ui's worst failure fires before the view exists: the
// backend initialises the chat module from its own construction, so "Failed to
// initialise chat" was emitted with nothing connected, went to a log, and the
// app drew an ordinary conversation list over a backend that was never there.
// The retained list is the one thing that survives that, so the bar takes it
// whole and decides for itself what nobody has looked at.
// Set the properties; standalone.
Rectangle {
    id: root

    // Every failure this run kept, newest first: one map per entry, with
    // `when`, `message` and `count`, exactly as the backend publishes them.
    required property var failures
    // How many of them somebody has already looked at. HERE rather than in the
    // view, because "what is still unread" is the only state the strip has and
    // splitting it from the list it counts is what let the two disagree.
    property int seenCount: 0

    signal errorActivated
    signal logsRequested

    readonly property int retainedCount: root.failures ? root.failures.length : 0
    // Never negative: the backend caps its log at 200 entries and drops the
    // oldest, so the list a strip is holding can get SHORTER without anything
    // having been read.
    readonly property int errorCount: Math.max(0, root.retainedCount - root.seenCount)
    // The newest, which is the one at the front.
    readonly property string errorMessage:
        root.errorCount > 0 ? (root.failures[0].message || "") : ""

    readonly property bool alerting: root.errorCount > 0

    // Everything retained has been read. Quiets the strip and discards nothing
    // -- the list is behind the button.
    function markSeen() {
        root.seenCount = root.retainedCount;
    }

    implicitWidth: 480
    implicitHeight: 26
    radius: Theme.spacing.radiusMedium
    color: Theme.palette.backgroundTertiary
    border.width: 1
    border.color: Theme.palette.borderSubtle

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.medium
        anchors.rightMargin: Theme.spacing.tiny
        spacing: Theme.spacing.small

        Rectangle {
            visible: root.alerting
            Layout.preferredWidth: 6
            Layout.preferredHeight: 6
            radius: Theme.spacing.radiusPill
            color: Theme.palette.error
        }

        LogosText {
            objectName: "statusMessage"
            Layout.fillWidth: true
            text: root.alerting ? root.errorMessage : ""
            textFormat: Text.PlainText
            color: Theme.palette.error
            font.pixelSize: Theme.typography.secondaryText
            elide: Text.ElideRight
            Accessible.role: Accessible.StaticText
            Accessible.name: text

            TapHandler {
                enabled: root.alerting
                onTapped: root.errorActivated()
            }

            HoverHandler {
                enabled: root.alerting
                cursorShape: Qt.PointingHandCursor
            }
        }

        LogosText {
            objectName: "statusErrorCount"
            visible: root.errorCount > 1
            //: How many failures are waiting on the status bar, the one shown included.
            text: qsTr("%n errors", "", root.errorCount)
            color: Theme.palette.textTertiary
            font.pixelSize: Theme.typography.secondaryText
        }

        // Always here, failure or not: it is the way to the run's files as much
        // as to the failures, and both outlive the strip's line.
        Rectangle {
            id: logsButton
            objectName: "showLogsButton"

            Layout.preferredWidth: logsRow.implicitWidth + 2 * Theme.spacing.small
            Layout.preferredHeight: 20
            radius: Theme.spacing.radiusSmall
            color: Theme.palette.overlayLight
            border.width: 1
            border.color: Theme.palette.borderDark
            Accessible.role: Accessible.Button
            //: Names the button that opens the run's failures and log files
            Accessible.name: qsTr("Show logs")
            Accessible.onPressAction: root.logsRequested()

            RowLayout {
                id: logsRow
                anchors.centerIn: parent
                spacing: 6

                LogosText {
                    //: Button at the foot of the window that opens the run's failures and log files
                    text: qsTr("Show logs")
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textTertiary
                }

                // How many failures nobody has looked at. Opening the dialog is
                // what marks them seen, so the badge goes quiet while the list
                // behind it stands.
                Rectangle {
                    objectName: "unseenErrorBadge"
                    visible: root.alerting
                    Layout.preferredWidth: Math.max(15, badgeLabel.implicitWidth + 8)
                    Layout.preferredHeight: 15
                    radius: Theme.spacing.radiusPill
                    color: Theme.palette.error

                    LogosText {
                        id: badgeLabel
                        anchors.centerIn: parent
                        text: root.errorCount
                        font.pixelSize: Theme.typography.badgeText
                        font.weight: Theme.typography.weightBold
                        color: Theme.palette.backgroundBlack
                    }
                }
            }

            TapHandler {
                onTapped: root.logsRequested()
            }

            HoverHandler {
                cursorShape: Qt.PointingHandCursor
            }
        }
    }
}
