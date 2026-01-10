const TOOLTIP_ID = "word-tooltip"

let activeHook = null

const ensureTooltipEl = () => {
  let existing = document.getElementById(TOOLTIP_ID)
  if (existing) {
    return existing
  }

  const tooltip = document.createElement("div")
  tooltip.id = TOOLTIP_ID
  tooltip.className =
    "fixed z-50 w-80 max-w-xs rounded-2xl border border-base-300 bg-base-100 p-4 shadow-2xl transition-opacity duration-150 opacity-0"
  tooltip.setAttribute("role", "status")
  tooltip.dataset.actionsBound = "true"
  tooltip.addEventListener("click", event => {
    const target = event.target.closest("[data-action='add-to-study']")
    if (!target) return
    event.preventDefault()
    event.stopPropagation()
    const wordId = target.dataset.wordId
    if (!wordId || !activeHook) return
    activeHook.pushEvent("add_to_study", {word_id: wordId})
  })
  document.body.appendChild(tooltip)
  return tooltip
}

const escapeHtml = text =>
  text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")

const buildDefinitions = definitions => {
  if (!definitions || definitions.length === 0) {
    return "<p class=\"text-sm text-base-content/70\">Sin definiciones disponibles.</p>"
  }

  const items = definitions
    .map(def => `<li class="mb-1 last:mb-0">${escapeHtml(def)}</li>`)
    .join("")

  return `<ol class="list-decimal pl-4 text-sm text-base-content/80 space-y-1">${items}</ol>`
}

const positionTooltip = (tooltip, anchor) => {
  const rect = anchor.getBoundingClientRect()
  const tooltipRect = tooltip.getBoundingClientRect()

  // For position: fixed, coordinates are relative to viewport (no scroll offset needed)
  let top = rect.bottom + 8
  let left = rect.left + (rect.width / 2) - (tooltipRect.width / 2)

  // Keep tooltip within viewport bounds
  const minLeft = 16
  const maxLeft = window.innerWidth - tooltipRect.width - 16
  
  if (left < minLeft) left = minLeft
  if (left > maxLeft) left = maxLeft
  
  // Ensure tooltip doesn't go below viewport
  const maxTop = window.innerHeight - tooltipRect.height - 16
  if (top > maxTop) {
    // Position above the word instead
    top = rect.top - tooltipRect.height - 8
  }
  
  // Ensure tooltip doesn't go above viewport
  if (top < 16) {
    top = 16
  }

  tooltip.style.top = `${top}px`
  tooltip.style.left = `${left}px`
}

const renderCta = entry => {
  if (entry.studied) {
    return `<span class="badge badge-success badge-outline text-xs font-semibold">✓</span>`
  }

  if (!entry.word_id) {
    return ""
  }

  return `<button
    class="btn btn-xs btn-circle btn-primary text-white"
    data-action="add-to-study"
    data-word-id="${entry.word_id}"
    aria-label="Añadir a estudio"
    title="Añadir a estudio"
  >
    +
  </button>`
}

const renderEntry = entry => {
  const metaParts = [entry.part_of_speech, entry.pronunciation].filter(Boolean)
  const meta =
    metaParts.length > 0
      ? `<p class="text-xs uppercase tracking-wide text-base-content/60">${metaParts.join(" • ")}</p>`
      : ""

  const translation = entry.translation
    ? `<p class="mt-1 rounded-full bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary/90 w-fit">${escapeHtml(entry.translation)}</p>`
    : ""

  const sourceLink = entry.source_url
    ? `<a href="${entry.source_url}" target="_blank" class="text-xs text-base-content/60 hover:text-primary transition-colors">Wiktionary →</a>`
    : ""

  const context = entry.context
    ? `<p class="mt-3 text-xs italic text-base-content/60">&ldquo;${escapeHtml(entry.context)}&rdquo;</p>`
    : ""

  return `
    <div>
      <div class="flex items-start justify-between gap-3">
        <div>
          <p class="text-base font-semibold text-base-content">${escapeHtml(entry.word)}</p>
          ${meta}
          ${translation}
        </div>
        <div class="flex items-center gap-2">${renderCta(entry)}</div>
      </div>
      <div class="mt-3">${buildDefinitions(entry.definitions)}</div>
      <div class="mt-3 flex items-center justify-between">
        ${context}
        ${sourceLink}
      </div>
    </div>
  `
}

const hideTooltip = tooltip => {
  tooltip.dataset.active = "false"
  tooltip.style.opacity = "0"
  // Optionally hide completely after transition
  setTimeout(() => {
    if (tooltip.dataset.active === "false") {
      tooltip.style.display = "none"
    }
  }, 150) // Match transition duration
}

const showTooltip = (tooltip, html, anchor) => {
  tooltip.innerHTML = html
  tooltip.dataset.active = "true"
  
  // Force display and remove opacity class to ensure visibility
  tooltip.style.display = "block"
  tooltip.style.opacity = "1"
  tooltip.style.visibility = "visible"
  
  // Remove the opacity-0 class that might be overriding inline styles
  tooltip.classList.remove("opacity-0")
  
  // Use double requestAnimationFrame to ensure DOM is fully updated and laid out
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      positionTooltip(tooltip, anchor)
    })
  })
}

const WordTooltip = {
  mounted() {
    this.tooltipEl = ensureTooltipEl()
    this.handleClick = this.handleClick.bind(this)
    this.handleDocClick = this.handleDocClick.bind(this)
    this.handleWordData = this.handleWordData.bind(this)
    this.pendingTimeout = null

    this.el.addEventListener("click", this.handleClick)
    document.addEventListener("click", this.handleDocClick)
    this.handleEvent("word-data", this.handleWordData)
  },
  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
    document.removeEventListener("click", this.handleDocClick)
    if (activeHook === this) {
      activeHook = null
    }
  },
  handleClick(event) {
    event.stopPropagation()
    event.preventDefault()
    if (this.pendingTimeout) clearTimeout(this.pendingTimeout)
    this.pendingTimeout = setTimeout(() => this.pushLookup(), 50)
  },
  handleWordData(payload) {
    if (payload.dom_id !== this.el.id) return
    if (this.pendingTimeout) clearTimeout(this.pendingTimeout)
    activeHook = this
    showTooltip(this.tooltipEl, renderEntry(payload), this.el)
  },
  handleDocClick(event) {
    // Don't hide if clicking on the word element or the tooltip itself
    if (this.el.contains(event.target) || this.tooltipEl.contains(event.target)) {
      return
    }
    hideTooltip(this.tooltipEl)
    if (activeHook === this) {
      activeHook = null
    }
  },
  pushLookup() {
    this.pushEvent("fetch_word_data", {
      word: this.el.dataset.word,
      language: this.el.dataset.language,
      sentence_id: this.el.dataset.sentenceId,
      dom_id: this.el.id,
      word_id: this.el.dataset.wordId,
    })
  },
}

export default WordTooltip
