const ChatInput = {
  mounted() {
    this.resizeObserver = null
    this.handleInput = () => {
      const container = this.el.closest(".chat-drawer-main")
      const maxHeight = container ? Math.floor(container.clientHeight * 0.5) : 200
      const minHeight = 48

      this.el.style.height = "auto"
      const nextHeight = Math.min(this.el.scrollHeight, maxHeight)
      this.el.style.height = `${Math.max(minHeight, nextHeight)}px`
      this.el.style.overflowY = this.el.scrollHeight > nextHeight ? "auto" : "hidden"
    }

    this.handleKeyDown = event => {
      if (event.key !== "Enter" || event.isComposing) return

      const value = this.el.value || ""
      const lineCount = value.split("\n").length

      if (event.shiftKey || lineCount > 1) {
        return
      }

      if (this.el.disabled || value.trim() === "") {
        event.preventDefault()
        return
      }

      event.preventDefault()
      const form = this.el.form
      if (form) {
        form.requestSubmit()
      }
    }

    this.el.addEventListener("keydown", this.handleKeyDown)
    this.el.addEventListener("input", this.handleInput)
    this.el.addEventListener("phx:after-update", this.handleInput)
    this.resizeObserver = new ResizeObserver(() => this.handleInput())
    this.resizeObserver.observe(this.el)
    const container = this.el.closest(".chat-drawer-main")
    if (container) {
      this.resizeObserver.observe(container)
    }
    this.handleInput()
  },

  destroyed() {
    this.el.removeEventListener("keydown", this.handleKeyDown)
    this.el.removeEventListener("input", this.handleInput)
    this.el.removeEventListener("phx:after-update", this.handleInput)
    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
    }
  },
}

export default ChatInput
