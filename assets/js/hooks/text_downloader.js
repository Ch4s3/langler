const TextDownloader = {
  mounted() {
    this.handleClick = this.handleClick.bind(this)
    this.el.addEventListener("click", this.handleClick)
  },
  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
  },
  handleClick(event) {
    event.stopPropagation()
    const text = this.el.dataset.downloadText?.trim()
    if (!text) return

    const filename =
      this.el.dataset.downloadFilename?.trim() || "langler-response.txt"
    const blob = new Blob([text], {type: "text/plain;charset=utf-8"})
    const url = URL.createObjectURL(blob)
    const link = document.createElement("a")
    link.href = url
    link.download = filename
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
    URL.revokeObjectURL(url)
  },
}

export default TextDownloader
