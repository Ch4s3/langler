const ChatAutoScroll = {
  mounted() {
    this.queueScroll("auto")

    this.handleEvent("chat:scroll-bottom", payload => {
      const behavior = payload?.instant ? "auto" : "smooth"
      this.queueScroll(behavior)
    })
  },
  updated() {
    if (this.pendingScroll) {
      this.scrollToBottom(this.pendingScroll)
      this.pendingScroll = null
    }
  },
  queueScroll(behavior = "smooth") {
    this.pendingScroll = behavior
    this.scrollToBottom(behavior)
  },
  scrollToBottom(behavior = "smooth") {
    requestAnimationFrame(() => {
      this.el.scrollTo({
        top: this.el.scrollHeight,
        behavior,
      })
    })
  },
}

export default ChatAutoScroll
