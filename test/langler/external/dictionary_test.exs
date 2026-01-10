defmodule Langler.External.DictionaryTest do
  use ExUnit.Case, async: false

  alias Langler.External.Dictionary

  test "returns fallback entry when providers fail" do
    bypass = Bypass.open()

    Application.put_env(:langler, Langler.External.Dictionary.Wiktionary,
      base_url: "http://localhost:#{bypass.port}"
    )

    Bypass.expect(bypass, "GET", "/hola", fn conn ->
      Plug.Conn.resp(conn, 500, "error")
    end)

    {:ok, entry} = Dictionary.lookup("hola", language: "spanish")

    assert entry.word == "hola"
    assert entry.language == "spanish"
    assert entry.definitions == []
  after
    Application.delete_env(:langler, Langler.External.Dictionary.Wiktionary)
  end
end
