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

      _item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(DateTime.utc_now(), -3_600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/study")

      assert html =~ "Due now"
      assert html =~ word.lemma

      assert has_element?(view, "#study-items")
    end

    test "rates a word and updates stats", %{conn: conn} do
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

      view
      |> element("button[phx-value-item-id='#{item.id}'][phx-value-quality='3']")
      |> render_click()

      assert render(view) =~ "Logged review"
      assert render(view) =~ "Due now"
    end
  end
end
