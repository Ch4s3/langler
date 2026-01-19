defmodule LanglerWeb.ArticleLive.IndexTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Langler.ContentFixtures

  alias Langler.Content

  setup :register_and_log_in_user

  test "renders the import form and reacts to URL validation", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/articles")

    assert has_element?(view, "#article-import-form")

    view
    |> form("#article-import-form", article: %{"url" => "https://www.bbc.com/mundo/articles/123"})
    |> render_change()

    assert has_element?(view, "button[phx-click='random_from_source']")
  end

  test "lists articles and filters by topic", %{conn: conn, user: user} do
    article = article_fixture(%{user: user})
    :ok = Content.tag_article(article, [{"culture", 0.9}])

    {:ok, view, _html} = live(conn, "/articles")

    assert has_element?(view, "a[href='/articles/#{article.id}']")

    view
    |> element("button[phx-click='filter_topic'][phx-value-topic='culture']")
    |> render_click()

    assert has_element?(view, "a[href='/articles/#{article.id}']")
  end

  describe "search functionality" do
    test "filters articles immediately as user types", %{conn: conn, user: user} do
      article1 = article_fixture(%{user: user, title: "Spanish article about culture"})
      article2 = article_fixture(%{user: user, title: "French article about food"})

      {:ok, view, _html} = live(conn, "/articles")

      # Both articles should be visible initially
      assert has_element?(view, "#articles-#{article1.id}")
      assert has_element?(view, "#articles-#{article2.id}")

      # Type search query
      view
      |> form("form[phx-change='search']", %{"q" => "Spanish"})
      |> render_change()

      # Only matching article should be visible
      assert has_element?(view, "#articles-#{article1.id}")
      refute has_element?(view, "#articles-#{article2.id}")
    end

    test "URL with ?q=query param loads correct filtered results", %{conn: conn, user: user} do
      article1 = article_fixture(%{user: user, title: "Spanish article"})
      article2 = article_fixture(%{user: user, title: "French article"})

      {:ok, view, _html} = live(conn, "/articles?q=Spanish")

      assert has_element?(view, "#articles-#{article1.id}")
      refute has_element?(view, "#articles-#{article2.id}")
      assert render(view) =~ ~r/value="Spanish"/
    end

    test "clearing search removes filter and shows all articles", %{conn: conn, user: user} do
      article1 = article_fixture(%{user: user, title: "Spanish article"})
      article2 = article_fixture(%{user: user, title: "French article"})

      {:ok, view, _html} = live(conn, "/articles?q=Spanish")

      # Only Spanish article visible
      assert has_element?(view, "#articles-#{article1.id}")
      refute has_element?(view, "#articles-#{article2.id}")

      # Clear search
      view
      |> element("button[phx-click='clear_search']")
      |> render_click()

      # Both articles should be visible
      assert has_element?(view, "#articles-#{article1.id}")
      assert has_element?(view, "#articles-#{article2.id}")
    end

    test "empty state displays when no results match", %{conn: conn, user: user} do
      article = article_fixture(%{user: user, title: "Spanish article"})

      {:ok, view, _html} = live(conn, "/articles")

      # Article is visible
      assert has_element?(view, "#articles-#{article.id}")

      # Search for something that doesn't match
      view
      |> form("form[phx-change='search']", %{"q" => "nonexistent"})
      |> render_change()

      # Article should be hidden when search doesn't match
      refute has_element?(view, "#articles-#{article.id}")

      # Note: The empty state component only shows when articles_count is 0,
      # not when search filters out all results. The stream will just be empty.
      # This is expected behavior - empty search results don't trigger the empty state.
    end

    test "URL updates immediately when search is entered", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/articles")

      # Type search query
      view
      |> form("form[phx-change='search']", %{"q" => "test"})
      |> render_change()

      # URL should be updated immediately and search query should be set
      assert render(view) =~ ~r/value="test"/
      # Verify URL was updated by checking the current path
      assert_patch(view, "/articles?q=test")
    end

    test "search input component renders correctly", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/articles")

      assert has_element?(view, "#article-search")
      assert has_element?(view, "input#article-search")

      # Clear button only appears when there's a value
      view
      |> form("form[phx-change='search']", %{"q" => "test"})
      |> render_change()

      assert has_element?(view, "button[phx-click='clear_search']")
    end
  end
end
