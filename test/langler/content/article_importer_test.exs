defmodule Langler.Content.ArticleImporterTest do
  use Langler.DataCase, async: true

  import Plug.Conn

  alias Langler.AccountsFixtures
  alias Langler.Content
  alias Langler.Content.ArticleImporter

  setup do
    bypass = Bypass.open()
    user = AccountsFixtures.user_fixture()

    %{bypass: bypass, user: user}
  end

  describe "import_from_url/2" do
    test "imports a new article, sanitizes content, and creates sentences", %{
      bypass: bypass,
      user: user
    } do
      Bypass.expect_once(bypass, "GET", "/article", fn conn ->
        body = """
        <html>
          <head><title>Ignored Title</title></head>
          <body>
            <p>Hola mundo.</p>
            <p>Adiós Phoenix!</p>
          </body>
        </html>
        """

        resp(conn, 200, body)
      end)

      url = article_url(bypass, "/article")

      assert {:ok, article, :new} = ArticleImporter.import_from_url(user, url)
      assert article.url == url
      assert article.content =~ "Hola mundo. Adiós Phoenix!"
      assert article.language == "spanish"

      sentences = Content.list_sentences(article)
      assert length(sentences) == 2

      assert Enum.map(sentences, & &1.content) == ["Hola mundo.", "Adiós Phoenix!"]
    end

    test "re-importing existing article refreshes content", %{bypass: bypass, user: user} do
      parent = self()

      Bypass.expect(bypass, fn conn ->
        send(parent, :fetched)
        resp(conn, 200, "<p>Hola mundo.</p>")
      end)

      url = article_url(bypass, "/same")
      assert {:ok, article, :new} = ArticleImporter.import_from_url(user, url)
      assert {:ok, same_article, :existing} = ArticleImporter.import_from_url(user, url)
      assert same_article.id == article.id
      assert_receive(:fetched)
      assert_receive(:fetched)
      assert DateTime.compare(same_article.updated_at, article.updated_at) != :lt
    end

    test "rejects invalid schemes", %{user: user} do
      assert {:error, :invalid_scheme} =
               ArticleImporter.import_from_url(user, "ftp://example.com")
    end
  end

  defp article_url(bypass, path) do
    "http://localhost:#{bypass.port}#{path}"
  end
end
