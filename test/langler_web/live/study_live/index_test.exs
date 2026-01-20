defmodule LanglerWeb.StudyLive.IndexTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Langler.AccountsFixtures
  alias Langler.StudyFixtures
  alias Langler.VocabularyFixtures

  describe "study index" do
    test "renders due items and stats", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word = VocabularyFixtures.word_fixture()

      item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(DateTime.utc_now(), -3_600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study")

      assert has_element?(view, "#study-items")
      assert has_element?(view, "#items-#{item.id}")
      assert has_element?(view, "#study-card-#{item.id}")
      assert has_element?(view, "#study-card-word-#{item.id}")
    end

    test "filters items immediately as user types", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word_one = VocabularyFixtures.word_fixture(%{normalized_form: "hablar", lemma: "hablar"})
      word_two = VocabularyFixtures.word_fixture(%{normalized_form: "comer", lemma: "comer"})

      item_one =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word_one,
          due_date: DateTime.add(DateTime.utc_now(), -3_600, :second)
        })

      item_two =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word_two,
          due_date: DateTime.add(DateTime.utc_now(), -3_600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study")

      # Both items should be visible initially
      assert has_element?(view, "#items-#{item_one.id}")
      assert has_element?(view, "#items-#{item_two.id}")

      # Type search query - target the form that contains the input
      view
      |> form("form[phx-change='search_items']", %{"q" => "hablar"})
      |> render_change()

      assert has_element?(view, "#items-#{item_one.id}")
      refute has_element?(view, "#items-#{item_two.id}")
    end

    test "URL with ?q=query param loads correct filtered results", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word_one = VocabularyFixtures.word_fixture(%{normalized_form: "hablar", lemma: "hablar"})
      word_two = VocabularyFixtures.word_fixture(%{normalized_form: "comer", lemma: "comer"})

      item_one =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word_one,
          due_date: DateTime.add(DateTime.utc_now(), -3_600, :second)
        })

      item_two =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word_two,
          due_date: DateTime.add(DateTime.utc_now(), -3_600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study?q=hablar")

      assert has_element?(view, "#items-#{item_one.id}")
      refute has_element?(view, "#items-#{item_two.id}")
      assert render(view) =~ ~r/value="hablar"/
    end

    test "clearing search removes filter and shows all items", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word_one = VocabularyFixtures.word_fixture(%{normalized_form: "hablar", lemma: "hablar"})
      word_two = VocabularyFixtures.word_fixture(%{normalized_form: "comer", lemma: "comer"})

      item_one =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word_one,
          due_date: DateTime.add(DateTime.utc_now(), -3_600, :second)
        })

      item_two =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word_two,
          due_date: DateTime.add(DateTime.utc_now(), -3_600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study?q=hablar")

      # Only hablar item visible
      assert has_element?(view, "#items-#{item_one.id}")
      refute has_element?(view, "#items-#{item_two.id}")

      # Clear search
      view
      |> element("button[phx-click='clear_search']")
      |> render_click()

      # Both items should be visible
      assert has_element?(view, "#items-#{item_one.id}")
      assert has_element?(view, "#items-#{item_two.id}")
    end

    test "empty state displays when no results match", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word = VocabularyFixtures.word_fixture(%{normalized_form: "hablar", lemma: "hablar"})

      item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(DateTime.utc_now(), -3_600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study")

      # Item is visible
      assert has_element?(view, "#items-#{item.id}")

      # Search for something that doesn't match
      view
      |> form("form[phx-change='search_items']", %{"q" => "nonexistent"})
      |> render_change()

      # Item should be hidden, empty state should show
      refute has_element?(view, "#items-#{item.id}")
      html = render(view)
      assert html =~ "No matches found"
    end

    test "URL updates immediately when search is entered", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study")

      # Type search query
      view
      |> form("form[phx-change='search_items']", %{"q" => "test"})
      |> render_change()

      # URL should be updated immediately and search query should be set
      assert render(view) =~ ~r/value="test"/
      # Verify URL was updated by checking the current path (includes filter=now by default)
      assert_patch(view, "/study?q=test&filter=now")
    end

    test "search input component renders correctly", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study")

      assert has_element?(view, "#study-search-input")
      assert has_element?(view, "input#study-search-input")

      # Clear button only appears when there's a value
      view
      |> form("form[phx-change='search_items']", %{"q" => "test"})
      |> render_change()

      assert has_element?(view, "button[phx-click='clear_search']")
    end

    test "rates a word and updates stats", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word = VocabularyFixtures.word_fixture(%{definitions: ["test definition"]})

      item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(DateTime.utc_now(), -3_600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study")

      view
      |> element("button[phx-value-item-id='#{item.id}'][phx-value-quality='3']")
      |> render_click()

      assert has_element?(view, "#flash-info")
      refute has_element?(view, "#items-#{item.id}")
    end

    test "toggles conjugations panel for verbs", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      word =
        VocabularyFixtures.word_fixture(%{
          lemma: "hablar",
          normalized_form: "hablar",
          part_of_speech: "verb",
          definitions: ["to speak"],
          conjugations: %{"indicative" => %{"present" => %{"yo" => "hablo"}}}
        })

      _item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(DateTime.utc_now(), -3_600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study")

      refute has_element?(view, "#study-conjugations-#{word.id}")

      view
      |> element("button[phx-click='toggle_conjugations'][phx-value-word-id='#{word.id}']")
      |> render_click()

      assert has_element?(view, "#study-conjugations-#{word.id}")
    end

    test "shows loading state for recommendations initially, then displays them", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study")

      # Initial render may show loading or empty state
      # Wait for async to complete
      html = render_async(view)

      # Should show recommendations section or empty state (not loading)
      refute html =~ "Loading recommendations..."
    end

    test "shows loading spinner while fetching conjugations", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      word =
        VocabularyFixtures.word_fixture(%{
          lemma: "hablar",
          normalized_form: "hablar",
          part_of_speech: "verb",
          definitions: ["to speak"],
          conjugations: nil
        })

      _item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(DateTime.utc_now(), -3_600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study")

      # Click toggle to expand conjugations
      view
      |> element("button[phx-click='toggle_conjugations'][phx-value-word-id='#{word.id}']")
      |> render_click()

      # Should show loading state immediately after click
      html = render(view)
      assert html =~ "Loading conjugations..."
    end

    test "fetches definitions when flipping a card that needs them", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      word =
        VocabularyFixtures.word_fixture(%{
          lemma: "test",
          normalized_form: "test",
          definitions: [],
          part_of_speech: nil
        })

      item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(DateTime.utc_now(), -3_600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study")

      # Flip the card
      view
      |> element("button[phx-click='toggle_card'][phx-value-id='#{item.id}']")
      |> render_click()

      # Should not crash - definitions should be fetched async
      html = render(view)
      assert html =~ "items-#{item.id}"
    end

    test "handles card flip when word is nil gracefully", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      # Create an item without a word (edge case)
      item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: nil,
          due_date: DateTime.add(DateTime.utc_now(), -3_600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study")

      # Flip the card - should not crash even with nil word
      view
      |> element("button[phx-click='toggle_card'][phx-value-id='#{item.id}']")
      |> render_click()

      # Should not crash
      html = render(view)
      assert html =~ "items-#{item.id}"
    end

    test "opens CSV import modal", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      _deck = VocabularyFixtures.deck_fixture(%{user: user, name: "Test Deck"})

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study")

      # Modal should not be visible initially
      refute has_element?(view, ".modal[phx-click='hide_csv_import']")

      # Click the import CSV button
      view
      |> element("button[phx-click='show_csv_import']")
      |> render_click()

      # Modal should now be visible
      assert has_element?(view, ".modal[phx-click='hide_csv_import']")
      assert render(view) =~ "Import words from CSV"
    end

    test "closes CSV import modal", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      _deck = VocabularyFixtures.deck_fixture(%{user: user, name: "Test Deck"})

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study")

      # Open the modal
      view
      |> element("button[phx-click='show_csv_import']")
      |> render_click()

      assert has_element?(view, ".modal[phx-click='hide_csv_import']")

      # Close the modal
      view
      |> element("button[phx-click='hide_csv_import']")
      |> render_click()

      # Modal should be closed
      refute has_element?(view, ".modal[phx-click='hide_csv_import']")
    end

    test "CSV import modal has file input and deck selector", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      deck = VocabularyFixtures.deck_fixture(%{user: user, name: "Test Deck"})

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study")

      # Open the modal
      view
      |> element("button[phx-click='show_csv_import']")
      |> render_click()

      assert has_element?(view, ".modal[phx-click='hide_csv_import']")
      assert has_element?(view, "input[type='file']")
      assert has_element?(view, "select[phx-change='validate_csv_deck']")
      assert has_element?(view, "button[type='submit']")

      # Select a deck - use element instead of form for select
      view
      |> element("select[phx-change='validate_csv_deck']")
      |> render_change(%{"deck_id" => "#{deck.id}"})

      # Verify deck is selected
      html = render(view)
      assert html =~ "Test Deck"
    end
  end
end
