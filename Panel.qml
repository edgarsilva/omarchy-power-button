import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.edgarsilva.power-button"
  ipcTarget: "io.github.edgarsilva.power-button"
  manageIpc: false

  property int cursorIndex: 0
  property bool cursorActive: false
  property var pendingAction: null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string icon: String(setting("icon", "")).trim() || Model.byId("shutdown").icon
  readonly property bool grouped: setting("showGroupHeaders", true) === true
  readonly property bool showDescriptions: setting("showDescriptions", true) === true
  readonly property bool showNumbers: setting("showNumbers", true) === true
  readonly property string confirmMode: String(setting("confirm", "Destructive actions"))
  readonly property string rightClickLabel: String(setting("rightClickAction", "Lock"))

  readonly property var rows: Model.rowsFor(setting("items", []), power.available, grouped)
  readonly property int rowHeight: showDescriptions ? Style.space(42) : Style.space(30)
  readonly property bool confirming: pendingAction !== null

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function actionAt(index) {
    return index >= 0 && index < rows.length ? rows[index].action : null
  }

  function moveCursor(delta) {
    if (rows.length === 0) return
    cursorIndex = Math.max(0, Math.min(rows.length - 1, cursorIndex + delta))
  }

  function needsConfirm(action) {
    if (confirmMode === "Never") return false
    if (confirmMode === "Every action") return true
    return action.destructive === true
  }

  // One funnel for every path in (click, keyboard, number key, right-click on
  // the bar icon) so the confirm rule and the close-then-run ordering can
  // never drift between them.
  function activate(action) {
    if (!action) return
    if (needsConfirm(action)) {
      pendingAction = action
      confirmDialog.selectedIndex = 1
      return
    }
    root.close()
    power.run(action)
  }

  function activateCursor() {
    activate(actionAt(cursorIndex))
  }

  function confirmPending() {
    var action = pendingAction
    pendingAction = null
    root.close()
    power.run(action)
  }

  // Number keys jump straight to a row. Letters are not used: PanelKeyCatcher
  // already owns h/j/k/l for movement and x for delete, which takes the
  // natural first letters of Lock, Hibernate, and Shutdown off the table.
  function activateNumber(text) {
    var n = parseInt(text, 10)
    if (!isFinite(n) || n < 1 || n > rows.length) return
    cursorActive = true
    cursorIndex = n - 1
    activate(actionAt(n - 1))
  }

  onOpenedChanged: {
    if (opened) {
      power.refresh()
      cursorIndex = 0
      cursorActive = false
    } else {
      pendingAction = null
    }
  }

  Service {
    id: power
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    // Fire an action without showing the menu, so a Hyprland bind can reuse
    // the same command table this panel renders: `omarchy-shell
    // io.github.edgarsilva.power-button run lock`.
    function run(id: string): string {
      var action = Model.byId(String(id))
      if (!action) return "unknown action: " + id
      if (!Model.isAvailable(action, power.available)) return "unavailable on this machine: " + id
      root.close()
      power.run(action)
      return "ok"
    }
    function list(): string {
      var out = []
      var visible = Model.visibleActions(root.setting("items", []), power.available)
      for (var i = 0; i < visible.length; i++) out.push(visible[i].id)
      return out.join("\n")
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    tooltipText: root.rightClickLabel === "None"
      ? "Power"
      : "Power — right click to " + root.rightClickLabel.toLowerCase()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton && root.rightClickLabel !== "None") {
        var action = Model.byLabel(root.rightClickLabel)
        if (action && Model.isAvailable(action, power.available)) {
          root.close()
          power.run(action)
        }
        return
      }
      root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      // While the confirm card is up it owns every key: arrows swap the
      // buttons, enter commits, escape backs out to the menu rather than
      // closing the panel out from under a half-made decision.
      onMoveRequested: function(dx, dy) {
        if (root.confirming) {
          confirmDialog.selectedIndex = confirmDialog.selectedIndex === 0 ? 1 : 0
          return
        }
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: {
        if (root.confirming) {
          if (confirmDialog.selectedIndex === 0) root.pendingAction = null
          else root.confirmPending()
          return
        }
        if (root.cursorActive) root.activateCursor()
        else root.cursorActive = true
      }
      onCloseRequested: {
        if (root.confirming) root.pendingAction = null
        else root.close()
      }
      onTabRequested: function(direction) {
        if (!root.confirming) root.switchPanel(direction)
      }
      onTextKey: function(t) {
        if (root.confirming) return
        root.activateNumber(t)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(8)

          PanelHero {
            width: parent.width
            title: "Power"
            meta: power.sessionLine
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: root.icon
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                color: root.foreground
              }
            }
          }

          Repeater {
            model: root.rows

            Column {
              required property var modelData
              required property int index

              readonly property var action: modelData.action
              readonly property bool hasCursor: root.cursorActive && root.cursorIndex === index
              // Destructive rows only warm to red once they are the row you
              // are about to press. A menu that is red at rest reads as an
              // error state rather than as a consequence.
              readonly property color accentColor: action.destructive && hasCursor ? Color.urgent : root.foreground

              width: column.width
              spacing: Style.space(6)

              PanelSectionHeader {
                width: parent.width
                visible: modelData.header !== ""
                text: modelData.header
                foreground: root.foreground
                fontFamily: root.fontFamily
                // PanelSectionHeader reserves glyph overshoot in its own
                // topPadding; keep that and add the group gap on top of it.
                topPadding: (index === 0 ? 0 : Style.space(8)) + Math.ceil(fontSize * 0.15)
              }

              CursorSurface {
                width: parent.width
                height: root.rowHeight
                hasCursor: parent.hasCursor
                foreground: parent.action.destructive ? Color.urgent : root.foreground
                accent: parent.action.destructive ? Color.urgent : Color.accent

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: { root.cursorActive = true; root.cursorIndex = index }
                  onClicked: root.activate(action)
                }

                Text {
                  id: rowIcon
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: action.icon
                  color: accentColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                  Behavior on color { ColorAnimation { duration: 120 } }
                }

                Column {
                  anchors.left: rowIcon.right
                  anchors.leftMargin: Style.space(12)
                  anchors.right: numberPill.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    text: action.label
                    elide: Text.ElideRight
                    color: accentColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    Behavior on color { ColorAnimation { duration: 120 } }
                  }
                  Text {
                    width: parent.width
                    visible: root.showDescriptions
                    text: action.detail
                    elide: Text.ElideRight
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  id: numberPill
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.showNumbers && modelData.number <= 9
                  text: String(modelData.number)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.rows.length === 0
            text: "No actions enabled. Pick some in the widget settings."
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelSeparator {
            width: parent.width
            visible: root.rows.length > 0
            foreground: root.foreground
          }

          Text {
            width: parent.width
            // Name the range that actually exists — "1–9" on a six-row menu
            // advertises keys that do nothing.
            text: root.showNumbers && root.rows.length > 1
              ? "↑↓ move · 1–" + Math.min(9, root.rows.length) + " jump · enter select · esc close"
              : "↑↓ move · enter select · esc close"
            horizontalAlignment: Text.AlignHCenter
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        z: 10
        opened: root.confirming
        message: root.pendingAction ? Model.confirmMessage(root.pendingAction) : ""
        confirmText: Model.confirmLabel(root.pendingAction)
        background: Color.popups.background
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.pendingAction = null
        onConfirmed: root.confirmPending()
      }
    }
  }
}
