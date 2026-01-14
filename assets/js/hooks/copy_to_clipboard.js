const copyTextToClipboard = async text => {
  if (!text) return false

  if (navigator.clipboard && navigator.clipboard.writeText) {
    await navigator.clipboard.writeText(text)
    return true
  }

  const textarea = document.createElement("textarea")
  textarea.value = text
  textarea.setAttribute("readonly", "")
  textarea.style.position = "absolute"
  textarea.style.left = "-9999px"
  document.body.appendChild(textarea)
  textarea.select()
  const success = document.execCommand("copy")
  document.body.removeChild(textarea)
  return success
}

const CopyToClipboard = {
  mounted() {
    this.handleClick = this.handleClick.bind(this)
    this.feedbackTimer = null
    this.el.addEventListener("click", this.handleClick)
  },
  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
    if (this.feedbackTimer) clearTimeout(this.feedbackTimer)
  },
  async handleClick(event) {
    event.stopPropagation()
    const text = this.el.dataset.copyText || this.el.textContent?.trim()
    try {
      await copyTextToClipboard(text)
      this.showFeedback()
    } catch (error) {
      console.error("Unable to copy text", error)
    }
  },
  showFeedback() {
    this.el.classList.add("copied")
    this.el.dataset.copied = "true"
    if (this.feedbackTimer) clearTimeout(this.feedbackTimer)
    this.feedbackTimer = setTimeout(() => {
      this.el.classList.remove("copied")
      delete this.el.dataset.copied
    }, 1200)
  },
}

export default CopyToClipboard
