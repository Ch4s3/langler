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

    test "filters items based on search query", %{conn: conn} do
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

      view
      |> element("#study-search-form")
      |> render_change(%{"search_query" => "hablar"})

      assert has_element?(view, "#items-#{item_one.id}")
      refute has_element?(view, "#items-#{item_two.id}")
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
  end
end
