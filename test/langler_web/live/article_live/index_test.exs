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
end
