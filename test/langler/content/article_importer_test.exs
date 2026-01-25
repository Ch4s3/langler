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

  describe "punctuation spacing normalization" do
    test "removes spaces before commas and periods", %{importer: importer, user: user} do
      Req.Test.expect(importer, fn conn ->
        body = """
        <html>
          <body>
            <p>El anfitrión , al ostentar la presidencia , subrayó que el diálogo es " el único camino " .</p>
          </body>
        </html>
        """

        Req.Test.html(conn, body)
      end)

      url = article_url("/punctuation-test")
      assert {:ok, article, :new} = ArticleImporter.import_from_url(user, url)

      sentences = Content.list_sentences(article)
      sentence_content = Enum.at(sentences, 0).content

      # Note: Space before opening quote is preserved when preceded by a letter
      assert sentence_content ==
               "El anfitrión, al ostentar la presidencia, subrayó que el diálogo es \"el único camino\"."
    end

    test "handles Spanish inverted marks correctly", %{importer: importer, user: user} do
      Req.Test.expect(importer, fn conn ->
        body = """
        <html>
          <body>
            <p>¿ pregunta ? ¡ exclamación !</p>
          </body>
        </html>
        """

        Req.Test.html(conn, body)
      end)

      url = article_url("/inverted-marks-test")
      assert {:ok, article, :new} = ArticleImporter.import_from_url(user, url)

      sentences = Content.list_sentences(article)

      # Note: Sentence splitting may separate "¿pregunta?" and "¡exclamación!" into different sentences
      # Check that punctuation spacing is correct in each sentence
      first_sentence = Enum.at(sentences, 0).content
      assert first_sentence == "¿pregunta?"

      # If there's a second sentence, check it too
      if length(sentences) > 1 do
        second_sentence = Enum.at(sentences, 1).content
        assert second_sentence == "¡exclamación!"
      end
    end

    test "removes spaces inside guillemets", %{importer: importer, user: user} do
      Req.Test.expect(importer, fn conn ->
        body = """
        <html>
          <body>
            <p>Dijo « texto » correctamente.</p>
          </body>
        </html>
        """

        Req.Test.html(conn, body)
      end)

      url = article_url("/guillemets-test")
      assert {:ok, article, :new} = ArticleImporter.import_from_url(user, url)

      sentences = Content.list_sentences(article)
      sentence_content = Enum.at(sentences, 0).content

      assert sentence_content == "Dijo «texto» correctamente."
    end

    test "normalizes ellipses", %{importer: importer, user: user} do
      Req.Test.expect(importer, fn conn ->
        body = """
        <html>
          <body>
            <p>Palabra ... siguiente.</p>
          </body>
        </html>
        """

        Req.Test.html(conn, body)
      end)

      url = article_url("/ellipsis-test")
      assert {:ok, article, :new} = ArticleImporter.import_from_url(user, url)

      sentences = Content.list_sentences(article)
      sentence_content = Enum.at(sentences, 0).content

      assert sentence_content == "Palabra… siguiente."
    end

    test "removes spaces after opening punctuation", %{importer: importer, user: user} do
      Req.Test.expect(importer, fn conn ->
        body = """
        <html>
          <body>
            <p>( texto ) [ otro ] { más }</p>
          </body>
        </html>
        """

        Req.Test.html(conn, body)
      end)

      url = article_url("/opening-punct-test")
      assert {:ok, article, :new} = ArticleImporter.import_from_url(user, url)

      sentences = Content.list_sentences(article)
      sentence_content = Enum.at(sentences, 0).content

      assert sentence_content == "(texto) [otro] {más}"
    end

    test "ensures space after punctuation when followed by letter", %{
      importer: importer,
      user: user
    } do
      Req.Test.expect(importer, fn conn ->
        body = """
        <html>
          <body>
            <p>Palabra,otra palabra;siguiente</p>
          </body>
        </html>
        """

        Req.Test.html(conn, body)
      end)

      url = article_url("/space-after-punct-test")
      assert {:ok, article, :new} = ArticleImporter.import_from_url(user, url)

      sentences = Content.list_sentences(article)
      sentence_content = Enum.at(sentences, 0).content

      assert sentence_content == "Palabra, otra palabra; siguiente"
    end

    test "handles complex sentence with multiple punctuation issues", %{
      importer: importer,
      user: user
    } do
      Req.Test.expect(importer, fn conn ->
        body = """
        <html>
          <body>
            <p>El anfitrión de la ceremonia , al ostentar la presidencia temporal de Mercosur , el paraguayo Santiago Peña , subrayó que el diálogo es " el único camino " .</p>
          </body>
        </html>
        """

        Req.Test.html(conn, body)
      end)

      url = article_url("/complex-punctuation-test")
      assert {:ok, article, :new} = ArticleImporter.import_from_url(user, url)

      sentences = Content.list_sentences(article)
      sentence_content = Enum.at(sentences, 0).content

      assert sentence_content ==
               "El anfitrión de la ceremonia, al ostentar la presidencia temporal de Mercosur, el paraguayo Santiago Peña, subrayó que el diálogo es \"el único camino\"."
    end
  end

  defp article_url(path) do
    "https://article-importer.test#{path}"
  end
end
