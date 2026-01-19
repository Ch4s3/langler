/**
 * DictionarySearch hook for handling Cmd+J keyboard shortcut
 * and managing the dictionary search modal.
 */

const shouldIgnoreShortcut = (target, modal) => {
  if (!target) return false
  
  // If modal is open and target is the dictionary search input, allow the shortcut (to close)
  if (modal && modal.classList.contains("modal-open")) {
    const searchInput = document.getElementById("dictionary-search-input")
    if (target === searchInput || target.closest("#dictionary-search-modal")) {
      return false
    }
  }
  
  // Otherwise, ignore if it's an editable field
  const tag = target.tagName
  const isEditable = tag === "INPUT" || tag === "TEXTAREA" || target.isContentEditable
  const closestEditable =
    typeof target.closest === "function"
      ? target.closest("input, textarea, [contenteditable=\"true\"]")
      : null
  return isEditable || Boolean(closestEditable)
}

const DictionarySearch = {
  mounted() {
    this.onKeyDown = event => {
      const isModifier = event.metaKey || event.ctrlKey
      if (!isModifier) return
      if (event.key.toLowerCase() !== "j") return
      
      const modal = document.getElementById("dictionary-search-modal")
      if (shouldIgnoreShortcut(event.target, modal)) return

      event.preventDefault()
      
      // Always push open_search - the server will toggle based on current state
      this.pushEventTo(this.el, "open_search", {})
    }

    // Focus input when modal opens
    this.handleEvent("dictionary:focus-input", () => {
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          const input = document.getElementById("dictionary-search-input")
          if (input) {
            input.focus()
            input.select()
          }
        })
      })
    })

    // Close on Escape key
    this.onEscape = event => {
      if (event.key === "Escape") {
        const modal = document.getElementById("dictionary-search-modal")
        if (modal && modal.classList.contains("modal-open")) {
          this.pushEventTo(this.el, "close_search", {})
        }
      }
    }

    window.addEventListener("keydown", this.onKeyDown)
    window.addEventListener("keydown", this.onEscape)
  },

  destroyed() {
    window.removeEventListener("keydown", this.onKeyDown)
    window.removeEventListener("keydown", this.onEscape)
  }
}

export default DictionarySearch
