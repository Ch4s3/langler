export default {
  async mounted() {
    this.audioUrl = this.el.dataset.audioUrl
    this.currentSentenceIdx = 0
    this.sentences = JSON.parse(this.el.dataset.sentences || "[]")
    this.subtitlesVisible = true
    this.playbackRate = parseFloat(this.el.dataset.playbackRate || "1.0")
    this.isPlaying = false
    this.initialListeningPosition = parseFloat(this.el.dataset.initialPosition || "0")
    if (!Number.isFinite(this.initialListeningPosition) || this.initialListeningPosition < 0) {
      this.initialListeningPosition = 0
    }
    this.hasSeekedToInitialPosition = false
    this.lastSavedPosition = null
    this.beforeUnloadHandler = () => {
      this.saveListeningPosition(true)
    }
    window.addEventListener("beforeunload", this.beforeUnloadHandler)

    console.log("[AudioPlayer] mounted - audioUrl:", this.audioUrl)

    // Dynamic import - only loads when hook is used
    const howlerModule = await import("howler")
    const Howl =
      howlerModule?.Howl ??
      howlerModule?.default?.Howl ??
      howlerModule?.module?.exports?.Howl

    if (!Howl) {
      console.error("[AudioPlayer] Unable to resolve Howl constructor from howler module", howlerModule)
      return
    }

    this.Howl = Howl

    if (this.audioUrl) {
      console.log("[AudioPlayer] Creating Howl instance with URL:", this.audioUrl)
      this.sound = new Howl({
        src: [this.audioUrl],
        format: ["wav"],
        html5: true,
        onplay: () => {
          console.log("[AudioPlayer] onplay")
          this.isPlaying = true
          this.updatePlayButton()
          this.pushEvent("audio_playing", {})
        },
        onpause: () => {
          console.log("[AudioPlayer] onpause")
          this.isPlaying = false
          this.updatePlayButton()
          this.saveListeningPosition(true)
          this.pushEvent("audio_paused", {})
        },
        onend: () => {
          console.log("[AudioPlayer] onend")
          this.isPlaying = false
          this.currentSentenceIdx = 0
          this.saveListeningPosition(true)
          this.pushEvent("audio_ended", {})
        },
        onseek: () => {
          this.syncSubtitles()
        },
        onload: () => {
          console.log("[AudioPlayer] onload - audio loaded successfully")
          const duration = this.getDuration()
          let targetPosition = this.initialListeningPosition
          if (duration > 0 && Number.isFinite(duration)) {
            targetPosition = Math.min(targetPosition, duration)
          }

          if (targetPosition > 0 && !this.hasSeekedToInitialPosition) {
            console.log("[AudioPlayer] Seeking to saved position:", targetPosition)
            this.seek(targetPosition)
            this.updateTimeDisplay()
            this.updateSeekSlider()
            this.hasSeekedToInitialPosition = true
          }

          this.pushEvent("audio_loaded", {})
        },
        onloaderror: (id, error) => {
          console.error("[AudioPlayer] onloaderror - id:", id, "error:", error)
          this.pushEvent("audio_load_error", {error: error})
        }
      })

      // Start subtitle sync and UI update polling
      this.lastScrolledSentenceIdx = -1
      this.subtitleInterval = setInterval(() => {
        if (this.isPlaying) {
          this.syncSubtitles()
        }
        // Update time display and seek slider regardless of playing state
        this.updateTimeDisplay()
        this.updateSeekSlider()
        // Scroll to active sentence if it changed
        if (this.currentSentenceIdx !== this.lastScrolledSentenceIdx) {
          this.scrollToActiveSentence()
          this.lastScrolledSentenceIdx = this.currentSentenceIdx
        }
      }, 500)

      // Periodically save listening position while playing (every 5 seconds)
      this.savePositionInterval = setInterval(() => {
        if (this.isPlaying) {
          this.saveListeningPosition()
        }
      }, 5000)

      // Set up click handler for play button
      const playButton = this.el.querySelector(".audio-play-button")
      if (playButton) {
        this.playButtonClickHandler = () => {
          console.log("[AudioPlayer] Play button clicked")
          this.togglePlay()
        }
        playButton.addEventListener("click", this.playButtonClickHandler)
      }

      // Set up click handlers for skip buttons
      const skipBackButton = this.el.querySelector(".audio-skip-back-button")
      if (skipBackButton) {
        this.skipBackClickHandler = () => {
          console.log("[AudioPlayer] Skip back button clicked")
          this.skipBackward()
        }
        skipBackButton.addEventListener("click", this.skipBackClickHandler)
      }

      const skipForwardButton = this.el.querySelector(".audio-skip-forward-button")
      if (skipForwardButton) {
        this.skipForwardClickHandler = () => {
          console.log("[AudioPlayer] Skip forward button clicked")
          this.skipForward()
        }
        skipForwardButton.addEventListener("click", this.skipForwardClickHandler)
      }

      // Set up seek slider interaction
      const seekSlider = this.el.querySelector("#audio-seek")
      if (seekSlider) {
        this.seekSliderInputHandler = (e) => {
          const sliderValue = parseFloat(e.target.value)
          const duration = this.sound ? this.sound.duration() || 0 : 0
          if (duration > 0) {
            const targetTime = (sliderValue / 100) * duration
            console.log("[AudioPlayer] Seeking to:", targetTime)
            this.seek(targetTime)
            // Update time display immediately
            this.updateTimeDisplay()
          }
        }
        seekSlider.addEventListener("input", this.seekSliderInputHandler)
      }

      // Set up volume slider interaction
      const volumeSlider = this.el.querySelector("#audio-volume")
      if (volumeSlider) {
        this.volumeSliderInputHandler = (e) => {
          const volumeValue = parseFloat(e.target.value) / 100
          console.log("[AudioPlayer] Setting volume to:", volumeValue)
          this.setVolume(volumeValue)
        }
        volumeSlider.addEventListener("input", this.volumeSliderInputHandler)
      }
    } else {
      console.warn("[AudioPlayer] No audioUrl provided")
    }
  },

  destroyed() {
    this.saveListeningPosition(true)

    if (this.beforeUnloadHandler) {
      window.removeEventListener("beforeunload", this.beforeUnloadHandler)
      this.beforeUnloadHandler = null
    }

    if (this.subtitleInterval) {
      clearInterval(this.subtitleInterval)
    }
    if (this.savePositionInterval) {
      clearInterval(this.savePositionInterval)
    }
    if (this.sound) {
      this.sound.unload()
    }
    // Remove play button click handler
    const playButton = this.el.querySelector(".audio-play-button")
    if (playButton && this.playButtonClickHandler) {
      playButton.removeEventListener("click", this.playButtonClickHandler)
    }
    // Remove skip button click handlers
    const skipBackButton = this.el.querySelector(".audio-skip-back-button")
    if (skipBackButton && this.skipBackClickHandler) {
      skipBackButton.removeEventListener("click", this.skipBackClickHandler)
    }
    const skipForwardButton = this.el.querySelector(".audio-skip-forward-button")
    if (skipForwardButton && this.skipForwardClickHandler) {
      skipForwardButton.removeEventListener("click", this.skipForwardClickHandler)
    }
    // Remove seek slider handler
    const seekSlider = this.el.querySelector("#audio-seek")
    if (seekSlider && this.seekSliderInputHandler) {
      seekSlider.removeEventListener("input", this.seekSliderInputHandler)
    }
    // Remove volume slider handler
    const volumeSlider = this.el.querySelector("#audio-volume")
    if (volumeSlider && this.volumeSliderInputHandler) {
      volumeSlider.removeEventListener("input", this.volumeSliderInputHandler)
    }
  },

  syncSubtitles() {
    if (!this.sound || !this.sentences || this.sentences.length === 0) return

    const currentTime = this.sound.seek() || 0
    const totalDuration = this.sound.duration() || 1
    
    if (totalDuration <= 0) return

    // Calculate total character count for all sentences
    const totalChars = this.sentences.reduce((sum, s) => sum + (s.content?.length || 0), 0)
    if (totalChars === 0) return

    // Calculate cumulative character counts to determine sentence boundaries
    let cumulativeChars = 0
    let estimatedIdx = 0
    
    // Find which sentence we should be on based on character-weighted progress
    // Use 95% of progress to allow earlier advancement
    const progress = (currentTime / totalDuration) * 0.95
    const targetChars = progress * totalChars
    
    for (let i = 0; i < this.sentences.length; i++) {
      const sentenceChars = this.sentences[i].content?.length || 0
      cumulativeChars += sentenceChars
      
      if (cumulativeChars >= targetChars) {
        estimatedIdx = i
        break
      }
    }
    
    const clampedIdx = Math.max(0, Math.min(estimatedIdx, this.sentences.length - 1))

    // Only advance forward if we're well into the next sentence
    if (clampedIdx > this.currentSentenceIdx) {
      // Calculate the actual time we should be at for this sentence based on character count
      let charsBeforeSentence = 0
      for (let i = 0; i < clampedIdx; i++) {
        charsBeforeSentence += this.sentences[i].content?.length || 0
      }
      
      const sentenceChars = this.sentences[clampedIdx].content?.length || 0
      const sentenceStartProgress = charsBeforeSentence / totalChars
      const sentenceEndProgress = (charsBeforeSentence + sentenceChars) / totalChars
      
      // Only advance if we're at least 5% through the next sentence
      // This allows very early advancement to stay in sync with audio
      const sentenceStartTime = sentenceStartProgress * totalDuration
      const sentenceEndTime = sentenceEndProgress * totalDuration
      const thresholdTime = sentenceStartTime + (sentenceEndTime - sentenceStartTime) * 0.05
      
      if (currentTime >= thresholdTime) {
        this.currentSentenceIdx = clampedIdx
        this.pushEvent("sentence_changed", {index: clampedIdx})
        this.scrollToActiveSentence()
      }
    } else if (clampedIdx < this.currentSentenceIdx) {
      // Allow going backwards immediately (user seeking backwards)
      this.currentSentenceIdx = clampedIdx
      this.pushEvent("sentence_changed", {index: clampedIdx})
      this.scrollToActiveSentence()
    }
  },

  handleEvent(event, payload) {
    console.log("[AudioPlayer] handleEvent:", event, payload)
    switch (event) {
      case "toggle_play":
        console.log("[AudioPlayer] toggle_play - isPlaying:", this.isPlaying, "sound:", !!this.sound)
        if (this.isPlaying) {
          this.pause()
        } else {
          this.play()
        }
        break
      case "set_playback_rate":
        if (payload && payload.rate) {
          this.setPlaybackRate(parseFloat(payload.rate))
        }
        break
      case "sentence_changed":
        // Update current sentence index and scroll to it
        if (payload && payload.index !== undefined) {
          this.currentSentenceIdx = payload.index
          this.scrollToActiveSentence()
        }
        break
    }
  },

  updated() {
    // Handle action from LiveView
    const action = this.el.dataset.action
    if (action === "toggle_play") {
      console.log("[AudioPlayer] updated - toggle_play action")
      if (this.isPlaying) {
        this.pause()
      } else {
        this.play()
      }
      // Clear the action
      this.el.removeAttribute("data-action")
    }

    // Update playback rate if it changed in LiveView
    const newRate = parseFloat(this.el.dataset.playbackRate || this.playbackRate)
    if (newRate !== this.playbackRate && this.sound) {
      this.setPlaybackRate(newRate)
    }

    // Check if current sentence index changed in LiveView by looking at the DOM
    const container = document.querySelector("#subtitles-container")
    if (container) {
      const activeSentence = container.querySelector('[data-active="true"]')
      if (activeSentence) {
        const sentenceIdx = parseInt(activeSentence.dataset.sentenceIndex || activeSentence.id.replace("sentence-", ""))
        if (sentenceIdx !== this.currentSentenceIdx) {
          this.currentSentenceIdx = sentenceIdx
          this.scrollToActiveSentence()
          this.lastScrolledSentenceIdx = sentenceIdx
        }
      }
    }
  },

  togglePlay() {
    console.log("[AudioPlayer] togglePlay() called - isPlaying:", this.isPlaying, "sound:", !!this.sound)
    if (this.isPlaying) {
      this.pause()
    } else {
      this.play()
    }
  },

  updatePlayButton() {
    const playButton = this.el.querySelector(".audio-play-button")
    if (!playButton) return

    // Find the icon span (it has class like "hero-play" or "hero-pause")
    const iconSpan = playButton.querySelector("span[class*='hero-']")
    if (!iconSpan) return

    // Remove existing hero icon classes
    const classes = Array.from(iconSpan.classList)
    classes.forEach(cls => {
      if (cls.startsWith("hero-")) {
        iconSpan.classList.remove(cls)
      }
    })

    if (this.isPlaying) {
      // Show pause icon
      iconSpan.classList.add("hero-pause")
      playButton.setAttribute("aria-label", "Pause")
    } else {
      // Show play icon
      iconSpan.classList.add("hero-play")
      playButton.setAttribute("aria-label", "Play")
    }
  },

  play() {
    console.log("[AudioPlayer] play() called - sound:", !!this.sound)
    if (this.sound) {
      const soundId = this.sound.play()
      console.log("[AudioPlayer] play() returned soundId:", soundId)
      if (soundId === undefined) {
        console.error("[AudioPlayer] play() failed - sound might not be loaded")
      }
    } else {
      console.error("[AudioPlayer] play() called but sound is not initialized")
    }
  },

  pause() {
    if (this.sound) {
      this.sound.pause()
    }
  },

  seek(time) {
    if (this.sound) {
      this.sound.seek(time)
    }
  },

  setVolume(volume) {
    if (this.sound) {
      this.sound.volume(volume)
    }
  },

  setPlaybackRate(rate) {
    if (this.sound) {
      this.sound.rate(rate)
      this.playbackRate = rate
    }
  },

  getCurrentTime() {
    return this.sound ? this.sound.seek() || 0 : 0
  },

  getDuration() {
    return this.sound ? this.sound.duration() || 0 : 0
  },

  formatTime(seconds) {
    if (!isFinite(seconds) || seconds < 0) return "0:00"
    const mins = Math.floor(seconds / 60)
    const secs = Math.floor(seconds % 60)
    return `${mins}:${String(secs).padStart(2, '0')}`
  },

  updateTimeDisplay() {
    const timeDisplay = this.el.querySelector("#audio-time-display")
    if (!timeDisplay) return

    const currentTime = this.getCurrentTime()
    const duration = this.getDuration()

    if (duration > 0) {
      timeDisplay.textContent = `${this.formatTime(currentTime)} / ${this.formatTime(duration)}`
    } else {
      timeDisplay.textContent = `${this.formatTime(currentTime)} / --:--`
    }
  },

  updateSeekSlider() {
    const seekSlider = this.el.querySelector("#audio-seek")
    if (!seekSlider) return

    const currentTime = this.getCurrentTime()
    const duration = this.getDuration()

    if (duration > 0) {
      const percentage = (currentTime / duration) * 100
      seekSlider.value = percentage
    } else {
      seekSlider.value = 0
    }
  },

  skipBackward() {
    if (!this.sound) return
    const currentTime = this.getCurrentTime()
    const newTime = Math.max(0, currentTime - 10)
    this.seek(newTime)
    this.updateTimeDisplay()
    this.updateSeekSlider()
  },

  skipForward() {
    if (!this.sound) return
    const currentTime = this.getCurrentTime()
    const duration = this.getDuration()
    const newTime = Math.min(duration, currentTime + 10)
    this.seek(newTime)
    this.updateTimeDisplay()
    this.updateSeekSlider()
  },

  scrollToActiveSentence() {
    const container = document.querySelector("#subtitles-container")
    if (!container) return

    // Try to find active sentence by data attribute first (from LiveView update)
    let activeSentence = container.querySelector('[data-active="true"]')
    
    // Fall back to using currentSentenceIdx from hook
    if (!activeSentence) {
      activeSentence = container.querySelector(`#sentence-${this.currentSentenceIdx}`)
    }
    
    if (!activeSentence) return

    // Calculate the position to scroll to center the active sentence
    const containerRect = container.getBoundingClientRect()
    const sentenceRect = activeSentence.getBoundingClientRect()
    const containerScrollTop = container.scrollTop
    const sentenceOffsetTop = sentenceRect.top - containerRect.top + containerScrollTop

    // Calculate the center position (container height / 2)
    const containerHeight = container.clientHeight
    const targetScrollTop = sentenceOffsetTop - (containerHeight / 2) + (sentenceRect.height / 2)

    // Scroll smoothly to the target position
    container.scrollTo({
      top: Math.max(0, targetScrollTop),
      behavior: "smooth"
    })
  },

  saveListeningPosition(force = false) {
    if (!this.sound) return

    const currentTime = this.getCurrentTime()
    if (!Number.isFinite(currentTime) || currentTime < 0) return

    const shouldSkip =
      !force &&
      typeof this.lastSavedPosition === "number" &&
      Math.abs(currentTime - this.lastSavedPosition) < 0.5

    if (shouldSkip) return

    this.lastSavedPosition = currentTime
    console.log("[AudioPlayer] Saving listening position:", currentTime)
    this.pushEvent("save_listening_position", {position_seconds: currentTime})
  }
}
