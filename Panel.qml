import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Bar button plus popup panel, plus a "Pop out" button that floats the same
// panel content in a normal resizable window. The service owns the items and
// the connection; PanelBody owns each surface's cursor; this file owns the
// bar button, the popup surface and the pop-out window.
Panel {
    id: root
    moduleName: "io.github.powerk1977.openhab"
    ipcTarget: "io.github.powerk1977.openhab"
    // We own the target's single IpcHandler, so the methods below can sit
    // alongside the base open/close/toggle.
    manageIpc: false

    readonly property var oh: bar && bar.shell ? bar.shell.serviceFor("io.github.powerk1977.openhab") : null
    readonly property bool serviceReady: oh !== null
    readonly property string phase: serviceReady ? oh.phase : "idle"

    // A separate plugin surface, so it goes through the shell. The popup closes
    // first because the overlay takes exclusive keyboard focus.
    function openSettings(tab) {
        if (!bar || !bar.shell || typeof bar.shell.summon !== "function")
            return;
        close();
        bar.shell.summon("io.github.powerk1977.openhab", JSON.stringify({
            tab: tab || "connection"
        }));
    }

    // Pop-out button on the popup: close the popup and float the content in a
    // window. Pressing it again (from either surface) hides the window.
    function togglePopout() {
        if (popout.visible) {
            popout.visible = false;
            return;
        }
        close();
        popout.visible = true;
    }

    readonly property color iconColor: {
        var base = bar ? bar.barForeground : Color.foreground;
        return phase === "connected" ? base : Qt.darker(base, 1.5);
    }

    // The bar relies on `button.active` for the text-glyph path; a custom
    // iconComponent is not tinted, so the icon picks urgent itself like the
    // built-in's `activeColor` binding.
    readonly property color barIconColor: phase === "error" ? (bar ? bar.urgent : Color.urgent) : iconColor

    // Closing the popup resets its cursor; the window keeps its own.
    onOpenedChanged: if (!opened && typeof body !== "undefined")
        body.resetCursor()

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    IpcHandler {
        target: "io.github.powerk1977.openhab"

        function open(): void {
            root.open();
        }
        function close(): void {
            root.close();
        }
        function show(): void {
            root.open();
        }
        function hide(): void {
            root.close();
        }
        function toggle(): void {
            root.toggle();
        }

        function status(): string {
            if (!root.serviceReady)
                return "service: UNREACHABLE";
            return "phase=" + root.oh.phase + " configured=" + root.oh.configured + " demo=" + root.oh.demoMode + " items=" + root.oh.itemCount + " rows=" + root.oh.rows.count + (root.oh.lastError ? " error=" + root.oh.lastError : "");
        }

        function refresh(): void {
            if (root.serviceReady)
                root.oh.refresh();
        }

        //   bind = SUPER, L, exec, omarchy-shell openhab toggleItem LivingRoom_Ceiling_Dimmer
        function toggleItem(itemName: string): string {
            if (!root.serviceReady)
                return "service unavailable";
            if (!root.oh.entityStore.item(itemName))
                return "unknown item " + itemName;
            return root.oh.toggleItem(itemName) ? "ok" : (root.oh.lastError || "item isn't toggleable");
        }

        //   bind = SUPER, T, exec, omarchy-shell openhab setBrightness LivingRoom_Ceiling_Dimmer 40
        function setBrightness(itemName: string, percent: int): string {
            if (!root.serviceReady)
                return "service unavailable";
            if (!root.oh.entityStore.item(itemName))
                return "unknown item " + itemName;
            return root.oh.setBrightness(itemName, percent) ? "ok" : (root.oh.lastError || "item isn't dimmable");
        }

        // Two no-arg calls, not one taking a tab: IpcHandler makes declared
        // arguments mandatory, so `settings` alone would refuse to run.
        function settings(): void {
            root.openSettings("connection");
        }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        iconComponent: Component {
            OpenHabIcon {
                anchors.centerIn: parent
                iconSize: Style.bar.iconCanvas
                color: root.barIconColor
            }
        }
        foreground: root.barIconColor
        active: root.phase === "error"
        onPressed: root.toggle()
    }

    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        // The panel has a fixed inner width (preferredWidth); the popout
        // window that shares PanelBody lets the user resize freely instead.
        // `fittedContentWidth` only compensates for height, so reserve the
        // card's horizontal insets (padding + borders) here or the content
        // clips behind them.
        contentWidth: panel.fittedContentWidth(body.preferredWidth
            + panel.padding * 2 + Border.left(panel.borderSpec) + Border.right(panel.borderSpec))
        contentHeight: panel.fittedContentHeight(body.contentImplicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            blocked: body.blockedKeys
            onCloseRequested: root.close()
            onTabRequested: function (direction) {
                root.switchPanel(direction);
            }
            onMoveRequested: function (dx, dy) {
                // Grouped list: no sideways tab switching anymore. Vertical
                // moves navigate the cursor; the first press only wakes it.
                if (dy === 0) return;
                if (!body.cursorActive)
                    body.focusLand();
                else
                    body.moveCursor(dy > 0 ? 1 : -1);
            }
            onActivateRequested: if (body.cursorActive)
                body.activateCursor()
            onTextKey: function (key) {
                var lower = String(key).toLowerCase();
                if (lower === "r" && body.serviceReady)
                    body.oh.refresh();
                else if (lower === "e" && body.cursorActive) {
                    var item = body.currentRow();
                    if (item && !item.locationHeader && item.expandable) {
                        body.toggleRowExpansion(item.itemName, item.expanded);
                    }
                } else if (lower === "s")
                    root.openSettings("connection");
            }

            PanelBody {
                id: body
                anchors.fill: parent
                oh: root.oh
                bar: root.bar
                settingsOpener: root.openSettings
                popoutOpen: popout.visible
                onPopoutRequested: root.togglePopout()
            }
        }
    }

    FloatingWindow {
        id: popout
        title: "openHAB"
        color: Color.popups.background
        implicitWidth: Style.space(560)
        implicitHeight: Style.space(640)
        minimumSize: Qt.size(Style.space(360), Style.space(420))
        visible: false

        onVisibleChanged: {
            if (visible) {
                Qt.callLater(function() { winCatcher.forceActiveFocus() });
            } else {
                popoutBody.resetCursor();
            }
        }

        // Compositor/user close (Super+W kill, titlebar ✕) doesn't flip
        // `visible` — Quickshell's `closed` fires instead. Sync it so
        // togglePopout() reopens the window on the next press.
        onClosed: popout.visible = false

        FocusScope {
            anchors.fill: parent
            anchors.margins: Style.spacing.popupPadding
            focus: true

            PanelKeyCatcher {
                id: winCatcher
                anchors.fill: parent
                blocked: popoutBody.blockedKeys
                onCloseRequested: popout.visible = false
                onMoveRequested: function (dx, dy) {
                    if (dy === 0) return;
                    if (!popoutBody.cursorActive)
                        popoutBody.focusLand();
                    else
                        popoutBody.moveCursor(dy > 0 ? 1 : -1);
                }
                onActivateRequested: if (popoutBody.cursorActive)
                    popoutBody.activateCursor()
                onTextKey: function (key) {
                    var lower = String(key).toLowerCase();
                    if (lower === "r" && popoutBody.serviceReady)
                        popoutBody.oh.refresh();
                    else if (lower === "e" && popoutBody.cursorActive) {
                        var item = popoutBody.currentRow();
                        if (item && !item.locationHeader && item.expandable) {
                            popoutBody.toggleRowExpansion(item.itemName, item.expanded);
                        }
                    } else if (lower === "s") {
                        popout.visible = false;
                        root.openSettings("connection");
                    }
                }

                PanelBody {
                    id: popoutBody
                    anchors.fill: parent
                    oh: root.oh
                    bar: null
                    settingsOpener: root.openSettings
                    popoutOpen: popout.visible
                    onPopoutRequested: popout.visible = false
                }
            }
        }
    }
}