defmodule LanglerWeb.ArticleLive.ShowTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Langler.ContentFixtures

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
end
