defmodule LanglerWeb.ArticleLive.RecommendationsTest do
  use LanglerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Req.Test, only: [set_req_test_from_context: 1]
  import Langler.ContentFixtures
  alias Langler.Content
  alias Langler.Content.{DiscoveredArticle, SourceSite}
  alias Langler.Repo

  @importer_req Langler.Content.ArticleImporterReq

  setup :set_req_test_from_context
  setup {Req.Test, :verify_on_exit!}

  setup do
    Application.put_env(:langler, Langler.Content.ArticleImporter,
      req_options: [plug: {Req.Test, @importer_req}, retry: false]
    )

    on_exit(fn -> Application.delete_env(:langler, Langler.Content.ArticleImporter) end)

    %{importer: @importer_req}
  end

  describe "render" do
    test "renders page title and description" do
      html = render_recommendations()
      document = document(html)

      assert text_for(document, "h1.section-header__title") =~ "Suggested for you"

      assert text_for(document, "p.section-header__lede") =~
               "Articles recommended based on your reading preferences."
    end

    test "shows empty state when no recommendations available" do
      html = render_recommendations()
      document = document(html)

      empty_text = text_for(document, "div.border-dashed")
      assert empty_text =~ "No recommendations available yet."
      assert empty_text =~ "Import some articles to get personalized suggestions."
    end

    test "displays discovered articles as recommendations" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      articles = [
        %{
          id: nil,
          title: "Test Article 1",
          url: "https://example.com/article1",
          source: "Test Site",
          language: "spanish",
          content: "This is a test article summary",
          inserted_at: now,
          published_at: now,
          is_discovered: true,
          difficulty_score: nil,
          avg_sentence_length: 12.0
        },
        %{
          id: nil,
          title: "Test Article 2",
          url: "https://example.com/article2",
          source: "Test Site",
          language: "spanish",
          content: "Another test article",
          inserted_at: now,
          published_at: now,
          is_discovered: true,
          difficulty_score: nil,
          avg_sentence_length: 12.0
        }
      ]

      html = render_recommendations(%{recommended_articles: articles})
      document = document(html)

      title_text = text_for(document, "p.text-lg")
      summary_text = text_for(document, "p.line-clamp-3")

      assert title_text =~ "Test Article 1"
      assert title_text =~ "Test Article 2"
      assert summary_text =~ "This is a test article summary"
      assert summary_text =~ "Another test article"
    end
  end

  describe "mount" do
    test "displays regular articles not imported by user", %{conn: conn} do
      user = Langler.AccountsFixtures.user_fixture()
      other_user = Langler.AccountsFixtures.user_fixture()

      # Create an article for another user (should appear in recommendations)
      _article = article_fixture(%{user: other_user, title: "Shared Article"})

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/articles/recommendations")

      assert html =~ "Shared Article"
    end

    test "does not display articles already imported by user", %{conn: conn} do
      user = Langler.AccountsFixtures.user_fixture()

      # Create an article for this user (should NOT appear in recommendations)
      _article = article_fixture(%{user: user, title: "My Article"})

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/articles/recommendations")

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

      %{conn: conn, user: user, discovered_article: discovered_article, importer: @importer_req}
    end

    test "imports article and removes it from recommendations", %{
      conn: conn,
      user: _user,
      discovered_article: discovered_article,
      importer: importer
    } do
      Req.Test.expect(importer, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/test-article"

        body = """
        <html>
          <body>
            <p>Hola mundo.</p>
          </body>
        </html>
        """

        Req.Test.html(conn, body)
      end)

      url = "https://article-importer.test/test-article"

      # Update discovered article with bypass URL
      discovered_article
      |> DiscoveredArticle.changeset(%{url: url})
      |> Repo.update()

      {:ok, view, _html} = live(conn, ~p"/articles/recommendations")
      Req.Test.allow(importer, self(), view.pid)

      # Verify article is in recommendations
      assert render(view) =~ "Test Article to Import"

      # Click import button
      view
      |> element("button[phx-click='import_recommended'][phx-value-url='#{url}']")
      |> render_click()

      assert %Content.Article{} = Content.get_article_by_url(url)

      # Verify article is removed from recommendations
      refute render(view) =~ "Test Article to Import"
    end

    test "handles import errors gracefully", %{
      conn: conn,
      discovered_article: discovered_article,
      importer: importer
    } do
      Req.Test.stub(importer, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/error-article"
        Req.Test.transport_error(conn, :econnrefused)
      end)

      # Update discovered article with URL that will fail
      url = "https://article-importer.test/error-article"

      discovered_article
      |> DiscoveredArticle.changeset(%{url: url})
      |> Repo.update()

      {:ok, view, _html} = live(conn, ~p"/articles/recommendations")
      Req.Test.allow(importer, self(), view.pid)

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
    test "displays article metadata correctly" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      published_at = DateTime.add(now, -2, :day) |> DateTime.truncate(:second)

      article = %{
        id: nil,
        title: "Test Article with Metadata",
        url: "https://elpais.com/article",
        source: "El País",
        language: "spanish",
        content: "This is a longer summary that should be displayed in the recommendations",
        inserted_at: now,
        published_at: published_at,
        is_discovered: true,
        difficulty_score: nil,
        avg_sentence_length: 16.0
      }

      html = render_recommendations(%{recommended_articles: [article]})
      document = document(html)

      card_text = text_for(document, ".card-body")

      assert card_text =~ "Test Article with Metadata"
      assert card_text =~ "El País"
      assert card_text =~ "This is a longer summary"
      assert card_text =~ "spanish"
    end

    test "displays 'New' badge for discovered articles" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      article = %{
        id: nil,
        title: "New Article",
        url: "https://example.com/new-article",
        source: "Test Site",
        language: "spanish",
        content: "A new article",
        inserted_at: now,
        published_at: now,
        is_discovered: true,
        difficulty_score: nil,
        avg_sentence_length: 12.0
      }

      html = render_recommendations(%{recommended_articles: [article]})
      document = document(html)

      assert text_for(document, "span.badge") =~ "New"
    end
  end

  defp render_recommendations(assigns \\ %{}) do
    assigns =
      assigns
      |> Map.put_new(:flash, %{})
      |> Map.put_new(:current_scope, nil)
      |> Map.put_new(:importing, false)
      |> Map.put_new(:recommended_articles, [])

    render_component(&LanglerWeb.ArticleLive.Recommendations.render/1, assigns)
  end

  defp document(html), do: LazyHTML.from_fragment(html)

  defp text_for(document, selector) do
    document
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
  end
end
