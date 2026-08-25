import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Web-search overlay. Same surface language as omarchy.menu / omarchy.emojis:
// BorderSurface, [menu] tokens, heading filter, selected row.

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property int suggestToken: 0
  property var suggestXhr: null

  readonly property int suggestTimeoutMs: 4000
  readonly property int suggestMaxBytes: 16384
  readonly property int suggestMaxItems: 8
  readonly property int suggestMaxChars: 160

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.heading + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int rowHeight: Math.max(Style.space(40), Style.font.body + Style.spacing.rowPaddingX)
  property int cardWidth: Math.min(Style.space(520), panel.width - Style.gapsOut * 2)

  readonly property var focusedScreen: {
    var monitor = Hyprland.focusedMonitor
    var target = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name || "") === target) return screens[i]
    return null
  }

  ListModel { id: suggestionModel }

  function applyFocusedScreen() {
    var s = root.focusedScreen
    if (s && panel.screen !== s) panel.screen = s
  }
  Component.onCompleted: root.applyFocusedScreen()

  function open(payloadJson) {
    root.applyFocusedScreen()
    root.opened = true
    root.filterText = ""
    suggestionModel.clear()
    root.selectedIndex = 0
    root.abortSuggest()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.abortSuggest()
    root.opened = false
  }

  function dismiss() {
    root.abortSuggest()
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "oxhenri.search")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function setFilter(text) {
    text = String(text || "")
    if (text.length > root.suggestMaxChars)
      text = text.substring(0, root.suggestMaxChars)
    root.filterText = text
    debounce.restart()
  }

  function search(q) {
    q = root.sanitizeSuggestion(q)
    if (q.length === 0) return
    Quickshell.execDetached(["xdg-open", "https://www.google.com/search?q=" + encodeURIComponent(q)])
    root.dismiss()
  }

  function abortSuggest() {
    root.suggestToken++
    if (root.suggestXhr) {
      try { root.suggestXhr.abort() } catch (e) {}
      root.suggestXhr = null
    }
  }

  function sanitizeSuggestion(value) {
    var s = String(value || "").replace(/[\u0000-\u001F\u007F-\u009F]/g, "").trim()
    if (s.length > root.suggestMaxChars)
      s = s.substring(0, root.suggestMaxChars)
    return s
  }

  function applySuggestions(query, remote) {
    suggestionModel.clear()
    query = root.sanitizeSuggestion(query)
    if (!query) {
      root.selectedIndex = 0
      return
    }
    suggestionModel.append({ text: query })
    var seen = {}
    seen[query.toLowerCase()] = true
    for (var i = 0; i < remote.length && suggestionModel.count < root.suggestMaxItems; i++) {
      var t = root.sanitizeSuggestion(remote[i])
      if (!t || seen[t.toLowerCase()]) continue
      seen[t.toLowerCase()] = true
      suggestionModel.append({ text: t })
    }
    root.selectedIndex = 0
  }

  function responseTooLarge(xhr) {
    var len = parseInt(xhr.getResponseHeader("Content-Length") || "0", 10)
    if (len > root.suggestMaxBytes) return true
    var body = xhr.responseText || ""
    return body.length > root.suggestMaxBytes
  }

  function fetchSuggestions(query) {
    query = root.sanitizeSuggestion(query)
    if (!query) return

    var token = ++root.suggestToken
    if (root.suggestXhr) {
      try { root.suggestXhr.abort() } catch (e) {}
      root.suggestXhr = null
    }

    var xhr = new XMLHttpRequest()
    root.suggestXhr = xhr
    xhr.timeout = root.suggestTimeoutMs

    function dropIfStale() {
      if (root.suggestXhr === xhr) root.suggestXhr = null
      return token !== root.suggestToken
    }

    xhr.ontimeout = function() { dropIfStale() }
    xhr.onabort = function() { dropIfStale() }
    xhr.onprogress = function() {
      if (token !== root.suggestToken) return
      if (root.responseTooLarge(xhr)) xhr.abort()
    }
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.HEADERS_RECEIVED && root.responseTooLarge(xhr)) {
        xhr.abort()
        return
      }
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (dropIfStale()) return
      if (xhr.status !== 200) return
      var body = xhr.responseText || ""
      if (body.length === 0 || body.length > root.suggestMaxBytes) return

      var items = []
      try {
        var data = JSON.parse(body)
        if (Array.isArray(data) && Array.isArray(data[1])) {
          items = data[1]
        } else if (Array.isArray(data)) {
          for (var i = 0; i < data.length; i++)
            if (data[i] && data[i].phrase) items.push(data[i].phrase)
        }
      } catch (e) { items = [] }
      root.applySuggestions(query, items)
    }

    xhr.open("GET", "https://suggestqueries.google.com/complete/search?client=firefox&q=" + encodeURIComponent(query))
    xhr.send()
  }

  Timer {
    id: debounce
    interval: 120
    onTriggered: {
      var q = root.sanitizeSuggestion(root.filterText)
      if (q.length === 0) {
        root.abortSuggest()
        suggestionModel.clear()
        root.selectedIndex = 0
        return
      }
      root.applySuggestions(q, [])
      root.fetchSuggestions(q)
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "oxhenri-search"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: card.contentTopInset + card.contentBottomInset + root.headerHeight
              + (suggestionModel.count > 0 ? root.contentSpacing + suggestionList.height : 0)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Down && suggestionModel.count > 0) {
            root.selectedIndex = (root.selectedIndex + 1) % suggestionModel.count
            event.accepted = true
          } else if (event.key === Qt.Key_Up && suggestionModel.count > 0) {
            root.selectedIndex = (root.selectedIndex - 1 + suggestionModel.count) % suggestionModel.count
            event.accepted = true
          } else if (event.key === Qt.Key_Tab && suggestionModel.count > 0) {
            root.setFilter(suggestionModel.get(Math.min(root.selectedIndex, suggestionModel.count - 1)).text)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            var q = root.filterText
            if (q.length > 0 && suggestionModel.count > 0 && root.selectedIndex < suggestionModel.count)
              q = suggestionModel.get(root.selectedIndex).text
            root.search(q)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
                     && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        anchors.topMargin: card.contentTopInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || "Search…"
            textFormat: Text.PlainText
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
          }
        }

        Column {
          id: suggestionList
          visible: suggestionModel.count > 0
          width: parent.width
          spacing: Style.spacing.xs

          Repeater {
            model: suggestionModel

            BorderSurface {
              id: row
              required property int index
              required property string text
              readonly property bool hasCursor: row.index === root.selectedIndex
              width: suggestionList.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: row.hasCursor ? root.selectedBackground : "transparent"
              borderSpec: row.hasCursor ? root.selectedBorderSpec : Border.none()

              Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: row.text
                textFormat: Text.PlainText
                color: row.hasCursor ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onContainsMouseChanged: if (containsMouse) root.selectedIndex = index
                onClicked: root.search(row.text)
              }
            }
          }
        }
      }
    }
  }
}
