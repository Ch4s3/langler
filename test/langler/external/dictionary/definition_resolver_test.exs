defmodule Langler.External.Dictionary.DefinitionResolverTest do
  @moduledoc """
  Tests for the DefinitionResolver module.
  """
  use Langler.DataCase, async: false

  alias Langler.Accounts
  alias Langler.External.Dictionary.DefinitionResolver

  describe "resolve_provider/2" do
    test "returns google with explicit api_key when no user_id" do
      opts = [api_key: "test_key", language: "spanish", target: "en"]

      assert {:ok, :google, resolved_opts} = DefinitionResolver.resolve_provider(nil, opts)
      assert Keyword.get(resolved_opts, :api_key) == "test_key"
    end

    test "returns error when no user_id and no api_key" do
      opts = [language: "spanish", target: "en"]

      assert {:error, :no_provider_available} = DefinitionResolver.resolve_provider(nil, opts)
    end

    test "returns llm when user prefers LLM and has LLM config" do
      user = insert_user()
      insert_llm_config(user)
      set_preference(user, %{use_llm_for_definitions: true})

      opts = [language: "spanish", target: "en"]

      assert {:ok, :llm, resolved_opts} = DefinitionResolver.resolve_provider(user.id, opts)
      assert Keyword.get(resolved_opts, :user_id) == user.id
    end

    test "returns error when user prefers LLM but has no LLM config" do
      user = insert_user()
      set_preference(user, %{use_llm_for_definitions: true})

      opts = [language: "spanish", target: "en"]

      assert {:error, :no_provider_available} = DefinitionResolver.resolve_provider(user.id, opts)
    end

    test "returns google when user has google translate configured" do
      user = insert_user()
      insert_google_translate_config(user)

      opts = [language: "spanish", target: "en"]

      assert {:ok, :google, resolved_opts} = DefinitionResolver.resolve_provider(user.id, opts)
      assert is_binary(Keyword.get(resolved_opts, :api_key))
    end

    test "falls back to LLM when Google not configured but LLM is" do
      user = insert_user()
      insert_llm_config(user)

      opts = [language: "spanish", target: "en"]

      assert {:ok, :llm, resolved_opts} = DefinitionResolver.resolve_provider(user.id, opts)
      assert Keyword.get(resolved_opts, :user_id) == user.id
    end

    test "returns error when neither Google nor LLM is configured" do
      user = insert_user()

      opts = [language: "spanish", target: "en"]

      assert {:error, :no_provider_available} = DefinitionResolver.resolve_provider(user.id, opts)
    end

    test "prefers google when both are configured and use_llm_for_definitions is false" do
      user = insert_user()
      insert_google_translate_config(user)
      insert_llm_config(user)
      set_preference(user, %{use_llm_for_definitions: false})

      opts = [language: "spanish", target: "en"]

      assert {:ok, :google, _} = DefinitionResolver.resolve_provider(user.id, opts)
    end

    test "uses LLM when both are configured and use_llm_for_definitions is true" do
      user = insert_user()
      insert_google_translate_config(user)
      insert_llm_config(user)
      set_preference(user, %{use_llm_for_definitions: true})

      opts = [language: "spanish", target: "en"]

      assert {:ok, :llm, _} = DefinitionResolver.resolve_provider(user.id, opts)
    end
  end

  defp insert_user do
    {:ok, user} =
      Accounts.register_user(%{
        email: "test-#{System.unique_integer()}@example.com",
        password: "Password123456!"
      })

    user
  end

  defp insert_llm_config(user) do
    {:ok, config} =
      Langler.Accounts.LlmConfig.create_config(user, %{
        "provider_name" => "openai",
        "api_key" => "test-llm-api-key-12345",
        "model" => "gpt-4o-mini",
        "is_default" => true
      })

    config
  end

  defp insert_google_translate_config(user) do
    {:ok, config} =
      Langler.Accounts.GoogleTranslateConfig.create_config(user, %{
        "api_key" => "test-google-api-key-12345",
        "enabled" => true,
        "is_default" => true
      })

    config
  end

  defp set_preference(user, attrs) do
    Accounts.upsert_user_preference(user, attrs)
  end
end
