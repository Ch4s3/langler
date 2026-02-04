defmodule LanglerWeb.DeckComponentsTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import LanglerWeb.DeckComponents

  alias Phoenix.Component

  describe "deck_card/1" do
    test "renders owned deck with name and word count" do
      deck = %{id: 1, name: "My Deck", description: nil, visibility: "private", is_default: false}

      html =
        render_component(&deck_card/1,
          deck: deck,
          variant: :owned,
          word_count: 5,
          words: [],
          custom_cards: []
        )

      assert html =~ "My Deck"
      assert html =~ "5"
      assert html =~ "cards"
      assert html =~ "Expand"
      assert html =~ "phx-click=\"set_default_deck\""
      assert html =~ "phx-click=\"edit_deck\""
      assert html =~ "phx-click=\"delete_deck\""
    end

    test "renders default deck with star indicator" do
      deck = %{id: 1, name: "Default", description: nil, visibility: "private", is_default: true}

      html =
        render_component(&deck_card/1,
          deck: deck,
          variant: :owned,
          word_count: 0,
          words: [],
          custom_cards: []
        )

      assert html =~ "Default deck"
      assert html =~ "★"
    end

    test "renders followed variant with Unfollow and Copy buttons" do
      deck = %{id: 1, name: "Followed", description: nil, visibility: "public", is_default: false}

      html =
        render_component(&deck_card/1,
          deck: deck,
          variant: :followed,
          word_count: 3,
          words: [],
          custom_cards: [],
          owner: %{email: "owner@example.com"},
          follower_count: 10
        )

      assert html =~ "Followed"
      assert html =~ "Unfollow"
      assert html =~ "Freeze"
      assert html =~ "Copy"
      assert html =~ "owner@example.com"
    end

    test "renders discover variant with Follow and Copy buttons" do
      deck = %{id: 1, name: "Public Deck", description: nil, visibility: "public", is_default: false}

      html =
        render_component(&deck_card/1,
          deck: deck,
          variant: :discover,
          word_count: 0,
          words: [],
          custom_cards: [],
          owner: %{email: "u@ex.com"},
          follower_count: 5
        )

      assert html =~ "Public Deck"
      assert html =~ "Follow"
      assert html =~ "Copy"
    end
  end

  describe "visibility_badge/1" do
    test "renders private badge" do
      html = render_component(&visibility_badge/1, visibility: "private")
      assert html =~ "private"
      assert html =~ "hero-lock-closed"
    end

    test "renders public badge" do
      html = render_component(&visibility_badge/1, visibility: "public")
      assert html =~ "public"
      assert html =~ "hero-globe-alt"
    end

    test "renders shared badge" do
      html = render_component(&visibility_badge/1, visibility: "shared")
      assert html =~ "shared"
      assert html =~ "hero-user-group"
    end
  end

  describe "suggestion_card/1" do
    test "renders suggestion with name, description, and words" do
      suggestion = %{
        name: "Food & Dining",
        description: "Words about meals",
        category: "thematic",
        words: ["comer", "beber", "agua"],
        word_ids: [1, 2, 3],
        confidence: 0.85
      }

      html =
        render_component(&suggestion_card/1,
          suggestion: suggestion,
          index: 0,
          expanded: false
        )

      assert html =~ "Food &amp; Dining"
      assert html =~ "Words about meals"
      assert html =~ "THEMATIC"
      assert html =~ "comer"
      assert html =~ "85% confidence"
      assert html =~ "Dismiss"
      assert html =~ "Create"
    end
  end

  describe "ungrouped_words_banner/1" do
    test "renders banner when count > 0" do
      html = render_component(&ungrouped_words_banner/1, ungrouped_count: 42)
      assert html =~ "42 ungrouped words"
      assert html =~ "Get AI Suggestions"
    end

    test "does not render when count is 0" do
      html = render_component(&ungrouped_words_banner/1, ungrouped_count: 0)
      refute html =~ "ungrouped words"
    end
  end

  describe "deck_modal/1" do
    test "renders create deck form when editing_deck is nil" do
      form = Component.to_form(%{"name" => "", "description" => "", "visibility" => "private"})

      html =
        render_component(&deck_modal/1,
          show: true,
          editing_deck: nil,
          form: form
        )

      assert html =~ "Create new deck"
      assert html =~ "deck-modal-form"
      assert html =~ ~s(phx-submit="create_deck")
    end

    test "renders edit deck form when editing_deck is set" do
      form = Component.to_form(%{"name" => "My Deck", "description" => "", "visibility" => "private"})
      deck = %{id: 123, name: "My Deck"}

      html =
        render_component(&deck_modal/1,
          show: true,
          editing_deck: deck,
          form: form
        )

      assert html =~ "Edit deck"
      assert html =~ ~s(phx-submit="update_deck")
    end
  end
end
