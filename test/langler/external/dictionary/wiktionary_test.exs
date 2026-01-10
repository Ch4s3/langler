defmodule Langler.External.Dictionary.WiktionaryTest do
  use ExUnit.Case, async: false

  alias Langler.External.Dictionary.Wiktionary

  setup do
    bypass = Bypass.open()

    Application.put_env(:langler, Langler.External.Dictionary.Wiktionary,
      base_url: "http://localhost:#{bypass.port}"
    )

    on_exit(fn -> Application.delete_env(:langler, Langler.External.Dictionary.Wiktionary) end)

    %{bypass: bypass}
  end

  test "parses lemma and definitions", %{bypass: bypass} do
    Bypass.expect(bypass, "GET", "/hola", fn conn ->
      Plug.Conn.resp(conn, 200, """
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
end
