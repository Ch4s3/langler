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
end
