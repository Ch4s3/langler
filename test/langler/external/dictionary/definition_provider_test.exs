defmodule Langler.External.Dictionary.DefinitionProviderTest do
  @moduledoc """
  Tests for the DefinitionProvider behavior and its implementations.
  """
  use Langler.DataCase, async: false

  import Req.Test, only: [set_req_test_from_context: 1]

  alias Langler.Accounts
  alias Langler.External.Dictionary.{GoogleProvider, LLMProvider}

  @google_req Langler.External.Dictionary.GoogleProviderReq
  @chatgpt_req Langler.LLM.ChatGPTProviderReq

  setup :set_req_test_from_context
  setup {Req.Test, :verify_on_exit!}

  setup do
    Application.put_env(:langler, Langler.External.Dictionary.Google,
      dictionary_endpoint: "https://google.test/dictionary",
      cache_table: :google_provider_test_cache,
      req_options: [plug: {Req.Test, @google_req}]
    )

    cleanup_caches()

    on_exit(fn ->
      cleanup_caches()
      Application.delete_env(:langler, Langler.External.Dictionary.Google)
    end)

    {:ok, google: @google_req, chatgpt: @chatgpt_req}
  end

  describe "GoogleProvider" do
    test "returns translation and definitions on success", %{google: google} do
      Req.Test.expect(google, fn conn ->
        response = %{
          "sentences" => [%{"trans" => "hello", "orig" => "hola"}],
          "dict" => [
            %{
              "pos" => "interjection",
              "entry" => [
                %{"word" => "hello", "reverse_translation" => ["hola", "saludo"]}
              ]
            }
          ]
        }

        Req.Test.json(conn, response)
      end)

      {:ok, result} =
        GoogleProvider.get_definition("hola",
          language: "spanish",
          target: "en",
          api_key: "test_key"
        )

      assert result.translation == "hello"
      assert result.definitions == ["Hello (interjection) — hola, saludo"]
    end

    test "returns empty definitions when Google returns no dict", %{google: google} do
      Req.Test.expect(google, fn conn ->
        response = %{
          "sentences" => [%{"trans" => "testing", "orig" => "probando"}]
        }

        Req.Test.json(conn, response)
      end)

      {:ok, result} =
        GoogleProvider.get_definition("probando",
          language: "spanish",
          target: "en",
          api_key: "test_key"
        )

      assert result.translation == "testing"
      assert result.definitions == []
    end

    test "returns error on API failure", %{google: google} do
      Req.Test.expect(google, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.text("Internal Server Error")
      end)

      assert {:error, _} =
               GoogleProvider.get_definition("hola",
                 language: "spanish",
                 target: "en",
                 api_key: "test_key"
               )
    end
  end

  describe "LLMProvider" do
    test "returns error when user_id is not provided" do
      assert {:error, :user_id_required} =
               LLMProvider.get_definition("hola", language: "spanish", target: "en")
    end

    test "returns error when user has no LLM config" do
      user = insert_user()

      assert {:error, :no_llm_config} =
               LLMProvider.get_definition("hola",
                 language: "spanish",
                 target: "en",
                 user_id: user.id
               )
    end

    # Note: Testing LLM responses requires mocking at a lower level since ChatGPT adapter
    # doesn't have built-in pluggable req_options like the dictionary services.
    # These tests verify the JSON parsing logic directly.
  end

  describe "LLMProvider response parsing" do
    test "parses valid JSON response" do
      content = ~s|{"translation": "hello", "definitions": ["Hello (interjection) — a greeting"]}|
      result = parse_llm_response_public(content)

      assert {:ok, parsed} = result
      assert parsed.translation == "hello"
      assert parsed.definitions == ["Hello (interjection) — a greeting"]
    end

    test "handles JSON wrapped in markdown code block" do
      content =
        ~s|```json\n{"translation": "to eat", "definitions": ["To eat (verb) — to consume food"]}\n```|

      result = parse_llm_response_public(content)

      assert {:ok, parsed} = result
      assert parsed.translation == "to eat"
      assert parsed.definitions == ["To eat (verb) — to consume food"]
    end

    test "handles JSON wrapped in plain code block" do
      content =
        ~s|```\n{"translation": "water", "definitions": ["Water (noun) — clear liquid"]}\n```|

      result = parse_llm_response_public(content)

      assert {:ok, parsed} = result
      assert parsed.translation == "water"
      assert parsed.definitions == ["Water (noun) — clear liquid"]
    end

    test "returns error for invalid JSON" do
      content = "I don't understand the word."
      assert {:error, {:json_parse_error, _}} = parse_llm_response_public(content)
    end

    test "returns error for unexpected JSON format" do
      content = ~s|{"some_other_field": "value"}|
      assert {:error, :invalid_response_format} = parse_llm_response_public(content)
    end

    test "normalizes nil translation" do
      content = ~s|{"translation": null, "definitions": []}|
      result = parse_llm_response_public(content)

      assert {:ok, parsed} = result
      assert parsed.translation == nil
      assert parsed.definitions == []
    end

    test "filters non-string definitions" do
      content =
        ~s|{"translation": "hello", "definitions": ["Valid def", 123, null, "Another def"]}|

      result = parse_llm_response_public(content)

      assert {:ok, parsed} = result
      assert parsed.definitions == ["Valid def", "Another def"]
    end

    test "trims whitespace from translation and definitions" do
      content = ~s|{"translation": "  hello  ", "definitions": ["  Def one  ", "  Def two  "]}|
      result = parse_llm_response_public(content)

      assert {:ok, parsed} = result
      assert parsed.translation == "hello"
      assert parsed.definitions == ["Def one", "Def two"]
    end

    test "limits definitions to 5 entries" do
      defs = Enum.map(1..10, &"Definition #{&1}")
      content = Jason.encode!(%{translation: "test", definitions: defs})
      result = parse_llm_response_public(content)

      assert {:ok, parsed} = result
      assert length(parsed.definitions) == 5
    end
  end

  # Helper to test the private parse function via module attribute trick
  defp parse_llm_response_public(content) do
    # Since parse_llm_response is private, we test via the module
    # by calling a wrapper that we'll add for testing
    Langler.External.Dictionary.LLMProvider.parse_response_for_test(content)
  end

  defp insert_user do
    {:ok, user} =
      Accounts.register_user(%{
        email: "test-#{System.unique_integer()}@example.com",
        password: "Password123456!"
      })

    user
  end

  defp cleanup_caches do
    tables = [:google_provider_test_cache]

    Enum.each(tables, fn table ->
      case :ets.whereis(table) do
        :undefined ->
          :ok

        _ ->
          try do
            :ets.delete(table)
          rescue
            _ -> :ok
          end
      end
    end)
  end
end
