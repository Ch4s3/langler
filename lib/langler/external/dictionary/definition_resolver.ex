defmodule Langler.External.Dictionary.DefinitionResolver do
  @moduledoc """
  Resolves which definition provider to use based on user configuration.

  Routing logic:
  1. If user has `use_llm_for_definitions` preference enabled, use LLM provider
  2. If Google Translate is configured and enabled, use Google provider
  3. If LLM is configured, fall back to LLM provider
  4. Otherwise, return an error indicating no provider is available
  """

  alias Langler.Accounts
  alias Langler.Accounts.{GoogleTranslateConfig, LlmConfig}
  alias Langler.External.Dictionary.{GoogleProvider, LLMProvider}

  @type provider :: :google | :llm
  @type opts :: [
          language: String.t(),
          target: String.t(),
          api_key: String.t() | nil,
          user_id: integer() | nil
        ]

  @doc """
  Gets a definition using the appropriate provider based on user configuration.

  ## Parameters
    - `term`: The word or phrase to look up
    - `opts`: Options including `:language`, `:target`, `:api_key`, `:user_id`

  ## Returns
    - `{:ok, result}` with translation and definitions
    - `{:error, reason}` on failure
  """
  @spec get_definition(String.t(), opts()) ::
          {:ok, map()} | {:error, term()}
  def get_definition(term, opts) when is_binary(term) do
    user_id = Keyword.get(opts, :user_id)

    case resolve_provider(user_id, opts) do
      {:ok, :google, resolved_opts} ->
        GoogleProvider.get_definition(term, resolved_opts)

      {:ok, :llm, resolved_opts} ->
        LLMProvider.get_definition(term, resolved_opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Determines which provider to use for the given user.

  Returns `{:ok, provider, opts}` or `{:error, reason}`.
  """
  @spec resolve_provider(integer() | nil, opts()) ::
          {:ok, provider(), opts()} | {:error, term()}
  def resolve_provider(nil, opts) do
    # No user ID - try Google with passed API key
    api_key = Keyword.get(opts, :api_key)

    if api_key do
      {:ok, :google, opts}
    else
      {:error, :no_provider_available}
    end
  end

  def resolve_provider(user_id, opts) when is_integer(user_id) do
    # Check user preference for LLM
    if prefers_llm?(user_id) do
      resolve_llm_provider(user_id, opts)
    else
      resolve_with_fallback(user_id, opts)
    end
  end

  defp resolve_with_fallback(user_id, opts) do
    # Try Google first, fall back to LLM
    case resolve_google_provider(user_id, opts) do
      {:ok, :google, resolved_opts} ->
        {:ok, :google, resolved_opts}

      {:error, _reason} ->
        # Fall back to LLM
        resolve_llm_provider(user_id, opts)
    end
  end

  defp resolve_google_provider(user_id, opts) do
    if GoogleTranslateConfig.translate_enabled?(user_id) do
      api_key = GoogleTranslateConfig.get_api_key(user_id)

      if api_key do
        {:ok, :google, Keyword.put(opts, :api_key, api_key)}
      else
        {:error, :google_api_key_not_available}
      end
    else
      {:error, :google_not_configured}
    end
  end

  defp resolve_llm_provider(user_id, opts) do
    if llm_configured?(user_id) do
      {:ok, :llm, Keyword.put(opts, :user_id, user_id)}
    else
      {:error, :no_provider_available}
    end
  end

  defp prefers_llm?(user_id) do
    case Accounts.get_user_preference(user_id) do
      %{use_llm_for_definitions: true} -> true
      _ -> false
    end
  end

  defp llm_configured?(user_id) do
    LlmConfig.get_default_config(user_id) != nil
  end
end
