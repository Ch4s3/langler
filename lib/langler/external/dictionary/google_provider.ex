defmodule Langler.External.Dictionary.GoogleProvider do
  @moduledoc """
  Google Translate definition provider.

  Implements the DefinitionProvider behavior using the Google Translate API
  for word translations and definitions.
  """

  @behaviour Langler.External.Dictionary.DefinitionProvider

  alias Langler.External.Dictionary.Google

  @impl true
  def get_definition(term, opts) when is_binary(term) do
    language = Keyword.get(opts, :language, "spanish")
    target = Keyword.get(opts, :target, "en")
    api_key = Keyword.get(opts, :api_key)

    case Google.translate(term, from: language, to: target, api_key: api_key) do
      {:ok, data} ->
        {:ok, normalize_result(data)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_result(data) do
    %{
      translation: Map.get(data, :translation),
      definitions: Map.get(data, :definitions, [])
    }
  end
end
