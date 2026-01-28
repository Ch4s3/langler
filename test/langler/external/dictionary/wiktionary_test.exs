defmodule Langler.External.Dictionary.WiktionaryTest do
  use ExUnit.Case, async: false

  import Req.Test, only: [set_req_test_from_context: 1]

  alias Langler.External.Dictionary.Wiktionary

  @wiktionary_req Langler.External.Dictionary.WiktionaryReq

  setup :set_req_test_from_context
  setup {Req.Test, :verify_on_exit!}

  setup do
    Application.put_env(:langler, Langler.External.Dictionary.Wiktionary,
      base_url: "https://wiktionary.test",
      req_options: [plug: {Req.Test, @wiktionary_req}]
    )

    on_exit(fn -> Application.delete_env(:langler, Langler.External.Dictionary.Wiktionary) end)

    %{wiktionary: @wiktionary_req}
  end

  test "parses lemma and definitions", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/hola"

      Req.Test.html(conn, """
      <html>
        <body>
          <h1 id="firstHeading">hola</h1>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <h2><span class="mw-headline">Noun</span></h2>
              <ol>
                <li>hello</li>
                <li>hi</li>
              </ol>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:ok, entry} = Wiktionary.lookup("hola", "spanish")
    assert entry.lemma == "hola"
    assert entry.part_of_speech == "Noun"
    assert entry.definitions == ["hello", "hi"]
    assert entry.source_url =~ "/hola"
  end

  test "returns error when word not found (404)", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.text("Not found")
    end)

    assert {:error, :not_found} = Wiktionary.lookup("nonexistentword", "spanish")
  end

  test "handles HTTP errors", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      conn
      |> Plug.Conn.put_status(500)
      |> Req.Test.text("Server error")
    end)

    assert {:error, {:http_error, 500}} = Wiktionary.lookup("test", "spanish")
  end

  test "handles Req exceptions", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn _conn ->
      raise "Connection failed"
    end)

    assert_raise RuntimeError, "Connection failed", fn ->
      Wiktionary.lookup("test", "spanish")
    end
  end

  test "returns error when no definitions found", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      Req.Test.html(conn, """
      <html>
        <body>
          <h1 id="firstHeading">test</h1>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <p>No definitions available</p>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:error, :not_found} = Wiktionary.lookup("test", "spanish")
  end

  test "extracts definitions for specific language section (Spanish)", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      Req.Test.html(conn, """
      <html>
        <body>
          <h1 id="firstHeading">casa</h1>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <h2><span id="English" class="mw-headline">English</span></h2>
              <h3><span class="mw-headline">Noun</span></h3>
              <ol><li>English definition</li></ol>
              
              <h2><span id="Spanish" class="mw-headline">Spanish</span></h2>
              <h3><span class="mw-headline">Noun</span></h3>
              <ol>
                <li>house</li>
                <li>home</li>
              </ol>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:ok, entry} = Wiktionary.lookup("casa", "spanish")
    assert entry.definitions == ["house", "home"]
    assert entry.language == "spanish"
  end

  test "tries lowercase variant when first attempt fails", %{wiktionary: wiktionary} do
    Req.Test.stub(wiktionary, fn conn ->
      case conn.request_path do
        "/Hola" ->
          conn
          |> Plug.Conn.put_status(404)
          |> Req.Test.text("Not found")

        "/hola" ->
          Req.Test.html(conn, """
          <html>
            <body>
              <h1 id="firstHeading">hola</h1>
              <div id="mw-content-text">
                <div class="mw-parser-output">
                  <ol><li>hello</li></ol>
                </div>
              </div>
            </body>
          </html>
          """)
      end
    end)

    assert {:ok, entry} = Wiktionary.lookup("Hola", "spanish")
    assert entry.definitions == ["hello"]
  end

  test "supports multiple parts of speech (Verb)", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      Req.Test.html(conn, """
      <html>
        <body>
          <h1 id="firstHeading">correr</h1>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <h2><span class="mw-headline">Verb</span></h2>
              <ol><li>to run</li></ol>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:ok, entry} = Wiktionary.lookup("correr", "spanish")
    assert entry.part_of_speech == "Verb"
  end

  test "supports Adjective part of speech", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      Req.Test.html(conn, """
      <html>
        <body>
          <h1 id="firstHeading">rojo</h1>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <h2><span class="mw-headline">Adjective</span></h2>
              <ol><li>red</li></ol>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:ok, entry} = Wiktionary.lookup("rojo", "spanish")
    assert entry.part_of_speech == "Adjective"
  end

  test "supports Adverb part of speech", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      Req.Test.html(conn, """
      <html>
        <body>
          <h1 id="firstHeading">rápidamente</h1>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <h2><span class="mw-headline">Adverb</span></h2>
              <ol><li>quickly</li></ol>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:ok, entry} = Wiktionary.lookup("rápidamente", "spanish")
    assert entry.part_of_speech == "Adverb"
  end

  test "limits definitions to 3", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      Req.Test.html(conn, """
      <html>
        <body>
          <h1 id="firstHeading">test</h1>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <ol>
                <li>def 1</li>
                <li>def 2</li>
                <li>def 3</li>
                <li>def 4</li>
                <li>def 5</li>
              </ol>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:ok, entry} = Wiktionary.lookup("test", "spanish")
    assert length(entry.definitions) == 3
    assert entry.definitions == ["def 1", "def 2", "def 3"]
  end

  test "strips reference numbers from definitions", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      Req.Test.html(conn, """
      <html>
        <body>
          <h1 id="firstHeading">test</h1>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <ol>
                <li>definition with reference[1]</li>
                <li>another one[42]</li>
              </ol>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:ok, entry} = Wiktionary.lookup("test", "spanish")
    assert entry.definitions == ["definition with reference", "another one"]
  end

  test "uses term as lemma fallback when header is missing", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      Req.Test.html(conn, """
      <html>
        <body>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <ol><li>definition</li></ol>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:ok, entry} = Wiktionary.lookup("test", "spanish")
    assert entry.lemma == "test"
  end

  test "supports French language", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      Req.Test.html(conn, """
      <html>
        <body>
          <h1 id="firstHeading">bonjour</h1>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <h2><span id="French" class="mw-headline">French</span></h2>
              <ol><li>hello</li></ol>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:ok, entry} = Wiktionary.lookup("bonjour", "french")
    assert entry.language == "french"
  end

  test "supports German language", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      Req.Test.html(conn, """
      <html>
        <body>
          <h1 id="firstHeading">Haus</h1>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <h2><span id="German" class="mw-headline">German</span></h2>
              <ol><li>house</li></ol>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:ok, entry} = Wiktionary.lookup("Haus", "german")
    assert entry.language == "german"
  end

  test "supports Italian language", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      Req.Test.html(conn, """
      <html>
        <body>
          <h1 id="firstHeading">ciao</h1>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <h2><span id="Italian" class="mw-headline">Italian</span></h2>
              <ol><li>hello</li></ol>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:ok, entry} = Wiktionary.lookup("ciao", "italian")
    assert entry.language == "italian"
  end

  test "supports Portuguese language", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      Req.Test.html(conn, """
      <html>
        <body>
          <h1 id="firstHeading">olá</h1>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <h2><span id="Portuguese" class="mw-headline">Portuguese</span></h2>
              <ol><li>hello</li></ol>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:ok, entry} = Wiktionary.lookup("olá", "portuguese")
    assert entry.language == "portuguese"
  end

  test "handles unsupported language (no anchor)", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      refute conn.request_path =~ "#"

      Req.Test.html(conn, """
      <html>
        <body>
          <h1 id="firstHeading">test</h1>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <ol><li>definition</li></ol>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:ok, entry} = Wiktionary.lookup("test", "unsupported")
    assert entry.language == "unsupported"
  end

  test "handles nil language", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      Req.Test.html(conn, """
      <html>
        <body>
          <h1 id="firstHeading">test</h1>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <ol><li>definition</li></ol>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:ok, entry} = Wiktionary.lookup("test", nil)
    assert entry.language == ""
  end

  test "handles empty string term", %{wiktionary: wiktionary} do
    Req.Test.stub(wiktionary, fn conn ->
      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.text("Not found")
    end)

    assert {:error, :not_found} = Wiktionary.lookup("", "spanish")
  end

  test "URI encodes term with special characters", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      assert conn.request_path == "/qu%C3%A9"

      Req.Test.html(conn, """
      <html>
        <body>
          <h1 id="firstHeading">qué</h1>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <ol><li>what</li></ol>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:ok, entry} = Wiktionary.lookup("qué", "spanish")
    assert entry.lemma == "qué"
  end

  test "includes source URL in entry", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      Req.Test.html(conn, """
      <html>
        <body>
          <h1 id="firstHeading">test</h1>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <ol><li>definition</li></ol>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:ok, entry} = Wiktionary.lookup("test", "spanish")
    assert entry.source_url =~ "wiktionary.test/test#Spanish"
  end

  test "sets pronunciation and translation to nil", %{wiktionary: wiktionary} do
    Req.Test.expect(wiktionary, fn conn ->
      Req.Test.html(conn, """
      <html>
        <body>
          <h1 id="firstHeading">test</h1>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <ol><li>definition</li></ol>
            </div>
          </div>
        </body>
      </html>
      """)
    end)

    assert {:ok, entry} = Wiktionary.lookup("test", "spanish")
    assert entry.pronunciation == nil
    assert entry.translation == nil
  end
end
