// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/langler"
import WordTooltip from "./hooks/word_tooltip"
import CopyToClipboard from "./hooks/copy_to_clipboard"
import ArticleStickyHeader from "./hooks/article_sticky_header"
import ChatAutoScroll from "./hooks/chat_auto_scroll"
import ChatMenuDropdown from "./hooks/chat_menu_dropdown"
import StudySession from "./hooks/study_session"
import ChatDrawerState from "./hooks/chat_drawer_state"
import TextDownloader from "./hooks/text_downloader"
import DictionarySearch from "./hooks/dictionary_search"
import AudioPlayer from "./hooks/audio_player"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const WordCardToggle = {
  mounted() {
    this.itemId = Number(this.el.dataset.itemId)

    this.clickHandler = () => {
      this.log(`click dispatched for card ${this.itemId}`)
    }

    this.el.addEventListener("click", this.clickHandler)

    this.handleEvent("study:card-toggled", detail => {
      if (detail.id === this.itemId) {
        this.log(`card ${this.itemId} toggled; flipped=${detail.flipped}`)
      }
    })
  },
  destroyed() {
    this.el.removeEventListener("click", this.clickHandler)
  },
  log(message) {
    console.log(`[WordCardToggle] ${message}`)
  },
}

const ChatShortcut = {
  mounted() {
    this.onKeyDown = event => {
      const isModifier = event.metaKey || event.ctrlKey
      if (!isModifier) return
      if (event.key.toLowerCase() !== "k") return
      if (this.el.classList.contains("chat-open")) return
      event.preventDefault()
      this.pushEvent("toggle_chat", {})
    }

    window.addEventListener("keydown", this.onKeyDown)
  },
  destroyed() {
    window.removeEventListener("keydown", this.onKeyDown)
  },
}

const hooks = {
  ...colocatedHooks,
  WordTooltip,
  WordCardToggle,
  CopyToClipboard,
  ArticleStickyHeader,
  ChatAutoScroll,
  ChatMenuDropdown,
  StudySession,
  ChatDrawerState,
  TextDownloader,
  DictionarySearch,
  AudioPlayer,
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

const shouldIgnoreShortcut = target => {
  if (!target) return false
  const tag = target.tagName
  const isEditable = tag === "INPUT" || tag === "TEXTAREA" || target.isContentEditable
  const closestEditable =
    typeof target.closest === "function"
      ? target.closest("input, textarea, [contenteditable=\"true\"]")
      : null
  return isEditable || Boolean(closestEditable)
}

window.addEventListener("keydown", event => {
  const modifierHeld = event.metaKey || event.ctrlKey
  if (!modifierHeld) return
  if (event.key.toLowerCase() !== "k") return
  if (shouldIgnoreShortcut(event.target)) return

  const drawer = document.getElementById("chat-drawer-container")
  if (!drawer) return

  const openButton = drawer.querySelector("button[aria-label='Open chat']")
  const closeButton = drawer.querySelector("button[aria-label='Close chat']")
  if (!openButton && !closeButton) return

  event.preventDefault()
  if (drawer.classList.contains("chat-open") && closeButton) {
    closeButton.click()
    return
  }

  openButton?.click()
})

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
