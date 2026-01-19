const ChatDrawerState = {
  mounted() {
    this.updateBodyClasses()
  },
  updated() {
    this.updateBodyClasses()
  },
  destroyed() {
    document.body.classList.remove("body-chat-open")
    document.body.classList.remove("body-chat-fullscreen")
  },
  updateBodyClasses() {
    const isOpen = this.el.classList.contains("chat-open")
    const isFullscreen = this.el.classList.contains("chat-fullscreen")
    document.body.classList.toggle("body-chat-open", isOpen)
    document.body.classList.toggle("body-chat-fullscreen", isFullscreen && isOpen)
  },
}

export default ChatDrawerState
