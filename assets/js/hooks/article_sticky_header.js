const clamp = (value, min = 0, max = 1) => Math.min(Math.max(value, min), max)

const ArticleStickyHeader = {
  mounted() {
    this.readerSelector = this.el.dataset.articleTarget
    this.readerEl = this.readerSelector ? document.getElementById(this.readerSelector) : null
    this.heroContent = this.el.querySelector(".card-body") || this.el.firstElementChild
    this.progressFill = this.el.querySelector("[data-progress-fill]")
    this.navEl = document.querySelector(".primary-nav")
    this.cardHeight = this.el.offsetHeight
    this.initialOffsetTop = this.el.getBoundingClientRect().top + window.scrollY
    this.isStuck = false

    this.measureArticle()

    this.handleScroll = this.handleScroll.bind(this)
    this.handleResize = this.handleResize.bind(this)

    window.addEventListener("scroll", this.handleScroll, {passive: true})
    window.addEventListener("resize", this.handleResize)

    this.handleScroll()
  },
  destroyed() {
    window.removeEventListener("scroll", this.handleScroll)
    window.removeEventListener("resize", this.handleResize)
    if (this.navEl) {
      this.navEl.classList.remove("nav--unpinned")
    }
  },
  measureArticle() {
    if (!this.readerEl) return
    const rect = this.readerEl.getBoundingClientRect()
    this.articleTop = rect.top + window.scrollY
    this.articleBottom = rect.bottom + window.scrollY
    this.articleHeight = Math.max(this.articleBottom - this.articleTop, 1)
  },
  handleResize() {
    this.cardHeight = this.el.offsetHeight
    this.initialOffsetTop = this.el.getBoundingClientRect().top + window.scrollY
    this.measureArticle()
    this.handleScroll()
  },
  handleScroll() {
    const scrollY = window.scrollY || window.pageYOffset
    const viewportBreakpoint = window.innerWidth < 640
    const heroRect = this.heroContent
      ? this.heroContent.getBoundingClientRect()
      : this.el.getBoundingClientRect()
    this.heroBottom = heroRect.bottom + scrollY
    const hysteresis = viewportBreakpoint ? 6 : 12
    const heroTopViewport = heroRect.top

    let shouldStick = this.isStuck

    if (heroTopViewport <= -hysteresis) {
      shouldStick = true
    } else if (heroTopViewport >= hysteresis) {
      shouldStick = false
    }

    if (!this.heroContent && this.readerEl) {
      const readerTopViewport = this.readerEl.getBoundingClientRect().top
      if (readerTopViewport <= -hysteresis) {
        shouldStick = true
      } else if (readerTopViewport >= hysteresis) {
        shouldStick = false
      }
    }

    if (!shouldStick) {
      const fallbackOffset = viewportBreakpoint ? 60 : Math.max(this.cardHeight - 140, 140)
      const stickThreshold = this.initialOffsetTop + fallbackOffset
      shouldStick = scrollY > stickThreshold
    }

    if (shouldStick !== this.isStuck) {
      this.isStuck = shouldStick
      this.el.classList.toggle("article-meta--stuck", shouldStick)
      if (this.navEl) {
        this.navEl.classList.toggle("nav--unpinned", shouldStick)
      }
    }

    this.updateProgress(scrollY)
  },
  updateProgress(scrollY) {
    if (!this.readerEl || !this.progressFill) return

    const heroInfluence = this.heroBottom
      ? this.heroBottom - window.innerHeight * 0.25
      : this.articleTop
    const start = Math.min(this.articleTop, heroInfluence)
    const end = this.articleBottom - window.innerHeight
    const denominator = Math.max(end - start, 1)
    const progress = clamp((scrollY - start) / denominator)

    this.progressFill.style.transform = `scaleX(${progress})`
  },
}

export default ArticleStickyHeader
