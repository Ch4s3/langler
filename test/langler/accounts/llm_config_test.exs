defmodule Langler.Accounts.LlmConfigTest do
  use Langler.DataCase, async: true

  import Langler.AccountsFixtures

  alias Langler.Accounts.{LlmConfig, LlmProvider, UserLlmConfig}
  alias Langler.Repo

  defp create_config(user, attrs \\ %{}) do
    base_attrs = %{
      provider_name: "openai",
      api_key: "supersecretkey12345",
      model: "gpt-4o-mini"
    }

    LlmConfig.create_config(user, Map.merge(base_attrs, attrs))
  end

  test "create_config/2 encrypts the api key and sets the first config as default" do
    user = user_fixture()

    assert {:ok, config} = create_config(user)
    assert config.is_default
    assert is_binary(config.encrypted_api_key)

    assert LlmConfig.get_default_config(user.id).id == config.id
    assert length(LlmConfig.get_user_configs(user.id)) == 1
  end

  test "create_config/2 rejects missing api keys" do
    user = user_fixture()

    assert {:error, :invalid_api_key} =
             create_config(user, %{api_key: ""})
  end

  test "update_config/2 can promote a config to default and unset others" do
    user = user_fixture()

    assert {:ok, first} = create_config(user)
    assert {:ok, second} = create_config(user, %{provider_name: "anthropic", model: "claude"})

    assert {:ok, updated} = LlmConfig.update_config(second, %{is_default: true})
    assert updated.is_default

    refute Repo.get!(UserLlmConfig, first.id).is_default
  end

  test "decrypt_api_key_masked/2 masks the decrypted key" do
    user = user_fixture()
    assert {:ok, config} = create_config(user)

    assert LlmConfig.decrypt_api_key_masked(user.id, config.encrypted_api_key) ==
             "supersec...2345"
  end

  test "list_providers/0 returns only enabled providers" do
    {:ok, _} =
      %LlmProvider{}
      |> LlmProvider.changeset(%{
        name: "openai",
        display_name: "OpenAI",
        adapter_module: "Langler.LLM.Adapters.ChatGPT",
        enabled: true
      })
      |> Repo.insert()

    {:ok, _} =
      %LlmProvider{}
      |> LlmProvider.changeset(%{
        name: "disabled",
        display_name: "Disabled",
        adapter_module: "Langler.LLM.Adapters.ChatGPT",
        enabled: false
      })
      |> Repo.insert()

    providers = LlmConfig.list_providers()

    assert Enum.any?(providers, &(&1.name == "openai"))
    refute Enum.any?(providers, &(&1.name == "disabled"))
  end

  test "delete_config/1 removes the record" do
    user = user_fixture()
    assert {:ok, config} = create_config(user)

    assert {:ok, _} = LlmConfig.delete_config(config)
    assert LlmConfig.get_config(config.id) == nil
  end

  test "update_config/2 can update model and temperature" do
    user = user_fixture()
    assert {:ok, config} = create_config(user)

    assert {:ok, updated} =
             LlmConfig.update_config(config, %{model: "gpt-4", temperature: 0.8})

    assert updated.model == "gpt-4"
    assert updated.temperature == 0.8
  end

  test "update_config/2 can update api_key" do
    user = user_fixture()
    assert {:ok, config} = create_config(user)

    assert {:ok, updated} = LlmConfig.update_config(config, %{api_key: "newsecretkey123"})

    # API key should be re-encrypted
    assert updated.encrypted_api_key != config.encrypted_api_key
  end

  test "update_config/2 handles empty api_key gracefully" do
    user = user_fixture()
    assert {:ok, config} = create_config(user)

    assert {:ok, updated} = LlmConfig.update_config(config, %{api_key: "", model: "gpt-4"})

    # API key should not change when empty string is passed
    assert updated.encrypted_api_key == config.encrypted_api_key
    assert updated.model == "gpt-4"
  end

  test "decrypt_api_key_masked/2 handles short keys" do
    user = user_fixture()
    assert {:ok, config} = create_config(user, %{api_key: "short"})

    masked = LlmConfig.decrypt_api_key_masked(user.id, config.encrypted_api_key)
    assert masked == "*****"
  end

  test "decrypt_api_key_masked/2 handles decryption errors" do
    user = user_fixture()

    # Pass invalid encrypted data
    masked = LlmConfig.decrypt_api_key_masked(user.id, "invalid_encrypted_data")
    assert masked == "****"
  end

  test "get_config/1 returns nil for non-existent config" do
    assert LlmConfig.get_config(999_999) == nil
  end

  test "get_default_config/1 returns nil when no default exists" do
    user = user_fixture()
    assert LlmConfig.get_default_config(user.id) == nil
  end

  test "create_config/2 handles default_selected? with different truthy values" do
    user = user_fixture()

    # Create first config (auto-default)
    assert {:ok, first} = create_config(user)
    assert first.is_default

    # Create second with is_default: "true" (string)
    assert {:ok, second} =
             create_config(user, %{provider_name: "anthropic", is_default: "true"})

    assert second.is_default
    refute Repo.get!(UserLlmConfig, first.id).is_default
  end

  test "create_config/2 handles default_selected? with numeric 1 value" do
    user = user_fixture()

    assert {:ok, first} = create_config(user)
    assert {:ok, second} = create_config(user, %{provider_name: "anthropic", is_default: true})

    assert second.is_default
    refute Repo.get!(UserLlmConfig, first.id).is_default
  end

  test "create_config/2 trims whitespace from api_key" do
    user = user_fixture()

    assert {:ok, config} = create_config(user, %{api_key: "  sec12345678901  "})

    # Decrypt and verify it was trimmed (showing first 8 and last 4 chars)
    decrypted = LlmConfig.decrypt_api_key_masked(user.id, config.encrypted_api_key)
    # Should show sec12345...8901, not have spaces
    refute String.contains?(decrypted, " ")
  end

  test "stringify_keys/1 converts atom keys to strings" do
    user = user_fixture()

    # Pass attrs with atom keys
    assert {:ok, config} =
             LlmConfig.create_config(user, %{
               provider_name: "openai",
               api_key: "testkey",
               model: "gpt-4o-mini"
             })

    assert config.provider_name == "openai"
    assert config.model == "gpt-4o-mini"
  end
end
