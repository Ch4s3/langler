defmodule LanglerWeb.StudyLive.SessionTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Langler.AccountsFixtures
  alias Langler.Repo
  alias Langler.Study.FSRSItem
  alias Langler.StudyFixtures
  alias Langler.VocabularyFixtures

  describe "mount" do
    test "loads due today cards and initializes session state", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word = VocabularyFixtures.word_fixture(%{definitions: ["test definition"]})

      now = DateTime.utc_now()

      _item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(now, -3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/study/session")

      assert html =~ "Card 1 of 1"
      assert has_element?(view, ".swap-off")
      assert has_element?(view, "#study-session-container")
    end

    test "shows empty state when no cards available", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/study/session")

      assert html =~ "No cards due today"
      assert has_element?(view, "h2", "No cards due today")
    end

    test "only shows cards with words", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word = VocabularyFixtures.word_fixture()

      now = DateTime.utc_now()

      _item_with_word =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(now, -3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/study/session")

      # Should show the card with a word
      assert html =~ "Card 1 of 1"
      assert has_element?(view, ".swap-off")
    end
  end

  describe "card display" do
    test "shows word on front of card", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      word =
        VocabularyFixtures.word_fixture(%{
          normalized_form: "hablar",
          lemma: "hablar"
        })

      now = DateTime.utc_now()

      _item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(now, -3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/study/session")

      assert html =~ "hablar"
      assert has_element?(view, ".swap-off")
    end

    test "shows progress indicator", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word1 = VocabularyFixtures.word_fixture()
      word2 = VocabularyFixtures.word_fixture()

      now = DateTime.utc_now()

      _item1 =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word1,
          due_date: DateTime.add(now, -3600, :second)
        })

      _item2 =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word2,
          due_date: DateTime.add(now, -1800, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/study/session")

      assert html =~ "Card 1 of 2"
    end
  end

  describe "card flip" do
    test "flips card when clicked", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word = VocabularyFixtures.word_fixture(%{definitions: ["to speak"]})

      now = DateTime.utc_now()

      _item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(now, -3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/study/session")

      # Initially, card should not have "flipped" class
      refute html =~ ~r/class="[^"]*flipped/

      html =
        view
        |> element("#study-card")
        |> render_click()

      # After click, card should have "flipped" class
      assert html =~ ~r/class="[^"]*swap-active/
      assert html =~ "to speak"
    end

    test "shows rating buttons after flip", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word = VocabularyFixtures.word_fixture(%{definitions: ["test"]})

      now = DateTime.utc_now()

      _item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(now, -3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study/session")

      view
      |> element("#study-card")
      |> render_click()

      assert has_element?(view, "button[phx-click='rate_card'][phx-value-quality='0']")
      assert has_element?(view, "button[phx-click='rate_card'][phx-value-quality='2']")
      assert has_element?(view, "button[phx-click='rate_card'][phx-value-quality='3']")
      assert has_element?(view, "button[phx-click='rate_card'][phx-value-quality='4']")
    end
  end

  describe "rating and advancement" do
    test "rates card and advances to next", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      word1 =
        VocabularyFixtures.word_fixture(%{
          normalized_form: "hablar",
          lemma: "hablar",
          definitions: ["to speak"]
        })

      word2 =
        VocabularyFixtures.word_fixture(%{
          normalized_form: "comer",
          lemma: "comer",
          definitions: ["to eat"]
        })

      now = DateTime.utc_now()

      item1 =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word1,
          due_date: DateTime.add(now, -3600, :second)
        })

      _item2 =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word2,
          due_date: DateTime.add(now, -1800, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study/session")

      # Flip and rate first card
      view |> element("#study-card") |> render_click()

      html =
        view
        |> element("button[phx-click='rate_card'][phx-value-quality='3']")
        |> render_click()

      # Should show second card (front side, so word should be visible)
      assert html =~ "comer"

      # Verify item was updated
      updated_item = Repo.get!(FSRSItem, item1.id) |> Repo.preload(:word)
      assert updated_item.repetitions > 0
      assert updated_item.last_reviewed_at != nil
    end

    test "updates ratings distribution", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word = VocabularyFixtures.word_fixture(%{definitions: ["test"]})

      now = DateTime.utc_now()

      _item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(now, -3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study/session")

      view |> element("#study-card") |> render_click()

      # Rate as "Good"
      view
      |> element("button[phx-click='rate_card'][phx-value-quality='3']")
      |> render_click()

      # Should show completion screen with rating
      assert render(view) =~ "Good"
    end
  end

  describe "end-to-end study session" do
    test "completes full study session from start to finish", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      word1 =
        VocabularyFixtures.word_fixture(%{
          normalized_form: "hablar",
          lemma: "hablar",
          definitions: ["to speak"]
        })

      word2 =
        VocabularyFixtures.word_fixture(%{
          normalized_form: "comer",
          lemma: "comer",
          definitions: ["to eat"]
        })

      word3 =
        VocabularyFixtures.word_fixture(%{
          normalized_form: "vivir",
          lemma: "vivir",
          definitions: ["to live"]
        })

      now = DateTime.utc_now()

      item1 =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word1,
          due_date: DateTime.add(now, -3600, :second)
        })

      item2 =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word2,
          due_date: DateTime.add(now, -1800, :second)
        })

      item3 =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word3,
          due_date: now
        })

      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/study/session")

      # Verify initial state
      assert html =~ "Card 1 of 3"
      assert has_element?(view, ".swap-off")
      assert render(view) =~ "hablar"

      # Flip first card
      view |> element("#study-card") |> render_click()
      assert has_element?(view, ".swap-on")
      assert render(view) =~ "to speak"

      # Rate first card as "Good"
      view
      |> element("button[phx-click='rate_card'][phx-value-quality='3']")
      |> render_click()

      # Verify second card appears
      assert render(view) =~ "comer"
      assert render(view) =~ "Card 2 of 3"

      # Flip and rate second card as "Easy"
      view |> element("#study-card") |> render_click()

      view
      |> element("button[phx-click='rate_card'][phx-value-quality='4']")
      |> render_click()

      # Verify third card appears
      assert render(view) =~ "vivir"

      # Flip and rate third card as "Hard"
      view |> element("#study-card") |> render_click()

      view
      |> element("button[phx-click='rate_card'][phx-value-quality='2']")
      |> render_click()

      # Verify completion screen appears
      assert has_element?(view, "#study-session-complete")
      assert render(view) =~ "3 cards reviewed"
      assert render(view) =~ "Good"
      assert render(view) =~ "Easy"
      assert render(view) =~ "Hard"

      # Verify items were updated in database
      updated_item1 = Repo.get!(FSRSItem, item1.id) |> Repo.preload(:word)
      assert updated_item1.repetitions > 0
      assert updated_item1.last_reviewed_at != nil

      updated_item2 = Repo.get!(FSRSItem, item2.id) |> Repo.preload(:word)
      assert updated_item2.repetitions > 0

      updated_item3 = Repo.get!(FSRSItem, item3.id) |> Repo.preload(:word)
      assert updated_item3.repetitions > 0
    end
  end

  describe "exit button" do
    test "exit button is visible during card view", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word = VocabularyFixtures.word_fixture()

      now = DateTime.utc_now()

      _item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(now, -3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study/session")

      assert has_element?(view, "#study-session-exit")
    end

    test "exit button navigates to study overview", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word = VocabularyFixtures.word_fixture()

      now = DateTime.utc_now()

      _item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(now, -3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study/session")

      assert view
             |> element("#study-session-exit")
             |> render_click()
             |> follow_redirect(conn, ~p"/study")
    end
  end

  describe "edge cases" do
    test "session with single card completes after rating", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word = VocabularyFixtures.word_fixture(%{definitions: ["test"]})

      now = DateTime.utc_now()

      _item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(now, -3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study/session")

      view |> element("#study-card") |> render_click()

      view
      |> element("button[phx-click='rate_card'][phx-value-quality='3']")
      |> render_click()

      assert has_element?(view, "#study-session-complete")
      assert render(view) =~ "1 cards reviewed"
    end

    test "handles card without definitions gracefully", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word = VocabularyFixtures.word_fixture(%{definitions: []})

      now = DateTime.utc_now()

      _item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(now, -3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study/session")

      view |> element("#study-card") |> render_click()

      assert render(view) =~ "No definition available"
    end
  end

  describe "completion screen" do
    test "shows accurate statistics", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word = VocabularyFixtures.word_fixture(%{definitions: ["test"]})

      now = DateTime.utc_now()

      _item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(now, -3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study/session")

      view |> element("#study-card") |> render_click()

      view
      |> element("button[phx-click='rate_card'][phx-value-quality='3']")
      |> render_click()

      html = render(view)
      assert html =~ "1 cards reviewed"
      assert html =~ "Good"
      # time should be minimal
      assert html =~ "0m"
    end

    test "return link navigates to study overview", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      word = VocabularyFixtures.word_fixture(%{definitions: ["test"]})

      now = DateTime.utc_now()

      _item =
        StudyFixtures.fsrs_item_fixture(%{
          user: user,
          word: word,
          due_date: DateTime.add(now, -3600, :second)
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/study/session")

      view |> element("#study-card") |> render_click()

      view
      |> element("button[phx-click='rate_card'][phx-value-quality='3']")
      |> render_click()

      # Find the "Return to Study Overview" link specifically
      assert view
             |> element("#study-session-complete a:first-of-type")
             |> render_click()
             |> follow_redirect(conn, ~p"/study")
    end
  end
end
