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
end
