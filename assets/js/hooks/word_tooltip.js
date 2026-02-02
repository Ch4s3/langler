const TOOLTIP_ID = "word-tooltip"

let activeHook = null

// Selection state (shared across all hook instances)
let selectionState = null
// { anchorEl, anchorHook, anchorSentenceId, currentEndEl, selectedEls: [], allSentenceTokens: [] }

const LONG_PRESS_MS = 300
const ACTIVE_SELECTION_CLASS = "phrase-selection-highlight"

// Helper to add/remove selection class
const addSelectionClasses = (el) => el.classList.add(ACTIVE_SELECTION_CLASS)
const removeSelectionClasses = (el) => el.classList.remove(ACTIVE_SELECTION_CLASS)

const ensureTooltipEl = () => {
  let existing = document.getElementById(TOOLTIP_ID)
  if (existing) {
    return existing
  }

  const tooltip = document.createElement("div")
  tooltip.id = TOOLTIP_ID
  tooltip.className =
    "fixed z-50 w-80 max-w-xs rounded-2xl border border-base-200 bg-base-100/95 p-5 shadow-2xl transition-all duration-200 opacity-0"
  tooltip.setAttribute("role", "status")
  tooltip.dataset.actionsBound = "true"
  tooltip.addEventListener("click", event => {
    const addButton = event.target.closest("[data-action='add-to-study']")
    if (addButton) {
      event.preventDefault()
      event.stopPropagation()
      const wordId = addButton.dataset.wordId
      const translations = addButton.dataset.translations
      const definitions = addButton.dataset.definitions
      if (!wordId || !activeHook) return
      
      const eventData = {
        word_id: wordId,
        translations,
        definitions,
        dom_id: activeHook.el.id,
      }
      
      // If component-id is set, target the component instead of parent LiveView
      const componentId = activeHook.el.dataset.componentId
      if (componentId) {
        const drawerContainer = activeHook.el.closest("#chat-drawer-container")
        let componentEl = null
        if (drawerContainer) {
          const containerComponentId = drawerContainer.getAttribute("phx-component")
          if (containerComponentId === componentId) {
            componentEl = drawerContainer
          } else {
            componentEl = drawerContainer.querySelector(`[phx-component="${componentId}"]`)
          }
        }
        if (!componentEl) {
          // Not in drawer, manually traverse up (but stop at drawer container)
          let current = activeHook.el.parentElement
          while (current && !componentEl) {
            if (current.id === "chat-drawer-container") break
            if (current.getAttribute && current.getAttribute("phx-component") === componentId) {
              componentEl = current
              break
            }
            current = current.parentElement
          }
        }
        if (!componentEl) {
          componentEl = document.querySelector(`[phx-component="${componentId}"]`)
        }
        if (componentEl) {
          activeHook.pushEventTo(componentEl, "add_to_study", eventData)
        } else {
          activeHook.pushEvent("add_to_study", eventData)
        }
      } else {
        activeHook.pushEvent("add_to_study", eventData)
      }
      return
    }

    const ratingButton = event.target.closest("[data-action='rate-word']")
    if (ratingButton) {
      event.preventDefault()
      event.stopPropagation()
      const {wordId, quality, rateTarget} = ratingButton.dataset
      if (!wordId || !quality || !activeHook) return
      const eventName = rateTarget === "existing" ? "rate_existing_word" : "rate_new_word"
      
      const eventData = {
        word_id: wordId,
        quality,
        dom_id: activeHook.el.id,
      }
      
      const componentId = activeHook.el.dataset.componentId
      if (componentId) {
        const drawerContainer = activeHook.el.closest("#chat-drawer-container")
        let componentEl = null
        if (drawerContainer) {
          const containerComponentId = drawerContainer.getAttribute("phx-component")
          if (containerComponentId === componentId) {
            componentEl = drawerContainer
          } else {
            componentEl = drawerContainer.querySelector(`[phx-component="${componentId}"]`)
          }
        }
        if (!componentEl) {
          // Not in drawer, manually traverse up (but stop at drawer container)
          let current = activeHook.el.parentElement
          while (current && !componentEl) {
            if (current.id === "chat-drawer-container") break
            if (current.getAttribute && current.getAttribute("phx-component") === componentId) {
              componentEl = current
              break
            }
            current = current.parentElement
          }
        }
        if (!componentEl) {
          componentEl = document.querySelector(`[phx-component="${componentId}"]`)
        }
        if (componentEl) {
          activeHook.pushEventTo(componentEl, eventName, eventData)
        } else {
          activeHook.pushEvent(eventName, eventData)
        }
      } else {
        activeHook.pushEvent(eventName, eventData)
      }
      return
    }

    const removeButton = event.target.closest("[data-action='remove-word']")
    if (removeButton) {
      event.preventDefault()
      event.stopPropagation()
      const {wordId} = removeButton.dataset
      if (!wordId || !activeHook) return
      
      const eventData = {
        word_id: wordId,
        dom_id: activeHook.el.id,
      }
      
      const componentId = activeHook.el.dataset.componentId
      if (componentId) {
        const drawerContainer = activeHook.el.closest("#chat-drawer-container")
        let componentEl = null
        if (drawerContainer) {
          const containerComponentId = drawerContainer.getAttribute("phx-component")
          if (containerComponentId === componentId) {
            componentEl = drawerContainer
          } else {
            componentEl = drawerContainer.querySelector(`[phx-component="${componentId}"]`)
          }
        }
        if (!componentEl) {
          // Not in drawer, manually traverse up (but stop at drawer container)
          let current = activeHook.el.parentElement
          while (current && !componentEl) {
            if (current.id === "chat-drawer-container") break
            if (current.getAttribute && current.getAttribute("phx-component") === componentId) {
              componentEl = current
              break
            }
            current = current.parentElement
          }
        }
        if (!componentEl) {
          componentEl = document.querySelector(`[phx-component="${componentId}"]`)
        }
        if (componentEl) {
          activeHook.pushEventTo(componentEl, "remove_from_study", eventData)
        } else {
          activeHook.pushEvent("remove_from_study", eventData)
        }
      } else {
        activeHook.pushEvent("remove_from_study", eventData)
      }
    }
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

const ratingButtons = [
  {label: "Hard", quality: "hard", className: "btn-warning"},
  {label: "Good", quality: "good", className: "btn-primary"},
  {label: "Easy", quality: "easy", className: "btn-success"}
]

const renderCornerAction = entry => {
  // Only show the + button in the corner (not the Tracked indicator)
  if (!entry.word_id || entry.studied) {
    return ""
  }

  const wrapperClasses =
    "absolute right-3 top-3 flex h-9 min-w-[2.75rem] items-center justify-center"

  return `<div class="${wrapperClasses}">
    <button
      class="btn btn-circle btn-xs btn-primary text-white shadow w-full h-full"
      data-action="add-to-study"
      data-word-id="${entry.word_id}"
      data-translations="${entry.translation || ""}"
      data-definitions="${(entry.definitions || []).join("||")}"
      aria-label="Add to study"
      title="Add to study"
    >
      +
    </button>
  </div>`
}


const renderActionSection = entry => {
  if (!entry.word_id) return ""

  const viewButton = entry.study_item_id
    ? `<a
        class="btn btn-xs btn-ghost border border-base-300/70 text-sm"
        href="/study#items-${entry.study_item_id}"
      >
        View card
      </a>`
    : ""

  const removeButton = `<button
    type="button"
    class="btn btn-xs btn-ghost border border-error/40 text-error"
    data-action="remove-word"
    data-word-id="${entry.word_id}"
  >
    Remove
  </button>`

  const ratingBlock = entry.studied
    ? `<div class="space-y-2 rounded-2xl border border-dashed border-base-300/80 bg-base-200/30 p-3">
      <p class="text-xs uppercase tracking-widest text-base-content/60">Score difficulty</p>
      <div class="flex flex-wrap gap-2">
        ${ratingButtons
          .map(
            button => `<button
                type="button"
                class="btn btn-xs font-semibold text-white ${button.className}"
                data-action="rate-word"
                data-rate-target="existing"
                data-word-id="${entry.word_id}"
                data-quality="${button.quality}"
              >
                ${button.label}
              </button>`
          )
          .join("")}
      </div>
    </div>`
    : ""

  return `<div class="space-y-3">
    <div class="flex flex-wrap gap-2">${viewButton}${entry.studied ? removeButton : ""}</div>
    ${ratingBlock}
  </div>`
}

const renderEntry = entry => {
  const metaParts = [entry.part_of_speech, entry.pronunciation].filter(Boolean)
  const meta =
    metaParts.length > 0
      ? `<p class="text-xs uppercase tracking-wide text-base-content/60">${metaParts.join(" • ")}</p>`
      : ""

  const phraseBadge = entry.word_type === "phrase"
    ? `<span class="badge badge-secondary badge-sm">Phrase</span>`
    : ""

  // Tracked indicator as inline badge
  const trackedBadge = entry.studied
    ? `<span class="badge badge-success badge-sm gap-1">
        <span class="text-xs">Tracked</span>
        <span class="text-sm leading-none">✓</span>
      </span>`
    : ""

  // For phrases, show translation prominently below the word
  // For regular words, show it in a smaller pill
  const translation = entry.translation
    ? entry.word_type === "phrase"
      ? `<p class="text-sm text-base-content/80">${escapeHtml(entry.translation)}</p>`
      : `<p class="mt-1 rounded-full bg-primary/10 px-2 py-0.5 text-xs font-semibold text-primary/90 w-fit">${escapeHtml(entry.translation)}</p>`
    : ""

  const sourceLink = entry.source_url
    ? `<a href="${entry.source_url}" target="_blank" class="text-xs text-base-content/60 hover:text-primary transition-colors">Wiktionary →</a>`
    : ""

  const context = entry.context
    ? `<p class="mt-3 text-xs italic text-base-content/60">&ldquo;${escapeHtml(entry.context)}&rdquo;</p>`
    : ""

  // Use wider padding when there's a corner action (+ button) to prevent overlap
  const rightPadding = (!entry.studied && entry.word_id) ? "pr-12" : ""

  return `
    <div class="relative space-y-3 ${rightPadding}">
      ${renderCornerAction(entry)}
      <div class="space-y-1.5">
        <p class="text-base font-semibold text-base-content">${escapeHtml(entry.word)}</p>
        <div class="flex items-center gap-2 flex-wrap">
          ${phraseBadge}
          ${trackedBadge}
        </div>
        ${meta}
        ${translation}
      </div>
      <div>${buildDefinitions(entry.definitions)}</div>
      <div class="flex items-center justify-between">
        ${context}
        ${sourceLink}
      </div>
      ${renderActionSection(entry)}
    </div>
  `
}

const renderLoadingSkeleton = () => {
  return `
    <div class="relative space-y-4 pr-6">
      <div class="absolute right-3 top-3 flex items-center justify-center rounded-full bg-base-200/80 p-2">
        <span class="loading loading-ring loading-primary"></span>
      </div>
      <div class="space-y-2">
        <div class="h-4 w-32 rounded-full bg-base-300/80"></div>
        <div class="h-3 w-24 rounded-full bg-base-200"></div>
      </div>
      <div class="space-y-2">
        <div class="h-3 w-full rounded-full bg-base-200"></div>
        <div class="h-3 w-5/6 rounded-full bg-base-200"></div>
        <div class="h-3 w-4/6 rounded-full bg-base-200"></div>
      </div>
      <div class="space-y-2">
        <div class="h-3 w-2/3 rounded-full bg-base-200"></div>
        <div class="h-3 w-1/2 rounded-full bg-base-200"></div>
      </div>
      <div class="rounded-2xl border border-dashed border-base-300/70 bg-base-100/80 p-3">
        <div class="h-3 w-28 rounded-full bg-base-200"></div>
        <div class="mt-3 flex gap-2">
          <div class="h-8 w-20 rounded-full bg-base-200"></div>
          <div class="h-8 w-20 rounded-full bg-base-200"></div>
          <div class="h-8 w-20 rounded-full bg-base-200"></div>
        </div>
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

// Selection mode helper functions
function cancelSelection() {
  if (!selectionState) return
  
  selectionState.selectedEls.forEach(el => removeSelectionClasses(el))
  selectionState = null
  
  document.removeEventListener("mousemove", handleSelectionMouseMove)
  document.removeEventListener("keydown", handleSelectionKeyDown)
  document.removeEventListener("click", handleSelectionOutsideClick, true)
  document.removeEventListener("pointermove", handleSelectionPointerMove)
}

function handleSelectionMouseMove(event) {
  if (!selectionState) return
  
  const hoveredEl = document.elementFromPoint(event.clientX, event.clientY)
  if (!hoveredEl) return
  
  const tokenEl = hoveredEl.closest("[data-sentence-id][data-word]")
  if (!tokenEl) return
  
  // Must be same sentence
  if (tokenEl.dataset.sentenceId !== selectionState.anchorSentenceId) return
  
  if (tokenEl === selectionState.currentEndEl) return
  selectionState.currentEndEl = tokenEl
  
  updateSelectionHighlight()
}

function handleSelectionPointerMove(event) {
  if (!selectionState) return
  
  const el = document.elementFromPoint(event.clientX, event.clientY)
  if (!el) return
  
  const tokenEl = el.closest("[data-sentence-id][data-word]")
  if (!tokenEl || tokenEl.dataset.sentenceId !== selectionState.anchorSentenceId) return
  
  selectionState.currentEndEl = tokenEl
  updateSelectionHighlight()
}

function updateSelectionHighlight() {
  // Clear old highlights
  selectionState.selectedEls.forEach(el => removeSelectionClasses(el))
  
  // Use pre-cached token list for performance
  const allTokens = selectionState.allSentenceTokens
  
  const anchorIdx = allTokens.indexOf(selectionState.anchorEl)
  const endIdx = allTokens.indexOf(selectionState.currentEndEl)
  
  if (anchorIdx === -1 || endIdx === -1) {
    return
  }
  
  const [startIdx, stopIdx] = anchorIdx < endIdx ? [anchorIdx, endIdx] : [endIdx, anchorIdx]
  
  selectionState.selectedEls = allTokens.slice(startIdx, stopIdx + 1)
  selectionState.selectedEls.forEach(el => addSelectionClasses(el))
}

function handleSelectionKeyDown(event) {
  if (event.key === "Escape") {
    cancelSelection()
  }
}

function handleSelectionOutsideClick(event) {
  if (!selectionState) return
  const isTokenClick = event.target.closest("[data-sentence-id][data-word]")
  if (!isTokenClick) {
    cancelSelection()
  }
  // Don't stop propagation - let the element's handleClick run for finalization
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
    this.handleWordRated = this.handleWordRated.bind(this)
    this.handleWordRemoved = this.handleWordRemoved.bind(this)
    this.handleWordAdded = this.handleWordAdded.bind(this)
    this.handlePointerDown = this.handlePointerDown.bind(this)
    this.handlePointerUp = this.handlePointerUp.bind(this)
    this.handlePointerCancel = this.handlePointerCancel.bind(this)
    this.handlePhraseMouseEnter = this.handlePhraseMouseEnter.bind(this)
    this.handlePhraseMouseLeave = this.handlePhraseMouseLeave.bind(this)
    this.pendingTimeout = null
    this.currentEntry = null
    this.longPressTimer = null

    this.el.addEventListener("click", this.handleClick)
    this.el.addEventListener("pointerdown", this.handlePointerDown)
    this.el.addEventListener("pointerup", this.handlePointerUp)
    this.el.addEventListener("pointercancel", this.handlePointerCancel)
    document.addEventListener("click", this.handleDocClick)
    
    // Add phrase hover handling
    if (this.el.dataset.phraseId) {
      this.el.addEventListener("mouseenter", this.handlePhraseMouseEnter)
      this.el.addEventListener("mouseleave", this.handlePhraseMouseLeave)
    }
    
    this.handleEvent("word-data", this.handleWordData)
    this.handleEvent("word-rated", this.handleWordRated)
    this.handleEvent("word-removed", this.handleWordRemoved)
    this.handleEvent("word-added", this.handleWordAdded)
  },
  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
    this.el.removeEventListener("pointerdown", this.handlePointerDown)
    this.el.removeEventListener("pointerup", this.handlePointerUp)
    this.el.removeEventListener("pointercancel", this.handlePointerCancel)
    document.removeEventListener("click", this.handleDocClick)
    
    if (this.el.dataset.phraseId) {
      this.el.removeEventListener("mouseenter", this.handlePhraseMouseEnter)
      this.el.removeEventListener("mouseleave", this.handlePhraseMouseLeave)
    }
    
    if (this.longPressTimer) {
      clearTimeout(this.longPressTimer)
    }
    if (activeHook === this) {
      activeHook = null
    }
  },
  handlePhraseMouseEnter() {
    const phraseId = this.el.dataset.phraseId
    if (!phraseId) return
    
    // Add hover class to all tokens with the same phrase ID
    document.querySelectorAll(`[data-phrase-id="${phraseId}"]`).forEach(el => {
      el.classList.add("phrase-hover")
    })
  },
  handlePhraseMouseLeave() {
    const phraseId = this.el.dataset.phraseId
    if (!phraseId) return
    
    // Remove hover class from all tokens with the same phrase ID
    document.querySelectorAll(`[data-phrase-id="${phraseId}"]`).forEach(el => {
      el.classList.remove("phrase-hover")
    })
  },
  handleClick(event) {
    const isModifierClick = event.metaKey || event.ctrlKey

    if (isModifierClick) {
      // Start phrase selection
      event.stopPropagation()
      event.preventDefault()
      this.startSelection()
      return
    }

    if (selectionState && selectionState.anchorSentenceId === this.el.dataset.sentenceId) {
      // Finalize selection on second click in same sentence
      // If the user clicked directly without hovering, update the end element now
      if (this.el !== selectionState.anchorEl) {
        selectionState.currentEndEl = this.el
        updateSelectionHighlight()
      }
      
      event.stopPropagation()
      event.preventDefault()
      this.finalizeSelection()
      return
    }

    // Normal single-word lookup
    event.stopPropagation()
    event.preventDefault()
    if (this.pendingTimeout) clearTimeout(this.pendingTimeout)
    this.pendingTimeout = setTimeout(() => this.pushLookup(), 50)
  },
  startSelection() {
    cancelSelection()  // Clear any prior selection
    
    // Pre-cache all lexical tokens in this sentence for performance
    const sentenceId = this.el.dataset.sentenceId
    const allSentenceTokens = Array.from(
      document.querySelectorAll(`[data-sentence-id="${sentenceId}"][data-word]`)
    )
    
    selectionState = {
      anchorEl: this.el,
      anchorHook: this,
      anchorSentenceId: sentenceId,
      currentEndEl: this.el,
      selectedEls: [this.el],
      allSentenceTokens: allSentenceTokens
    }
    
    addSelectionClasses(this.el)
    
    // Add document-level listeners
    document.addEventListener("mousemove", handleSelectionMouseMove)
    document.addEventListener("keydown", handleSelectionKeyDown)
    document.addEventListener("click", handleSelectionOutsideClick, true)
  },
  finalizeSelection() {
    if (!selectionState || selectionState.selectedEls.length < 2) {
      cancelSelection()
      return
    }
    
    // Build phrase text from selected tokens
    const phraseText = selectionState.selectedEls
      .map(el => el.dataset.word)
      .join(" ")
    
    const eventData = {
      word: phraseText,
      language: selectionState.anchorEl.dataset.language,
      sentence_id: selectionState.anchorSentenceId,
      dom_id: selectionState.anchorEl.id,
      term_kind: "phrase",
    }
    
    const hook = selectionState.anchorHook
    activeHook = hook
    hook.currentEntry = null
    showTooltip(hook.tooltipEl, renderLoadingSkeleton(), selectionState.anchorEl)
    
    // If component-id is set, target the component instead of parent LiveView
    const componentId = selectionState.anchorEl.dataset.componentId
    if (componentId) {
      const drawerContainer = selectionState.anchorEl.closest("#chat-drawer-container")
      let componentEl = null
      if (drawerContainer) {
        const containerComponentId = drawerContainer.getAttribute("phx-component")
        if (containerComponentId === componentId) {
          componentEl = drawerContainer
        } else {
          componentEl = drawerContainer.querySelector(`[phx-component="${componentId}"]`)
        }
      }
      if (!componentEl) {
        let current = selectionState.anchorEl.parentElement
        while (current && !componentEl) {
          if (current.id === "chat-drawer-container") break
          if (current.getAttribute && current.getAttribute("phx-component") === componentId) {
            componentEl = current
            break
          }
          current = current.parentElement
        }
      }
      if (!componentEl) {
        componentEl = document.querySelector(`[phx-component="${componentId}"]`)
      }
      if (componentEl) {
        hook.pushEventTo(componentEl, "fetch_word_data", eventData)
      } else {
        hook.pushEvent("fetch_word_data", eventData)
      }
    } else {
      hook.pushEvent("fetch_word_data", eventData)
    }
  },
  handlePointerDown(event) {
    if (event.pointerType !== "touch") return
    
    this.longPressTimer = setTimeout(() => {
      this.startSelection()
      // Add pointermove for drag
      document.addEventListener("pointermove", handleSelectionPointerMove)
    }, LONG_PRESS_MS)
  },
  handlePointerUp(event) {
    // Only handle touch for mobile long-press selection
    if (event.pointerType !== "touch") return
    
    if (this.longPressTimer) {
      clearTimeout(this.longPressTimer)
      this.longPressTimer = null
    }
    
    document.removeEventListener("pointermove", handleSelectionPointerMove)
    
    if (selectionState && selectionState.selectedEls.length >= 2) {
      this.finalizeSelection()
    } else if (selectionState) {
      cancelSelection()
    }
  },
  handlePointerCancel(event) {
    // Only handle touch for mobile long-press selection
    if (event.pointerType !== "touch") return
    
    if (this.longPressTimer) {
      clearTimeout(this.longPressTimer)
      this.longPressTimer = null
    }
    
    document.removeEventListener("pointermove", handleSelectionPointerMove)
    cancelSelection()
  },
  handleWordData(payload) {
    if (payload.dom_id !== this.el.id) return
    if (this.pendingTimeout) clearTimeout(this.pendingTimeout)
    
    // Clear selection highlight when word data arrives
    if (selectionState && selectionState.anchorEl === this.el) {
      selectionState.selectedEls.forEach(el => removeSelectionClasses(el))
      cancelSelection()
    }
    
    activeHook = this
    if (payload.word_id) {
      this.el.dataset.wordId = payload.word_id
    }
    this.currentEntry = payload
    showTooltip(this.tooltipEl, renderEntry(payload), this.el)
  },
  handleDocClick(event) {
    // Don't interfere with phrase selection
    if (selectionState) {
      return
    }
    // Don't hide if clicking on the word element or the tooltip itself
    if (this.el.contains(event.target) || this.tooltipEl.contains(event.target)) {
      return
    }
    hideTooltip(this.tooltipEl)
    if (activeHook === this) {
      activeHook = null
    }
  },
  matchesPayload(payload) {
    const matchesDom = payload.dom_id && payload.dom_id === this.el.id
    const matchesWord = payload.word_id?.toString() === this.el.dataset.wordId
    return matchesDom || matchesWord
  },
  handleWordRated(payload) {
    if (!this.matchesPayload(payload)) return
    if (!this.currentEntry) return
    this.currentEntry = {
      ...this.currentEntry,
      studied: true,
      rating_required: true,
      study_item_id: payload.study_item_id || this.currentEntry.study_item_id,
      fsrs_sleep_until: payload.fsrs_sleep_until || this.currentEntry.fsrs_sleep_until,
    }
    showTooltip(this.tooltipEl, renderEntry(this.currentEntry), this.el)
  },
  handleWordRemoved(payload) {
    if (!this.matchesPayload(payload)) return
    if (!this.currentEntry) return
    this.currentEntry = {
      ...this.currentEntry,
      studied: false,
      rating_required: false,
      study_item_id: null,
      fsrs_sleep_until: null,
    }
    showTooltip(this.tooltipEl, renderEntry(this.currentEntry), this.el)
  },
  handleWordAdded(payload) {
    if (!this.matchesPayload(payload)) return
    if (!this.currentEntry) return
    this.currentEntry = {
      ...this.currentEntry,
      studied: true,
      rating_required: true,
      study_item_id: payload.study_item_id,
      fsrs_sleep_until: payload.fsrs_sleep_until || this.currentEntry.fsrs_sleep_until,
    }
    showTooltip(this.tooltipEl, renderEntry(this.currentEntry), this.el)
  },
  pushLookup() {
    // Check if this token is part of a saved phrase
    const phraseText = this.el.dataset.phrase
    const phraseId = this.el.dataset.phraseId
    
    const eventData = {
      word: phraseText || this.el.dataset.word,
      language: this.el.dataset.language,
      sentence_id: this.el.dataset.sentenceId,
      dom_id: this.el.id,
      word_id: phraseId || this.el.dataset.wordId,
      term_kind: phraseText ? "phrase" : "word",
    }

    activeHook = this
    this.currentEntry = null
    showTooltip(this.tooltipEl, renderLoadingSkeleton(), this.el)
    
    // If component-id is set, target the component instead of parent LiveView
    const componentId = this.el.dataset.componentId
    if (componentId) {
      // First, check if we're inside the chat drawer container
      const drawerContainer = this.el.closest("#chat-drawer-container")
      if (drawerContainer) {
        // The container itself should have the phx-component attribute
        // Check if it matches our component ID
        const containerComponentId = drawerContainer.getAttribute("phx-component")
        if (containerComponentId === componentId) {
          // Use the container as the component element
          this.pushEventTo(drawerContainer, "fetch_word_data", eventData)
          return
        }
        // If not, search within the container
        const componentEl = drawerContainer.querySelector(`[phx-component="${componentId}"]`)
        if (componentEl) {
          this.pushEventTo(componentEl, "fetch_word_data", eventData)
          return
  }
}
      // If not in drawer, try to find component by traversing up (but stop at drawer container)
      // This prevents finding the parent LiveView
      let current = this.el.parentElement
      let componentEl = null
      while (current && !componentEl) {
        if (current.id === "chat-drawer-container") {
          // Stop searching if we hit the drawer container
          break
        }
        if (current.getAttribute && current.getAttribute("phx-component") === componentId) {
          componentEl = current
          break
        }
        current = current.parentElement
      }
      if (!componentEl) {
        // Last resort: try to find anywhere in document
        componentEl = document.querySelector(`[phx-component="${componentId}"]`)
      }
      if (componentEl) {
        this.pushEventTo(componentEl, "fetch_word_data", eventData)
      } else {
        // Fallback to parent if component not found
        this.pushEvent("fetch_word_data", eventData)
      }
    } else {
      this.pushEvent("fetch_word_data", eventData)
    }
  },
}

export default WordTooltip
