defmodule Langler.Accounts.GoogleTranslateConfig do
  @moduledoc """
  Context for managing user Google Translate API configurations.
  """

  import Ecto.Query
  alias Langler.Accounts.{User, UserGoogleTranslateConfig}
  alias Langler.Chat.Encryption
  alias Langler.External.Dictionary.Google
  alias Langler.Repo

  @doc """
  Gets all Google Translate configs for a user.
  """
  @spec get_user_configs(integer()) :: list(UserGoogleTranslateConfig.t())
  def get_user_configs(user_id) when is_integer(user_id) do
    UserGoogleTranslateConfig
    |> where(user_id: ^user_id)
    |> Repo.all()
  end

  @doc """
  Gets the default Google Translate config for a user.
  """
  @spec get_default_config(integer()) :: UserGoogleTranslateConfig.t() | nil
  def get_default_config(user_id) when is_integer(user_id) do
    UserGoogleTranslateConfig
    |> where(user_id: ^user_id, is_default: true)
    |> Repo.one()
  end

  @doc """
  Gets a specific Google Translate config by ID.
  """
  @spec get_config(integer()) :: UserGoogleTranslateConfig.t() | nil
  def get_config(config_id) when is_integer(config_id) do
    Repo.get(UserGoogleTranslateConfig, config_id)
  end

  @doc """
  Checks if Google Translate is enabled for a user.
  Returns true only if user has a default config AND enabled == true.
  """
  @spec translate_enabled?(integer()) :: boolean()
  def translate_enabled?(user_id) when is_integer(user_id) do
    case get_default_config(user_id) do
      %UserGoogleTranslateConfig{enabled: true} -> true
      _ -> false
    end
  end

  @doc """
  Gets the decrypted API key for a user's default config.
  Returns nil if no enabled config exists.
  """
  @spec get_api_key(integer()) :: String.t() | nil
  def get_api_key(user_id) when is_integer(user_id) do
    case get_default_config(user_id) do
      %UserGoogleTranslateConfig{enabled: true, encrypted_api_key: encrypted_key} ->
        case Encryption.decrypt_message(user_id, encrypted_key) do
          {:ok, key} -> key
          {:error, _} -> nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Creates a new Google Translate config with encrypted API key.
  """
  @spec create_config(User.t(), map()) ::
          {:ok, UserGoogleTranslateConfig.t()} | {:error, Ecto.Changeset.t()}
  def create_config(%User{} = user, attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    with {:ok, encrypted_key} <- encrypt_api_key(user.id, Map.get(attrs, "api_key")) do
      attrs =
        attrs
        |> Map.put("encrypted_api_key", encrypted_key)
        |> Map.put("user_id", user.id)
        |> Map.delete("api_key")

      # If this is the first config, make it default
      is_first = get_user_configs(user.id) == []

      attrs =
        if is_first do
          Map.put(attrs, "is_default", true)
        else
          attrs
        end

      %UserGoogleTranslateConfig{}
      |> UserGoogleTranslateConfig.changeset(attrs)
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
  Updates an existing Google Translate config.
  """
  @spec update_config(UserGoogleTranslateConfig.t(), map()) ::
          {:ok, UserGoogleTranslateConfig.t()} | {:error, Ecto.Changeset.t()}
  def update_config(%UserGoogleTranslateConfig{} = config, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> maybe_encrypt_api_key(config.user_id)

    config
    |> UserGoogleTranslateConfig.changeset(attrs)
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
  Deletes a Google Translate config.
  """
  @spec delete_config(UserGoogleTranslateConfig.t()) ::
          {:ok, UserGoogleTranslateConfig.t()} | {:error, Ecto.Changeset.t()}
  def delete_config(%UserGoogleTranslateConfig{} = config) do
    Repo.delete(config)
  end

  @doc """
  Tests if Google Translate API key is valid by making a test translation request.
  """
  @spec test_config(map()) :: {:ok, String.t()} | {:error, term()}
  def test_config(config) when is_map(config) do
    api_key = Map.get(config, :api_key) || Map.get(config, "api_key")

    if is_nil(api_key) or api_key == "" do
      {:error, "API key is required"}
    else
      # Test with a simple translation
      case Google.translate("test", from: "en", to: "es", api_key: api_key) do
        {:ok, _result} ->
          {:ok, "Google Translate API key is valid"}

        {:error, {:http_error, 403, _}} ->
          {:error, "Invalid API key or insufficient permissions"}

        {:error, {:http_error, status, _}} ->
          {:error, "Failed to validate credentials: HTTP #{status}"}

        {:error, reason} ->
          {:error, "Failed to validate credentials: #{inspect(reason)}"}
      end
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
    UserGoogleTranslateConfig
    |> where(user_id: ^user_id, is_default: true)
    |> where([c], c.id != ^keep_config_id)
    |> Repo.update_all(set: [is_default: false])
  end
end
