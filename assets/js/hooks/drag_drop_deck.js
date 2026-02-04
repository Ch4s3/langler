/**
 * DraggableWord hook - Makes word/card rows draggable
 */
const DraggableWord = {
  mounted() {
    this.el.addEventListener("dragstart", (e) => {
      const wordId = this.el.dataset.wordId;
      const deckId = this.el.dataset.deckId;
      const cardType = this.el.dataset.cardType || "word";

      // Set drag data
      e.dataTransfer.setData(
        "application/json",
        JSON.stringify({
          wordId,
          fromDeckId: deckId,
          cardType,
        })
      );
      e.dataTransfer.effectAllowed = "move";

      // Create ghost element
      const ghost = this.el.cloneNode(true);
      ghost.classList.add(
        "bg-base-100",
        "shadow-lg",
        "rounded-lg",
        "p-2",
        "border-2",
        "border-primary"
      );
      ghost.style.width = `${this.el.offsetWidth}px`;
      document.body.appendChild(ghost);
      e.dataTransfer.setDragImage(ghost, 20, 20);
      setTimeout(() => ghost.remove(), 0);

      // Add dragging state
      this.el.classList.add("opacity-50", "bg-base-200");

      // Notify other decks to show drop zones
      document.querySelectorAll("[data-deck-id]").forEach((deck) => {
        if (deck.dataset.deckId !== deckId) {
          deck.classList.add("ring-2", "ring-dashed", "ring-primary/30");
        }
      });
    });

    this.el.addEventListener("dragend", (e) => {
      this.el.classList.remove("opacity-50", "bg-base-200");
      document.querySelectorAll("[data-deck-id]").forEach((deck) => {
        deck.classList.remove(
          "ring-2",
          "ring-dashed",
          "ring-primary/30",
          "ring-primary",
          "bg-primary/5"
        );
      });
    });
  },
};

/**
 * DeckDropZone hook - Makes deck cards accept dropped words/cards
 */
const DeckDropZone = {
  mounted() {
    this.el.addEventListener("dragover", (e) => {
      e.preventDefault();
      e.dataTransfer.dropEffect = "move";

      // Replace dashed ring with solid ring on hover
      this.el.classList.remove("ring-dashed", "ring-primary/30");
      this.el.classList.add("ring-2", "ring-primary", "bg-primary/5");
    });

    this.el.addEventListener("dragleave", (e) => {
      // Only remove if actually leaving the drop zone
      if (!this.el.contains(e.relatedTarget)) {
        this.el.classList.remove("ring-primary", "bg-primary/5");
        this.el.classList.add("ring-dashed", "ring-primary/30");
      }
    });

    this.el.addEventListener("drop", (e) => {
      e.preventDefault();
      this.el.classList.remove(
        "ring-2",
        "ring-dashed",
        "ring-primary/30",
        "ring-primary",
        "bg-primary/5"
      );

      try {
        const data = JSON.parse(e.dataTransfer.getData("application/json"));
        const toDeckId = this.el.dataset.deckId;

        if (data.fromDeckId !== toDeckId) {
          this.pushEvent("move_word_between_decks", {
            word_id: data.wordId,
            from_deck_id: data.fromDeckId,
            to_deck_id: toDeckId,
            card_type: data.cardType,
          });
        }
      } catch (err) {
        console.error("Drop error:", err);
      }
    });
  },
};

export { DraggableWord, DeckDropZone };
