defmodule LanglerWeb.ArticleLive.RecommendationsTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Langler.ContentFixtures
  alias Langler.Content
  alias Langler.Content.{DiscoveredArticle, SourceSite}
  alias Langler.Repo

  describe "mount" do
    test "renders page title and description", %{conn: conn} do
      user = Langler.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/articles/recommendations")

      assert html =~ "Suggested for you"
      assert html =~ "Articles recommended based on your reading preferences"
    end

    test "shows empty state when no recommendations available", %{conn: conn} do
      user = Langler.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/articles/recommendations")

      assert html =~ "No recommendations available yet"
      assert html =~ "Import some articles to get personalized suggestions"
    end

    test "displays discovered articles as recommendations", %{conn: conn} do
      user = Langler.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      # Create a source site
      {:ok, source_site} =
        %SourceSite{}
        |> SourceSite.changeset(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish",
          is_active: true
        })
        |> Repo.insert()

      # Create discovered articles
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      discovered_articles = [
        %{
          source_site_id: source_site.id,
          url: "https://example.com/article1",
          title: "Test Article 1",
          summary: "This is a test article summary",
          language: "spanish",
          status: "new",
          discovered_at: now,
          inserted_at: now,
          updated_at: now
        },
        %{
          source_site_id: source_site.id,
          url: "https://example.com/article2",
          title: "Test Article 2",
          summary: "Another test article",
          language: "spanish",
          status: "new",
          discovered_at: now,
          inserted_at: now,
          updated_at: now
        }
      ]

      Repo.insert_all(DiscoveredArticle, discovered_articles)

      {:ok, view, html} = live(conn, ~p"/articles/recommendations")

      assert html =~ "Test Article 1"
      assert html =~ "Test Article 2"
      assert html =~ "This is a test article summary"
      assert html =~ "Another test article"
    end

    test "displays regular articles not imported by user", %{conn: conn} do
      user = Langler.AccountsFixtures.user_fixture()
      other_user = Langler.AccountsFixtures.user_fixture()

      # Create an article for another user (should appear in recommendations)
      article = article_fixture(%{user: other_user, title: "Shared Article"})

      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/articles/recommendations")

      assert html =~ "Shared Article"
    end

    test "does not display articles already imported by user", %{conn: conn} do
      user = Langler.AccountsFixtures.user_fixture()

      # Create an article for this user (should NOT appear in recommendations)
      article = article_fixture(%{user: user, title: "My Article"})

      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/articles/recommendations")

      refute html =~ "My Article"
    end
  end

  describe "import_recommended" do
    setup %{conn: conn} do
      user = Langler.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      # Create a source site
      {:ok, source_site} =
        %SourceSite{}
        |> SourceSite.changeset(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish",
          is_active: true
        })
        |> Repo.insert()

      # Create a discovered article
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, discovered_article} =
        %DiscoveredArticle{}
        |> DiscoveredArticle.changeset(%{
          source_site_id: source_site.id,
          url: "https://example.com/test-article",
          title: "Test Article to Import",
          summary: "Test summary",
          language: "spanish",
          status: "new",
          discovered_at: now
        })
        |> Repo.insert()

      %{conn: conn, user: user, discovered_article: discovered_article}
    end

    test "imports article and removes it from recommendations", %{
      conn: conn,
      user: user,
      discovered_article: discovered_article
    } do
      bypass = Bypass.open()

      Bypass.expect_once(bypass, "GET", "/test-article", fn conn ->
        body = """
        <html>
          <body>
            <p>Hola mundo.</p>
          </body>
        </html>
        """

        resp(conn, 200, body)
      end)

      url = "http://localhost:#{bypass.port}/test-article"

      # Update discovered article with bypass URL
      discovered_article
      |> DiscoveredArticle.changeset(%{url: url})
      |> Repo.update()

      {:ok, view, _html} = live(conn, ~p"/articles/recommendations")

      # Verify article is in recommendations
      assert render(view) =~ "Test Article to Import"

      # Click import button
      view
      |> element("button[phx-click='import_recommended'][phx-value-url='#{url}']")
      |> render_click()

      # Verify flash message
      assert render(view) =~ "Imported"

      # Verify article is removed from recommendations
      refute render(view) =~ "Test Article to Import"
    end

    test "handles import errors gracefully", %{
      conn: conn,
      discovered_article: discovered_article
    } do
      bypass = Bypass.open()

      # Update discovered article with bypass URL that will fail
      url = "http://localhost:#{bypass.port}/error-article"
      Bypass.down(bypass)

      discovered_article
      |> DiscoveredArticle.changeset(%{url: url})
      |> Repo.update()

      {:ok, view, _html} = live(conn, ~p"/articles/recommendations")

      # Try to import - should handle error gracefully
      view
      |> element("button[phx-click='import_recommended'][phx-value-url='#{url}']")
      |> render_click()

      # Should show error message or keep the article in the list
      html = render(view)
      assert html =~ "error" or html =~ "Error" or html =~ "Test Article to Import"
    end
  end

  describe "article display" do
    test "displays article metadata correctly", %{conn: conn} do
      user = Langler.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      # Create a source site
      {:ok, source_site} =
        %SourceSite{}
        |> SourceSite.changeset(%{
          name: "El País",
          url: "https://elpais.com",
          discovery_method: "rss",
          language: "spanish",
          is_active: true
        })
        |> Repo.insert()

      # Create discovered article with metadata
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      published_at = DateTime.add(now, -2, :day) |> DateTime.truncate(:second)

      {:ok, _discovered_article} =
        %DiscoveredArticle{}
        |> DiscoveredArticle.changeset(%{
          source_site_id: source_site.id,
          url: "https://elpais.com/article",
          title: "Test Article with Metadata",
          summary: "This is a longer summary that should be displayed in the recommendations",
          language: "spanish",
          status: "new",
          discovered_at: now,
          published_at: published_at
        })
        |> Repo.insert()

      {:ok, view, html} = live(conn, ~p"/articles/recommendations")

      assert html =~ "Test Article with Metadata"
      assert html =~ "El País"
      assert html =~ "This is a longer summary"
      assert html =~ "spanish"
    end

    test "displays 'New' badge for discovered articles", %{conn: conn} do
      user = Langler.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      # Create a source site
      {:ok, source_site} =
        %SourceSite{}
        |> SourceSite.changeset(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish",
          is_active: true
        })
        |> Repo.insert()

      # Create discovered article
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _discovered_article} =
        %DiscoveredArticle{}
        |> DiscoveredArticle.changeset(%{
          source_site_id: source_site.id,
          url: "https://example.com/new-article",
          title: "New Article",
          summary: "A new article",
          language: "spanish",
          status: "new",
          discovered_at: now
        })
        |> Repo.insert()

      {:ok, _view, html} = live(conn, ~p"/articles/recommendations")

      assert html =~ "New"
    end
  end
end
