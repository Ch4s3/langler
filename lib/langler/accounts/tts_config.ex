defmodule Langler.Accounts.TtsConfig do
  @moduledoc """
  Context for managing user TTS configurations.
  """

  import Ecto.Query
  alias Langler.Accounts.{User, UserTtsConfig}
  alias Langler.Chat.Encryption
  alias Langler.Repo
  alias Langler.TTS.Adapters.VertexAI

  @doc """
  Gets all TTS configs for a user.
  """
  @spec get_user_configs(integer()) :: list(UserTtsConfig.t())
  def get_user_configs(user_id) when is_integer(user_id) do
    UserTtsConfig
    |> where(user_id: ^user_id)
    |> Repo.all()
  end

  @doc """
  Gets the default TTS config for a user.
  """
  @spec get_default_config(integer()) :: UserTtsConfig.t() | nil
  def get_default_config(user_id) when is_integer(user_id) do
    UserTtsConfig
    |> where(user_id: ^user_id, is_default: true)
    |> Repo.one()
  end

  @doc """
  Gets a specific TTS config by ID.
  """
  @spec get_config(integer()) :: UserTtsConfig.t() | nil
  def get_config(config_id) when is_integer(config_id) do
    Repo.get(UserTtsConfig, config_id)
  end

  @doc """
  Checks if TTS is enabled for a user.
  Returns true only if user has a default config AND enabled == true.
  """
  @spec tts_enabled?(integer()) :: boolean()
  def tts_enabled?(user_id) when is_integer(user_id) do
    case get_default_config(user_id) do
      %UserTtsConfig{enabled: true} -> true
      _ -> false
    end
  end

  @doc """
  Creates a new TTS config with encrypted API key.
  """
  @spec create_config(User.t(), map()) :: {:ok, UserTtsConfig.t()} | {:error, Ecto.Changeset.t()}
  def create_config(%User{} = user, attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    with {:ok, encrypted_key} <- encrypt_api_key(user.id, Map.get(attrs, "api_key")) do
      attrs =
        attrs
        |> Map.put("encrypted_api_key", encrypted_key)
        |> Map.put("user_id", user.id)
        |> Map.delete("api_key")
        |> Map.put_new("provider_name", "vertex_ai")
        |> Map.put_new("location", "us-central1")
        # project_id is optional for Generative AI API (not needed for API key auth)
        |> Map.delete("project_id")

      # If this is the first config, make it default
      is_first = get_user_configs(user.id) == []

      attrs =
        if is_first do
          Map.put(attrs, "is_default", true)
        else
          attrs
        end

      %UserTtsConfig{}
      |> UserTtsConfig.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, config} = result ->
          # If setting as default, unset other defaults
          if default_selected?(attrs) do
            unset_other_defaults(user.id, config.id)
          end

          result

        error ->
          error
      end
    end
  end

  @doc """
  Updates an existing TTS config.
  """
  @spec update_config(UserTtsConfig.t(), map()) ::
          {:ok, UserTtsConfig.t()} | {:error, Ecto.Changeset.t()}
  def update_config(%UserTtsConfig{} = config, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> maybe_encrypt_api_key(config.user_id)
      # project_id is optional for Generative AI API (not needed for API key auth)
      |> Map.delete("project_id")

    config
    |> UserTtsConfig.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, _updated_config} = result ->
        # If setting as default, unset other defaults
        if default_selected?(attrs) do
          unset_other_defaults(config.user_id, config.id)
        end

        result

      error ->
        error
    end
  end

  @doc """
  Deletes a TTS config.
  """
  @spec delete_config(UserTtsConfig.t()) ::
          {:ok, UserTtsConfig.t()} | {:error, Ecto.Changeset.t()}
  def delete_config(%UserTtsConfig{} = config) do
    Repo.delete(config)
  end

  @doc """
  Tests if TTS credentials are valid by making a test request.
  """
  @spec test_config(map()) :: {:ok, String.t()} | {:error, term()}
  def test_config(config) when is_map(config) do
    # Use a longer, more explicit test text that clearly indicates it's a transcript
    # Short texts like "Test" might be interpreted as instructions
    test_text = "This is a test of the text to speech system."

    test_config_map = %{
      api_key: Map.get(config, :api_key) || Map.get(config, "api_key"),
      voice_name: Map.get(config, :voice_name) || Map.get(config, "voice_name")
    }

    case VertexAI.generate_audio(test_text, test_config_map) do
      {:ok, _response} ->
        {:ok, "TTS credentials are valid"}

      {:error, :invalid_api_key} ->
        {:error, "Invalid API key"}

      {:error, reason} ->
        {:error, "Failed to validate credentials: #{inspect(reason)}"}
    end
  end

  @doc """
  Decrypts an API key for display (masked).
  """
  @spec decrypt_api_key_masked(integer(), binary()) :: String.t()
  def decrypt_api_key_masked(user_id, encrypted_key) when is_integer(user_id) do
    case Encryption.decrypt_message(user_id, encrypted_key) do
      {:ok, key} ->
        # Show first 8 and last 4 characters
        if String.length(key) > 12 do
          first = String.slice(key, 0, 8)
          last = String.slice(key, -4, 4)
          "#{first}...#{last}"
        else
          String.duplicate("*", String.length(key))
        end

      {:error, _} ->
        "****"
    end
  end

  ## Private Functions

  defp encrypt_api_key(user_id, api_key) when is_binary(api_key) and api_key != "" do
    # Trim whitespace before encrypting
    trimmed_key = String.trim(api_key)
    Encryption.encrypt_message(user_id, trimmed_key)
  end

  defp encrypt_api_key(_, _), do: {:error, :invalid_api_key}

  defp stringify_keys(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp maybe_encrypt_api_key(attrs, user_id) do
    api_key = Map.get(attrs, "api_key")

    if is_binary(api_key) and api_key != "" do
      case encrypt_api_key(user_id, api_key) do
        {:ok, encrypted} ->
          attrs
          |> Map.put("encrypted_api_key", encrypted)
          |> Map.delete("api_key")

        {:error, _} ->
          Map.delete(attrs, "api_key")
      end
    else
      Map.delete(attrs, "api_key")
    end
  end

  defp default_selected?(attrs) do
    Map.get(attrs, "is_default") in [true, "true", "on", 1, "1"] ||
      Map.get(attrs, :is_default) in [true, "true", "on", 1, "1"]
  end

  defp unset_other_defaults(user_id, keep_config_id) do
    UserTtsConfig
    |> where(user_id: ^user_id, is_default: true)
    |> where([c], c.id != ^keep_config_id)
    |> Repo.update_all(set: [is_default: false])
  end
end
