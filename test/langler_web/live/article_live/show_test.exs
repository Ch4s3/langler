defmodule LanglerWeb.ArticleLive.ShowTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Langler.ContentFixtures

  alias Langler.Accounts.UserLlmConfig
  alias Langler.Content
  alias Langler.Content.ArticleImporter
  alias Langler.Repo
  alias LanglerWeb.ArticleLive.Show
  alias Langler.AccountsFixtures

  describe "show" do
    test "renders article content for associated user", %{conn: conn} do
      user = Langler.AccountsFixtures.user_fixture()
      article = article_fixture(%{user: user})
      _sentence_one = sentence_fixture(article, %{position: 0, content: "Hola mundo."})
      _sentence_two = sentence_fixture(article, %{position: 1, content: "Buenos días."})

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/articles/#{article}")
      rendered = render(view)

      assert rendered =~ article.title
      assert rendered =~ "Hola"
      assert rendered =~ "Buenos"
    end

    test "renders punctuation without extra spaces before commas and periods", %{conn: conn} do
      user = Langler.AccountsFixtures.user_fixture()
      article = article_fixture(%{user: user})
      # Content with correct punctuation spacing
      _sentence = sentence_fixture(article, %{position: 0, content: "Hola, mundo. Buenos días."})

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/articles/#{article}")
      rendered = render(view)

      document = LazyHTML.from_fragment(rendered)
      token_spans = LazyHTML.query(document, "span[id^='token-']")
      token_texts = Enum.map(token_spans, &LazyHTML.text/1)
      article_text = Enum.join(token_texts, "")
      normalized_text = article_text |> String.replace(~r/\s+/, " ") |> String.trim()

      # Should NOT have space before punctuation
      refute normalized_text =~ "Hola ,"
      refute normalized_text =~ "mundo ."
      refute normalized_text =~ "días ."

      # Should have correct spacing
      assert normalized_text =~ "Hola,"
      assert normalized_text =~ "mundo."
      assert normalized_text =~ "días."
    end

    test "renders quotes without extra spaces inside", %{conn: conn} do
      user = Langler.AccountsFixtures.user_fixture()
      article = article_fixture(%{user: user})
      _sentence = sentence_fixture(article, %{position: 0, content: "Dijo \"hola\" y se fue."})

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/articles/#{article}")
      rendered = render(view)

      document = LazyHTML.from_fragment(rendered)
      token_spans = LazyHTML.query(document, "span[id^='token-']")
      token_texts = Enum.map(token_spans, &LazyHTML.text/1)
      article_text = Enum.join(token_texts, "")
      normalized_text = article_text |> String.replace(~r/\s+/, " ") |> String.trim()

      # Should NOT have space after opening quote or before closing quote
      refute normalized_text =~ "\" hola"
      refute normalized_text =~ "hola \""

      # Should have correct spacing
      assert normalized_text =~ "\"hola\""
    end

    test "renders Spanish inverted punctuation correctly", %{conn: conn} do
      user = Langler.AccountsFixtures.user_fixture()
      article = article_fixture(%{user: user})
      _sentence = sentence_fixture(article, %{position: 0, content: "¿Cómo estás? ¡Muy bien!"})

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/articles/#{article}")
      rendered = render(view)

      document = LazyHTML.from_fragment(rendered)
      token_spans = LazyHTML.query(document, "span[id^='token-']")
      token_texts = Enum.map(token_spans, &LazyHTML.text/1)
      article_text = Enum.join(token_texts, "")
      normalized_text = article_text |> String.replace(~r/\s+/, " ") |> String.trim()

      # Should NOT have space after opening punctuation
      refute normalized_text =~ "¿ Cómo"
      refute normalized_text =~ "¡ Muy"

      # Should have correct spacing
      assert normalized_text =~ "¿Cómo"
      assert normalized_text =~ "¡Muy"
    end

    @tag :external
    test "normalizes punctuation spacing in rendered article content", %{conn: conn} do
      user = Langler.AccountsFixtures.user_fixture()

      # Import the real article from El País
      # This test requires network access and is tagged with :external
      url =
        "https://elpais.com/ciencia/2026-01-24/un-beso-esquimal-la-ciencia-explica-el-contacto-nariz-con-nariz-en-los-mamiferos.html"

      assert {:ok, article, _} = ArticleImporter.import_from_url(user, url)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/articles/#{article}")
      rendered = render(view)

      # Extract all token text content from spans with id="token-*"
      document = LazyHTML.from_fragment(rendered)
      token_spans = LazyHTML.query(document, "span[id^='token-']")

      # Get text content from each token span and join them
      token_texts = Enum.map(token_spans, &LazyHTML.text/1)
      article_text = Enum.join(token_texts, "")

      # Normalize whitespace (collapse multiple spaces/newlines to single space for comparison)
      normalized_text =
        article_text
        |> String.replace(~r/\s+/, " ")
        |> String.trim()

      # Assert that punctuation spacing is correct - no spaces before commas, periods, etc.
      # Check for patterns like "word ," or "word ." (space before punctuation)
      refute normalized_text =~ ~r/\w\s+[,\.;:!\?\)\]\}]/
      # Assert no spaces before closing quotes after words
      refute normalized_text =~ ~r/\w\s+[""»›]/
      # Assert no spaces after opening quotes when followed by letters
      refute normalized_text =~ ~r/[""«‹]\s+\w/
      # Assert no spaces inside parentheses
      refute normalized_text =~ ~r/\(\s+/
      refute normalized_text =~ ~r/\s+\)/

      # Check specific problematic patterns from the article
      # The text should have proper spacing like "besos ," -> "besos,"
      # and "catastrófica ", según" -> "catastrófica", según"
      refute normalized_text =~ "besos ,"
      refute normalized_text =~ "catastrófica \","
      refute normalized_text =~ "ciencia \","
      refute normalized_text =~ "Song ,"
      refute normalized_text =~ "que ,"
    end

    test "redirects to /articles with error when article does not exist", %{conn: conn} do
      user = Langler.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      # Try to access a nonexistent article
      {:error, {:live_redirect, %{to: redirect_path, flash: flash}}} =
        live(conn, ~p"/articles/999999")

      assert redirect_path == ~p"/articles"
      assert flash["error"] == "Article not found"
    end
  end

  describe "handle_event" do
    setup do
      user = AccountsFixtures.user_fixture()
      article = article_fixture(%{user: user})
      scope = Langler.AccountsFixtures.user_scope_fixture(user)

      socket =
        build_socket(%{
          current_scope: scope,
          article: article,
          article_topics: [],
          sentence_lookup: %{},
          studied_word_ids: MapSet.new(),
          studied_forms: MapSet.new(),
          study_items_by_word: %{},
          flash: %{}
        })

      %{socket: socket, user: user, article: article, scope: scope}
    end

    test "start_article_chat shows error when no LLM config", %{socket: socket} do
      {:noreply, updated} = Show.handle_event("start_article_chat", %{}, socket)

      assert Phoenix.Flash.get(updated.assigns.flash, :error) =~
               "Add an LLM provider"
    end

    test "start_article_quiz shows error when LLM config missing", %{socket: socket} do
      {:noreply, updated} = Show.handle_event("start_article_quiz", %{}, socket)

      assert Phoenix.Flash.get(updated.assigns.flash, :error) =~
               "Add an LLM provider"
    end

    test "finish_without_quiz marks article finished", %{
      socket: socket,
      user: user,
      article: article
    } do
      assert {:ok, _} = Content.ensure_article_user(article, user.id)

      {:noreply, updated} =
        Show.handle_event("finish_without_quiz", %{}, socket)

      assert Phoenix.Flash.get(updated.assigns.flash, :info) =~ "Article marked as finished"
    end

    test "start_article_chat succeeds when default config exists", %{socket: socket, user: user} do
      Repo.insert!(%UserLlmConfig{
        user_id: user.id,
        provider_name: "test",
        encrypted_api_key: :crypto.strong_rand_bytes(16),
        model: "gpt",
        is_default: true
      })

      {:noreply, updated} = Show.handle_event("start_article_chat", %{}, socket)

      refute Phoenix.Flash.get(updated.assigns.flash, :error)
    end
  end

  defp build_socket(assigns) do
    default_assigns = %{
      __changed__: %{}
    }

    %Phoenix.LiveView.Socket{
      assigns: Map.merge(default_assigns, assigns),
      private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}
    }
  end
end
