defmodule Langler.External.DictionaryTest do
  use Langler.DataCase, async: false

  alias Langler.External.Dictionary
  alias Langler.External.Dictionary.CacheEntry

  setup do
    google = Bypass.open()
    wiktionary = Bypass.open()
    languagetool = Bypass.open()

    Application.put_env(:langler, Langler.External.Dictionary.Google,
      dictionary_endpoint: "http://localhost:#{google.port}/dictionary",
      cache_table: :google_dictionary_test_cache
    )

    Application.put_env(:langler, Langler.External.Dictionary.Wiktionary,
      base_url: "http://localhost:#{wiktionary.port}/wiki",
      cache_table: :wiktionary_dictionary_test_cache
    )

    Application.put_env(:langler, Langler.External.Dictionary.LanguageTool,
      endpoint: "http://localhost:#{languagetool.port}/check",
      cache_table: :languagetool_dictionary_test_cache
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

    {:ok, google: google, wiktionary: wiktionary, languagetool: languagetool}
  end

  test "prefers Google dictionary definitions and translation", %{
    google: google,
    wiktionary: wiktionary,
    languagetool: languagetool
  } do
    Bypass.expect(google, "GET", "/dictionary", fn conn ->
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

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response))
    end)

    # Wiktionary isn't needed when Google dictionary succeeds
    Bypass.expect_once(wiktionary, "GET", "/wiki/hola", fn conn ->
      Plug.Conn.resp(conn, 404, "not found")
    end)

    Bypass.expect(languagetool, "POST", "/check", fn conn ->
      response = %{"matches" => []}

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response))
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
    Bypass.expect(google, "GET", "/dictionary", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(500, "error")
    end)

    Bypass.expect(wiktionary, "GET", "/wiki/hola", fn conn ->
      Plug.Conn.resp(conn, 404, "not found")
    end)

    Bypass.expect(languagetool, "POST", "/check", fn conn ->
      response = %{"matches" => []}

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response))
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
    Bypass.expect(google, "GET", "/dictionary", fn conn ->
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

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response))
    end)

    Bypass.expect_once(wiktionary, "GET", "/wiki/hablando", fn conn ->
      Plug.Conn.resp(conn, 404, "not found")
    end)

    Bypass.expect(languagetool, "POST", "/check", fn conn ->
      response = %{
        "matches" => [
          %{
            "replacements" => [%{"value" => "hablar"}],
            "rule" => %{"category" => %{"id" => "verb"}}
          }
        ]
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response))
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
    Bypass.expect(google, "GET", "/dictionary", fn conn ->
      response = %{
        "sentences" => [%{"trans" => "hello", "orig" => "hola"}],
        "dict" => [
          %{
            "pos" => "noun",
            "entry" => [%{"word" => "hello", "reverse_translation" => ["hola"]}]
          }
        ]
      }

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response))
    end)

    # ensure Wiktionary isn't used during first fetch
    Bypass.expect_once(wiktionary, "GET", "/wiki/hola", fn conn ->
      Plug.Conn.resp(conn, 404, "not found")
    end)

    Bypass.expect(languagetool, "POST", "/check", fn conn ->
      response = %{"matches" => []}

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(response))
    end)

    {:ok, entry} = Dictionary.lookup("hola", language: "spanish", target: "en")
    assert entry.translation == "hello"

    :ets.delete(:dictionary_entry_cache)

    Bypass.stub(google, "GET", "/dictionary", fn _conn ->
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
