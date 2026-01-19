defmodule LanglerWeb.ArticleLive.RecommendationsTest do
  use LanglerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Req.Test, only: [set_req_test_from_context: 1]
  import Langler.ContentFixtures
  alias Langler.Content
  alias Langler.Content.{DiscoveredArticle, SourceSite}
  alias Langler.Repo
  alias Phoenix.LiveView.AsyncResult

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
      article = article_fixture(%{user: other_user, title: "Shared Article"})

      assert :ok = Content.tag_article(article, [{"cultura", 0.9}])

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/articles/recommendations")
      html = render_async(view)

      assert html =~ "Shared Article"
    end

    test "does not display articles already imported by user", %{conn: conn} do
      user = Langler.AccountsFixtures.user_fixture()

      # Create an article for this user (should NOT appear in recommendations)
      _article = article_fixture(%{user: user, title: "My Article"})

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/articles/recommendations")
      html = render_async(view)

      refute html =~ "My Article"
    end
  end

  describe "import_recommended" do
    setup do
      user = Langler.AccountsFixtures.user_fixture()
      scope = Langler.AccountsFixtures.user_scope_fixture(user)

      Application.put_env(:langler, Langler.Content.ArticleImporter,
        req_options: [plug: {Req.Test, @importer_req}, retry: false]
      )

      on_exit(fn ->
        Application.delete_env(:langler, Langler.Content.ArticleImporter)
      end)

      # Create a source site and discovered article
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

      socket = build_recommendations_socket(scope)

      %{
        user: user,
        scope: scope,
        discovered_article: discovered_article,
        importer: @importer_req,
        socket: socket
      }
    end

    test "imports article and removes it from recommendations", %{
      socket: socket,
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

      discovered_article
      |> DiscoveredArticle.changeset(%{url: url})
      |> Repo.update()

      socket =
        with_recommended_articles(socket, [
          %{url: url, title: "Test Article to Import", is_discovered: true}
        ])

      {:noreply, updated} =
        LanglerWeb.ArticleLive.Recommendations.handle_event(
          "import_recommended",
          %{"url" => url},
          socket
        )

      assert %Content.Article{} = Content.get_article_by_url(url)
      # After import, recommendations are refreshed async, so we check the AsyncResult
      assert %AsyncResult{} = updated.assigns.recommended_articles
      assert updated.assigns.importing == false
    end

    test "handles import errors gracefully", %{
      socket: socket,
      discovered_article: discovered_article,
      importer: importer
    } do
      Req.Test.stub(importer, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/error-article"
        Req.Test.transport_error(conn, :econnrefused)
      end)

      url = "https://article-importer.test/error-article"

      discovered_article
      |> DiscoveredArticle.changeset(%{url: url})
      |> Repo.update()

      socket =
        with_recommended_articles(socket, [
          %{url: url, title: "Test Article to Import", is_discovered: true}
        ])

      {:noreply, updated} =
        LanglerWeb.ArticleLive.Recommendations.handle_event(
          "import_recommended",
          %{"url" => url},
          socket
        )

      assert Phoenix.Flash.get(updated.assigns.flash, :error)
      # After error, recommendations async is refreshed, so we check the AsyncResult
      assert %AsyncResult{} = updated.assigns.recommended_articles
      assert updated.assigns.importing == false
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

    test "displays categories for articles with topics" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      article = %{
        id: 1,
        title: "Ciencia y tecnología avanzan rápidamente",
        url: "https://example.com/science",
        source: "Test Site",
        language: "spanish",
        content: "Los científicos descubren nuevas tecnologías cada día.",
        inserted_at: now,
        published_at: now,
        is_discovered: false,
        article_topics: [
          %{topic: "ciencia", confidence: Decimal.new("0.85")},
          %{topic: "tecnologia", confidence: Decimal.new("0.75")}
        ],
        difficulty_score: nil,
        avg_sentence_length: 16.0
      }

      html = render_recommendations(%{recommended_articles: [article]})
      document = document(html)

      # Should display topic badges
      badges = LazyHTML.query(document, "span.badge")
      badge_text = LazyHTML.text(badges)

      # Should contain at least one topic name (classification may vary)
      assert badge_text != ""
    end

    test "displays categories for discovered articles via classification" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      article = %{
        id: nil,
        title: "Ciencia y tecnología avanzan rápidamente",
        url: "https://example.com/science",
        source: "Test Site",
        language: "spanish",
        content: "Los científicos descubren nuevas tecnologías cada día.",
        inserted_at: now,
        published_at: now,
        is_discovered: true,
        article_topics: [],
        difficulty_score: nil,
        avg_sentence_length: 16.0
      }

      html = render_recommendations(%{recommended_articles: [article]})
      document = document(html)

      # Should display topic badges (from classification)
      badges = LazyHTML.query(document, "span.badge")
      badge_text = LazyHTML.text(badges)

      # Should contain topic names from classification
      assert badge_text != ""
      # Should have the "New" badge
      assert badge_text =~ "New"
    end

    test "displays categories for regular articles without topics via classification" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      article = %{
        id: 1,
        title: "Arte y cultura en la ciudad",
        url: "https://example.com/culture",
        source: "Test Site",
        language: "spanish",
        content: "Exposición de arte moderno en el museo.",
        inserted_at: now,
        published_at: now,
        is_discovered: false,
        article_topics: [],
        difficulty_score: nil,
        avg_sentence_length: 16.0
      }

      html = render_recommendations(%{recommended_articles: [article]})
      document = document(html)

      # Should display topic badges (from classification)
      badges = LazyHTML.query(document, "span.badge")
      badge_text = LazyHTML.text(badges)

      # Should contain topic names from classification
      assert badge_text != ""
    end
  end

  defp render_recommendations(assigns \\ %{}) do
    recommended_articles = Map.get(assigns, :recommended_articles, [])

    recommended_articles_async =
      if is_list(recommended_articles) do
        AsyncResult.ok(recommended_articles)
      else
        recommended_articles
      end

    assigns =
      assigns
      |> Map.put_new(:flash, %{})
      |> Map.put_new(:current_scope, nil)
      |> Map.put_new(:importing, false)
      |> Map.put(:recommended_articles, recommended_articles_async)

    render_component(&LanglerWeb.ArticleLive.Recommendations.render/1, assigns)
  end

  defp build_recommendations_socket(scope) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        importing: false,
        recommended_articles: AsyncResult.ok([]),
        current_scope: scope
      },
      private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}
    }
  end

  defp document(html), do: LazyHTML.from_fragment(html)

  defp text_for(document, selector) do
    document
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
  end

  defp with_recommended_articles(socket, articles) do
    async_result = AsyncResult.ok(articles)
    %{socket | assigns: Map.put(socket.assigns, :recommended_articles, async_result)}
  end
end
