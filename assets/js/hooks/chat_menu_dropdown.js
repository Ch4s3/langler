const ChatMenuDropdown = {
  mounted() {
    this.buttonEl = this.el.querySelector("button")
    this.menuEl = this.el.querySelector("ul")
    this.sessionId = this.el.dataset.sessionId

    if (!this.buttonEl) return

    // Position menu function
    this.positionMenu = () => {
      if (!this.menuEl || !this.buttonEl) return

      // Wait for menu to be rendered
      if (this.menuEl.offsetParent === null) {
        setTimeout(() => this.positionMenu(), 10)
        return
      }

      const buttonRect = this.buttonEl.getBoundingClientRect()
      const menuRect = this.menuEl.getBoundingClientRect()

      // Position below and to the right of the button
      const top = buttonRect.bottom + 4 // 4px gap
      const left = buttonRect.right - menuRect.width // Align right edge with button

      this.menuEl.style.top = `${top}px`
      this.menuEl.style.left = `${left}px`
      this.menuEl.style.right = "auto"
      this.menuEl.style.bottom = "auto"
    }

    // Watch for menu visibility changes
    if (this.menuEl) {
      this.mutationObserver = new MutationObserver(() => {
        if (this.menuEl && this.menuEl.offsetParent !== null) {
          this.positionMenu()
        }
      })

      this.mutationObserver.observe(this.menuEl, {
        attributes: true,
        attributeFilter: ["style", "class"],
        childList: true,
        subtree: true,
      })
    }

    // Reposition on window resize/scroll
    this.handleResize = () => {
      if (this.menuEl && this.menuEl.offsetParent !== null) {
        this.positionMenu()
      }
    }

    window.addEventListener("resize", this.handleResize)
    window.addEventListener("scroll", this.handleResize, true)
  },

  updated() {
    // Reposition menu when it becomes visible after update
    if (this.menuEl && this.menuEl.offsetParent !== null) {
      setTimeout(() => this.positionMenu(), 0)
    }
  },

  destroyed() {
    if (this.mutationObserver) {
      this.mutationObserver.disconnect()
    }
    if (this.handleResize) {
      window.removeEventListener("resize", this.handleResize)
      window.removeEventListener("scroll", this.handleResize, true)
    }
  },
}

export default ChatMenuDropdown
