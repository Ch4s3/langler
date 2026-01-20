defmodule LanglerWeb.StudyComponentsTest do
  use LanglerWeb.ConnCase

  import Phoenix.LiveViewTest
  import LanglerWeb.StudyComponents

  alias Phoenix.Component

  describe "deck_modal/1" do
    test "renders create deck modal when editing_deck is nil" do
      form = Component.to_form(%{"name" => ""})

      html =
        render_component(&deck_modal/1,
          show: true,
          editing_deck: nil,
          form: form
        )

      assert html =~ "Create new deck"
      assert html =~ "Enter deck name"
      assert html =~ ~s(phx-submit="create_deck")
      assert html =~ "Create"
      assert html =~ ~s(input type="hidden" name="deck_id" value="")
    end

    test "renders edit deck modal when editing_deck is provided" do
      form = Component.to_form(%{"name" => "My Deck"})
      deck = %{id: 123, name: "My Deck"}

      html =
        render_component(&deck_modal/1,
          show: true,
          editing_deck: deck,
          form: form
        )

      assert html =~ "Edit deck"
      assert html =~ ~s(phx-submit="update_deck")
      assert html =~ "Update"
      assert html =~ ~s(<input type="hidden" name="deck_id" value="123">)
    end

    test "does not render when show is false" do
      form = Component.to_form(%{"name" => ""})

      html =
        render_component(&deck_modal/1,
          show: false,
          editing_deck: nil,
          form: form
        )

      refute html =~ "Create new deck"
      refute html =~ "Edit deck"
    end

    test "includes form validation attributes" do
      form = Component.to_form(%{"name" => ""})

      html =
        render_component(&deck_modal/1,
          show: true,
          editing_deck: nil,
          form: form
        )

      assert html =~ ~s(phx-change="validate_deck")
      assert html =~ ~s(id="deck-form")
      assert html =~ ~s(input type="text" name="name")
    end

    test "includes modal close handlers" do
      form = Component.to_form(%{"name" => ""})

      html =
        render_component(&deck_modal/1,
          show: true,
          editing_deck: nil,
          form: form
        )

      assert html =~ ~s(phx-click="hide_deck_modal")
      assert html =~ ~s(phx-click-away="hide_deck_modal")
      assert html =~ ~s(phx-click="stop_propagation")
    end
  end

  describe "decks_section/1" do
    test "renders section with title and action buttons" do
      decks = []

      html = render_component(&decks_section/1, decks: decks)

      assert html =~ "Your decks"
      assert html =~ "Import CSV"
      assert html =~ "New deck"
      assert html =~ ~s(phx-click="show_csv_import")
      assert html =~ ~s(phx-click="show_deck_modal")
    end

    test "renders deck cards with name and word count" do
      decks = [
        %{id: 1, name: "Spanish Vocabulary", is_default: true},
        %{id: 2, name: "French Words", is_default: false}
      ]

      html = render_component(&decks_section/1, decks: decks)

      assert html =~ "Spanish Vocabulary"
      assert html =~ "French Words"
      assert html =~ "Default"
    end

    test "shows default badge only for default deck" do
      decks = [
        %{id: 1, name: "Default Deck", is_default: true},
        %{id: 2, name: "Regular Deck", is_default: false}
      ]

      html = render_component(&decks_section/1, decks: decks)

      # Check for badge specifically (badge-primary badge-sm)
      badge_count = html |> String.split("badge-primary badge-sm") |> length() |> Kernel.-(1)
      assert badge_count == 1

      # Verify both decks are rendered
      assert html =~ "Default Deck"
      assert html =~ "Regular Deck"
    end

    test "includes edit and delete actions for each deck" do
      decks = [
        %{id: 1, name: "Test Deck", is_default: false}
      ]

      html = render_component(&decks_section/1, decks: decks)

      assert html =~ ~s(phx-click="edit_deck")
      assert html =~ ~s(phx-click="delete_deck")
      assert html =~ ~s(phx-value-deck_id="1")
    end

    test "hides delete button for default deck" do
      decks = [
        %{id: 1, name: "Default Deck", is_default: true}
      ]

      html = render_component(&decks_section/1, decks: decks)

      # Should have edit button but delete should be conditionally hidden
      assert html =~ ~s(phx-click="edit_deck")
      # The delete button should not appear for default deck due to :if condition
      refute html =~ ~s(phx-click="delete_deck")
    end

    test "includes word count display" do
      decks = [
        %{id: 1, name: "Test Deck", is_default: false}
      ]

      html = render_component(&decks_section/1, decks: decks)

      assert html =~ "words"
    end
  end

  describe "kpi_cards/1" do
    test "renders KPI grid with cards" do
      cards = [
        %{title: "Card 1", value: 10, meta: "Description 1"},
        %{title: "Card 2", value: 20, meta: "Description 2"}
      ]

      html = render_component(&kpi_cards/1, cards: cards)

      assert html =~ "kpi-grid"
      assert html =~ "Card 1"
      assert html =~ "10"
      assert html =~ "Description 1"
      assert html =~ "Card 2"
      assert html =~ "20"
      assert html =~ "Description 2"
    end

    test "renders correct number of cards based on list length" do
      cards = [
        %{title: "One", value: 1, meta: "First"},
        %{title: "Two", value: 2, meta: "Second"},
        %{title: "Three", value: 3, meta: "Third"},
        %{title: "Four", value: 4, meta: "Fourth"}
      ]

      html = render_component(&kpi_cards/1, cards: cards)

      # Count kpi-card divs (class="kpi-card" appears once per card)
      card_count = html |> String.split(~s(class="kpi-card")) |> length() |> Kernel.-(1)
      assert card_count == 4
    end

    test "applies value_class when provided" do
      cards = [
        %{title: "Primary", value: 5, meta: "Test", value_class: "text-primary"},
        %{title: "Secondary", value: 10, meta: "Test", value_class: "text-secondary"},
        %{title: "Default", value: 15, meta: "Test"}
      ]

      html = render_component(&kpi_cards/1, cards: cards)

      assert html =~ ~s(class="kpi-card__value text-primary")
      assert html =~ ~s(class="kpi-card__value text-secondary")
      assert html =~ ~s(class="kpi-card__value text-base-content")
    end

    test "handles empty list" do
      html = render_component(&kpi_cards/1, cards: [])

      assert html =~ "kpi-grid"
      # Should have no kpi-card divs
      refute html =~ "kpi-card"
    end

    test "renders all card fields correctly" do
      cards = [
        %{title: "Test Title", value: 42, meta: "Test meta text", value_class: "text-primary"}
      ]

      html = render_component(&kpi_cards/1, cards: cards)

      assert html =~ "Test Title"
      assert html =~ "42"
      assert html =~ "Test meta text"
      assert html =~ "text-primary"
    end
  end

  describe "study_card/1" do
    test "renders card with word information" do
      item = %{
        id: 1,
        word: %{
          id: 10,
          lemma: "hola",
          normalized_form: "hola",
          definitions: ["hello", "hi"]
        },
        due_date: ~U[2024-01-15 14:30:00Z],
        ease_factor: 2.5,
        interval: 5,
        repetitions: 3,
        quality_history: [3, 4, 3]
      }

      quality_buttons = [
        %{score: 0, label: "Again", class: "btn-error"},
        %{score: 3, label: "Good", class: "btn-primary"},
        %{score: 4, label: "Easy", class: "btn-success"}
      ]

      html =
        render_component(&study_card/1,
          item: item,
          flipped: false,
          definitions_loading: false,
          conjugations_loading: false,
          expanded_conjugations: false,
          quality_buttons: quality_buttons
        )

      assert html =~ "hola"
      assert html =~ "Ease factor"
      assert html =~ "Interval"
      assert html =~ "Repetitions"
    end

    test "shows definition when flipped" do
      item = %{
        id: 1,
        word: %{
          id: 10,
          lemma: "hola",
          normalized_form: "hola",
          definitions: ["hello", "hi"]
        },
        due_date: nil,
        ease_factor: 2.5,
        interval: 0,
        repetitions: 0,
        quality_history: nil
      }

      quality_buttons = [%{score: 3, label: "Good", class: "btn-primary"}]

      html =
        render_component(&study_card/1,
          item: item,
          flipped: true,
          definitions_loading: false,
          conjugations_loading: false,
          expanded_conjugations: false,
          quality_buttons: quality_buttons
        )

      assert html =~ "Definition"
      assert html =~ "hello"
      assert html =~ "hi"
    end

    test "shows loading state for definitions" do
      item = %{
        id: 1,
        word: %{
          id: 10,
          lemma: "hola",
          normalized_form: "hola",
          definitions: []
        },
        due_date: nil,
        ease_factor: 2.5,
        interval: 0,
        repetitions: 0,
        quality_history: nil
      }

      quality_buttons = [%{score: 3, label: "Good", class: "btn-primary"}]

      html =
        render_component(&study_card/1,
          item: item,
          flipped: true,
          definitions_loading: true,
          conjugations_loading: false,
          expanded_conjugations: false,
          quality_buttons: quality_buttons
        )

      assert html =~ "Loading definition"
    end
  end

  describe "recommended_articles_section/1" do
    alias Phoenix.LiveView.AsyncResult

    test "renders loading state when filter is :now" do
      assigns = %{
        recommended_articles: AsyncResult.loading(),
        filter: :now,
        user_level: %{cefr_level: "B1"}
      }

      html = render_component(&recommended_articles_section/1, assigns)

      assert html =~ "Loading recommendations"
    end

    test "does not render when filter is not :now" do
      assigns = %{
        recommended_articles: AsyncResult.loading(),
        filter: :all,
        user_level: %{cefr_level: "B1"}
      }

      html = render_component(&recommended_articles_section/1, assigns)

      refute html =~ "Recommended reading"
    end

    test "renders failed state when filter is :now" do
      assigns = %{
        recommended_articles: AsyncResult.failed(AsyncResult.loading(), :error),
        filter: :now,
        user_level: %{cefr_level: "B1"}
      }

      html = render_component(&recommended_articles_section/1, assigns)

      assert html =~ "Unable to load recommendations"
    end

    test "renders articles when available and filter is :now" do
      articles = [
        %{
          article: %{
            id: 1,
            title: "Test Article",
            url: "https://example.com/article",
            difficulty_score: 5.5,
            avg_sentence_length: 12.3
          },
          score: 0.85
        }
      ]

      assigns = %{
        recommended_articles: AsyncResult.ok(articles),
        filter: :now,
        user_level: %{cefr_level: "B1"}
      }

      html = render_component(&recommended_articles_section/1, assigns)

      assert html =~ "Recommended reading"
      assert html =~ "Test Article"
      assert html =~ "B1"
      assert html =~ "85%"
      assert html =~ ~s(phx-click="import_article")
    end

    test "does not render when articles list is empty" do
      assigns = %{
        recommended_articles: AsyncResult.ok([]),
        filter: :now,
        user_level: %{cefr_level: "B1"}
      }

      html = render_component(&recommended_articles_section/1, assigns)

      refute html =~ "Recommended reading"
    end
  end
end
