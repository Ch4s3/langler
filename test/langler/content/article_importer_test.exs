defmodule Langler.Content.ArticleImporterTest do
  use Langler.DataCase, async: true

  import Req.Test, only: [set_req_test_from_context: 1]

  alias Langler.AccountsFixtures
  alias Langler.Content
  alias Langler.Content.ArticleImporter

  @importer_req Langler.Content.ArticleImporterReq

  setup :set_req_test_from_context
  setup {Req.Test, :verify_on_exit!}

  setup do
    Application.put_env(:langler, Langler.Content.ArticleImporter,
      req_options: [plug: {Req.Test, @importer_req}, retry: false]
    )

    on_exit(fn -> Application.delete_env(:langler, Langler.Content.ArticleImporter) end)

    user = AccountsFixtures.user_fixture()

    %{user: user, importer: @importer_req}
  end

  describe "import_from_url/2" do
    test "imports a new article, sanitizes content, and creates sentences", %{
      importer: importer,
      user: user
    } do
      Req.Test.expect(importer, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/article"

        body = """
        <html>
          <head><title>Ignored Title</title></head>
          <body>
            <p>Hola mundo.</p>
            <p>Adiós Phoenix!</p>
          </body>
        </html>
        """

        Req.Test.html(conn, body)
      end)

      url = article_url("/article")

      assert {:ok, article, :new} = ArticleImporter.import_from_url(user, url)
      assert article.url == url
      assert article.content =~ "Hola mundo. Adiós Phoenix!"
      assert article.language == "spanish"

      sentences = Content.list_sentences(article)
      assert length(sentences) == 2

      assert Enum.map(sentences, & &1.content) == ["Hola mundo.", "Adiós Phoenix!"]
    end

    test "re-importing existing article refreshes content", %{importer: importer, user: user} do
      parent = self()

      Req.Test.expect(importer, 2, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/same"

        send(parent, :fetched)
        Req.Test.html(conn, "<p>Hola mundo.</p>")
      end)

      url = article_url("/same")
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

  defp article_url(path) do
    "https://article-importer.test#{path}"
  end
end
