import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Minimal web-search overlay. Summoned by the shell
// (`omarchy-shell shell toggle oxhenri.spotlight`); the shell calls
// open()/close()/dismiss() and supplies `shell` + `manifest`.
//
// Type a query — Google autocomplete suggests while you type.
// Enter opens the search in the default browser (Chromium). Nothing else:
// no files/folders mode, no inline results, no backend binary.

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  // ── theming (menu surface tokens) ─────────────────────────────────────────
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border,
                                                       Color.menu.border, Math.max(1, Style.space(2)))
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int cardW: Math.min(Style.space(560), panel.width - Style.gapsOut * 4)

  // ── state ─────────────────────────────────────────────────────────────────
  property int selectedIndex: 0
  property int suggestToken: 0

  ListModel { id: suggestionModel }

  // ── lifecycle (called by the shell) ───────────────────────────────────────
  function open(payloadJson) {
    root.opened = true
    searchField.text = ""
    suggestionModel.clear()
    root.selectedIndex = 0
    root.suggestToken++
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "oxhenri.spotlight")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // ── search + suggestions ──────────────────────────────────────────────────
  function search(q) {
    q = String(q || "").trim()
    if (q.length === 0) return
    Quickshell.execDetached(["xdg-open", "https://www.google.com/search?q=" + encodeURIComponent(q)])
    root.dismiss()
  }

  function fetchSuggestions(query) {
    var token = ++root.suggestToken
    var xhr = new XMLHttpRequest()
    xhr.open("GET", "https://suggestqueries.google.com/complete/search?client=firefox&q=" + encodeURIComponent(query))
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (token !== root.suggestToken) return // stale response for an older query
      var items = []
      try {
        var data = JSON.parse(xhr.responseText)
        if (Array.isArray(data) && Array.isArray(data[1])) {
          // list format: ["query", ["a", "b", ...]]
          items = data[1]
        } else if (Array.isArray(data)) {
          // object format: [{phrase: "a"}, ...]
          for (var i = 0; i < data.length; i++)
            if (data[i] && data[i].phrase) items.push(data[i].phrase)
        }
      } catch (e) { items = [] }
      suggestionModel.clear()
      for (var j = 0; j < Math.min(items.length, 8); j++) suggestionModel.append({ text: String(items[j]) })
      root.selectedIndex = 0
    }
    xhr.send()
  }

  Timer {
    id: debounce
    interval: 120
    onTriggered: {
      var q = searchField.text.trim()
      suggestionModel.clear()
      if (q.length > 0) root.fetchSuggestions(q)
    }
  }

  // ── overlay window ────────────────────────────────────────────────────────
  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "oxhenri-spotlight"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      width: root.cardW
      height: col.height + card.contentTopInset + card.contentBottomInset
      radius: Style.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin
      anchors.centerIn: parent

      Column {
        id: col
        width: card.width - card.contentLeftInset - card.contentRightInset
        x: card.contentLeftInset
        y: card.contentTopInset
        spacing: Style.spacing.md

        TextField {
          id: searchField
          width: parent.width
          placeholderText: "Search the web…"
          font.family: root.fontFamily
          onTextChanged: debounce.restart()

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.dismiss()
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_Down && suggestionModel.count > 0) {
              root.selectedIndex = (root.selectedIndex + 1) % suggestionModel.count
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_Up && suggestionModel.count > 0) {
              root.selectedIndex = (root.selectedIndex - 1 + suggestionModel.count) % suggestionModel.count
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_Tab && suggestionModel.count > 0) {
              searchField.text = suggestionModel.get(Math.min(root.selectedIndex, suggestionModel.count - 1)).text
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              var q = searchField.text.trim()
              if (q.length > 0 && suggestionModel.count > 0 && root.selectedIndex < suggestionModel.count)
                q = suggestionModel.get(root.selectedIndex).text
              root.search(q)
              event.accepted = true
            }
          }
        }

        ListView {
          visible: suggestionModel.count > 0
          width: parent.width
          height: Math.min(contentHeight, panel.height / 2)
          clip: true
          currentIndex: root.selectedIndex
          model: suggestionModel
          spacing: Style.spacing.xs

          delegate: Rectangle {
            required property int index
            required property string text
            width: ListView.view.width
            height: rowText.height + Style.space(8)
            radius: Style.cornerRadius
            color: root.selectedIndex === index ? root.selectedBackground : "transparent"

            Text {
              id: rowText
              anchors.verticalCenter: parent.verticalCenter
              x: Style.space(8)
              width: parent.width - Style.space(16)
              text: parent.text
              color: root.selectedIndex === index ? root.selectedText : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onContainsMouseChanged: if (containsMouse) root.selectedIndex = index
              onClicked: root.search(parent.text)
            }
          }
        }
      }
    }
  }
}
