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
  end
end
