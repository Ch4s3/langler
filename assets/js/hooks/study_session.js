const StudySession = {
  mounted() {
    this.onKeyDown = event => {
      // Ignore if user is typing in an input/textarea
      const tag = event.target.tagName
      const isEditable = tag === "INPUT" || tag === "TEXTAREA" || event.target.isContentEditable
      if (isEditable) return

      // Spacebar: flip card
      if (event.key === " " || event.key === "Spacebar") {
        event.preventDefault()
        this.pushEvent("flip_card", {})
        return
      }

      // Number keys 1-4: rate card
      const ratingMap = {
        "1": "0", // Again
        "2": "2", // Hard
        "3": "3", // Good
        "4": "4", // Easy
      }

      if (ratingMap[event.key]) {
        event.preventDefault()
        const quality = ratingMap[event.key]
        // Get the current card's item-id from the rating buttons
        const ratingButton = this.el.querySelector(
          `button[phx-click="rate_card"][phx-value-quality="${quality}"]`
        )
        if (ratingButton) {
          const itemId = ratingButton.getAttribute("phx-value-item-id")
          if (itemId) {
            this.pushEvent("rate_card", {
              quality: quality,
              item_id: itemId,
            })
          }
        }
      }
    }

    window.addEventListener("keydown", this.onKeyDown)
  },
  destroyed() {
    if (this.onKeyDown) {
      window.removeEventListener("keydown", this.onKeyDown)
    }
  },
}

export default StudySession
