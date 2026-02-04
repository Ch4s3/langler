defmodule LanglerWeb.DeckLive.IndexTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Langler.AccountsFixtures
  import Langler.VocabularyFixtures

  alias Langler.Vocabulary

  describe "deck kebab menu actions" do
    setup %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      # Ensure user has default deck (visit triggers creation)
      _ = Vocabulary.get_or_create_default_deck(user.id)
      # Create a second, non-default deck for testing
      other_deck = deck_fixture(%{user: user, name: "To Edit or Delete", is_default: false})
      %{conn: conn, user: user, other_deck: other_deck}
    end

    test "set_default_deck updates default and refreshes list", %{conn: conn, user: user, other_deck: other_deck} do
      {:ok, view, _html} = live(conn, ~p"/decks")

      view
      |> element("#deck-card-#{other_deck.id} button[phx-click='set_default_deck'][phx-value-deck-id='#{other_deck.id}']")
      |> render_click()

      assert render(view) =~ "Default deck updated"
      refute render(view) =~ "Could not set default deck"

      # Default deck in DB should now be the one we set
      {:ok, default_deck} = Vocabulary.get_or_create_default_deck(user.id)
      assert default_deck.id == other_deck.id
    end

    test "edit_deck opens modal with deck data and update_deck saves", %{conn: conn, other_deck: other_deck} do
      {:ok, view, _html} = live(conn, ~p"/decks")

      view
      |> element("#deck-card-#{other_deck.id} button[phx-click='edit_deck'][phx-value-deck-id='#{other_deck.id}']")
      |> render_click()

      assert has_element?(view, "#deck-modal-form")
      assert view |> element("#deck-modal-form input[name='name']") |> render() =~ "To Edit or Delete"

      view
      |> form("#deck-modal-form", %{"name" => "Updated Name", "description" => "New desc", "visibility" => "private", "deck_id" => "#{other_deck.id}"})
      |> render_submit()

      assert render(view) =~ "Deck updated"

      # Deck name updated in list
      assert render(view) =~ "Updated Name"
    end

    test "set_visibility opens edit modal", %{conn: conn, other_deck: other_deck} do
      {:ok, view, _html} = live(conn, ~p"/decks")

      view
      |> element("#deck-card-#{other_deck.id} button[phx-click='set_visibility'][phx-value-deck-id='#{other_deck.id}']")
      |> render_click()

      assert has_element?(view, "#deck-modal-form")
    end

    test "delete_deck removes deck and shows flash", %{conn: conn, other_deck: other_deck} do
      {:ok, view, _html} = live(conn, ~p"/decks")

      assert has_element?(view, "#deck-card-#{other_deck.id}")

      view
      |> element("#deck-card-#{other_deck.id} button[phx-click='delete_deck'][phx-value-deck-id='#{other_deck.id}']")
      |> render_click()

      assert render(view) =~ "Deck deleted"
      refute has_element?(view, "#deck-card-#{other_deck.id}")
    end
  end

  describe "decks index" do
    test "requires authentication", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/decks")
      assert path == ~p"/users/log-in"
    end

    test "renders my decks tab with create button", %{conn: conn} do
      user = user_fixture()
      _ = Vocabulary.get_or_create_default_deck(user.id)

      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/decks")

      assert html =~ "Decks"
      assert html =~ "My Decks"
      assert html =~ "Create New Deck"
    end

    test "create new deck opens modal and submit creates deck", %{conn: conn} do
      user = user_fixture()
      _ = Vocabulary.get_or_create_default_deck(user.id)

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/decks")

      refute has_element?(view, "#deck-modal-form")

      view
      |> element("button", "Create New Deck")
      |> render_click()

      assert has_element?(view, "#deck-modal-form")

      view
      |> form("#deck-modal-form", %{
        "name" => "My New Deck",
        "description" => "A test deck",
        "visibility" => "private"
      })
      |> render_submit()

      assert render(view) =~ "Deck created"
      assert render(view) =~ "My New Deck"
    end

    test "toggle deck expanded loads and shows deck contents", %{conn: conn} do
      user = user_fixture()
      _ = Vocabulary.get_or_create_default_deck(user.id)
      deck = deck_fixture(%{user: user, name: "Expandable Deck"})
      word = word_fixture()
      Vocabulary.add_word_to_deck(deck.id, word.id, user.id)

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/decks")

      refute has_element?(view, "tr#word-row-#{deck.id}-#{word.id}")

      view
      |> element("#deck-card-#{deck.id} button", "Expand")
      |> render_click()

      assert has_element?(view, "tr#word-row-#{deck.id}-#{word.id}")
    end
  end
end
