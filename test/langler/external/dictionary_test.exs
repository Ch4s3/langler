defmodule Langler.External.DictionaryTest do
  use Langler.DataCase, async: false

  import Req.Test, only: [set_req_test_from_context: 1]

  alias Langler.External.Dictionary
  alias Langler.External.Dictionary.CacheEntry

  @google_req Langler.External.Dictionary.GoogleReq
  @wiktionary_req Langler.External.Dictionary.WiktionaryReq
  @languagetool_req Langler.External.Dictionary.LanguageToolReq

  setup :set_req_test_from_context
  setup {Req.Test, :verify_on_exit!}

  setup do
    Application.put_env(:langler, Langler.External.Dictionary.Google,
      dictionary_endpoint: "https://google.test/dictionary",
      cache_table: :google_dictionary_test_cache,
      req_options: [plug: {Req.Test, @google_req}]
    )

    Application.put_env(:langler, Langler.External.Dictionary.Wiktionary,
      base_url: "https://wiktionary.test/wiki",
      cache_table: :wiktionary_dictionary_test_cache,
      req_options: [plug: {Req.Test, @wiktionary_req}]
    )

    Application.put_env(:langler, Langler.External.Dictionary.LanguageTool,
      endpoint: "https://languagetool.test/check",
      cache_table: :languagetool_dictionary_test_cache,
      req_options: [plug: {Req.Test, @languagetool_req}]
    )

    cleanup_tables([
      :dictionary_entry_cache,
      :google_dictionary_test_cache,
      :wiktionary_dictionary_test_cache,
      :languagetool_dictionary_test_cache
    ])

    on_exit(fn ->
      cleanup_tables([
        :dictionary_entry_cache,
        :google_dictionary_test_cache,
        :wiktionary_dictionary_test_cache,
        :languagetool_dictionary_test_cache
      ])

      Application.delete_env(:langler, Langler.External.Dictionary.Google)
      Application.delete_env(:langler, Langler.External.Dictionary.Wiktionary)
      Application.delete_env(:langler, Langler.External.Dictionary.LanguageTool)
    end)

    {:ok, google: @google_req, wiktionary: @wiktionary_req, languagetool: @languagetool_req}
  end

  test "prefers Google dictionary definitions and translation", %{
    google: google,
    wiktionary: wiktionary,
    languagetool: languagetool
  } do
    Req.Test.expect(google, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/dictionary"

      response = %{
        "sentences" => [
          %{"trans" => "hello", "orig" => "hola"}
        ],
        "dict" => [
          %{
            "pos" => "noun",
            "entry" => [
              %{
                "word" => "hello",
                "reverse_translation" => ["hola", "qué tal"]
              }
            ]
          }
        ]
      }

      Req.Test.json(conn, response)
    end)

    # Wiktionary isn't needed when Google dictionary succeeds
    Req.Test.expect(wiktionary, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/wiki/hola"

      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.text("not found")
    end)

    Req.Test.expect(languagetool, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/check"

      response = %{"matches" => []}

      Req.Test.json(conn, response)
    end)

    {:ok, entry} = Dictionary.lookup("hola", language: "spanish", target: "en")

    assert entry.word == "hola"
    assert entry.language == "spanish"
    assert entry.translation == "hello"
    assert entry.definitions == ["Hello (noun) — hola, qué tal"]
    assert entry.lemma == "Hola"
  end

  test "falls back to translation when Wiktionary and Google both fail", %{
    google: google,
    wiktionary: wiktionary,
    languagetool: languagetool
  } do
    Req.Test.expect(google, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/dictionary"

      conn
      |> Plug.Conn.put_status(500)
      |> Req.Test.text("error")
    end)

    Req.Test.expect(wiktionary, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/wiki/hola"

      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.text("not found")
    end)

    Req.Test.expect(languagetool, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/check"

      response = %{"matches" => []}

      Req.Test.json(conn, response)
    end)

    {:ok, entry} = Dictionary.lookup("hola", language: "spanish", target: "en")

    assert entry.word == "hola"
    assert entry.language == "spanish"
    assert entry.translation == nil
    assert entry.definitions == []
    assert entry.lemma == "Hola"
  end

  test "retries Google lookup using lemma when inflected form lacks definitions", %{
    google: google,
    wiktionary: wiktionary,
    languagetool: languagetool
  } do
    Req.Test.expect(google, 2, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/dictionary"

      conn = Plug.Conn.fetch_query_params(conn)

      response =
        case conn.query_params["q"] do
          "hablando" ->
            %{"sentences" => [%{"orig" => "hablando", "trans" => ""}]}

          "hablar" ->
            %{
              "sentences" => [%{"orig" => "hablar", "trans" => "to speak"}],
              "dict" => [
                %{
                  "pos" => "verb",
                  "entry" => [
                    %{
                      "word" => "speak",
                      "reverse_translation" => ["hablar", "decir", "charlar"]
                    }
                  ]
                }
              ]
            }
        end

      Req.Test.json(conn, response)
    end)

    Req.Test.expect(wiktionary, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/wiki/hablando"

      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.text("not found")
    end)

    Req.Test.expect(languagetool, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/check"

      response = %{
        "matches" => [
          %{
            "replacements" => [%{"value" => "hablar"}],
            "rule" => %{"category" => %{"id" => "verb"}}
          }
        ]
      }

      Req.Test.json(conn, response)
    end)

    {:ok, entry} = Dictionary.lookup("hablando", language: "spanish", target: "en")
    assert entry.translation == "to speak"
    assert entry.definitions == ["Speak (verb) — hablar, decir, charlar"]
  end

  test "restores cached entries from the database without hitting providers", %{
    google: google,
    wiktionary: wiktionary,
    languagetool: languagetool
  } do
    Req.Test.expect(google, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/dictionary"

      response = %{
        "sentences" => [%{"trans" => "hello", "orig" => "hola"}],
        "dict" => [
          %{
            "pos" => "noun",
            "entry" => [%{"word" => "hello", "reverse_translation" => ["hola"]}]
          }
        ]
      }

      Req.Test.json(conn, response)
    end)

    # ensure Wiktionary isn't used during first fetch
    Req.Test.expect(wiktionary, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/wiki/hola"

      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.text("not found")
    end)

    Req.Test.expect(languagetool, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/check"

      response = %{"matches" => []}

      Req.Test.json(conn, response)
    end)

    {:ok, entry} = Dictionary.lookup("hola", language: "spanish", target: "en")
    assert entry.translation == "hello"

    :ets.delete(:dictionary_entry_cache)

    Req.Test.stub(google, fn _conn ->
      flunk("dictionary API should not be hit when loading from persistent cache")
    end)

    {:ok, cached_entry} = Dictionary.lookup("hola", language: "spanish", target: "en")
    assert cached_entry.translation == "hello"
  end

  defp cleanup_tables(tables) do
    Enum.each(tables, fn table ->
      case :ets.whereis(table) do
        :undefined ->
          :ok

        _ ->
          try do
            :ets.delete(table)
          rescue
            ArgumentError -> :ok
          end
      end
    end)

    Repo.delete_all(CacheEntry)
  end
end
