defmodule LanglerWeb.ArticleLive.ShowTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Langler.ContentFixtures

  alias Langler.Accounts.UserLlmConfig
  alias Langler.Content
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
