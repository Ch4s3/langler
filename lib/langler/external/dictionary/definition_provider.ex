defmodule Langler.External.Dictionary.DefinitionProvider do
  @moduledoc """
  Behavior for definition providers.

  Defines the interface that all definition providers must implement,
  allowing for interchangeable providers like Google Translate or LLM-based definitions.
  """

  @type definition_result :: %{
          translation: String.t() | nil,
          definitions: [String.t()]
        }

  @type opts :: [
          language: String.t(),
          target: String.t(),
          api_key: String.t() | nil,
          user_id: integer() | nil
        ]

  @doc """
  Gets the definition and translation for a given term.

  ## Parameters
    - `term`: The word or phrase to look up
    - `opts`: Options including:
      - `:language` - Source language (e.g., "spanish")
      - `:target` - Target language for translation (e.g., "en")
      - `:api_key` - API key if required by the provider
      - `:user_id` - User ID for user-specific configurations

  ## Returns
    - `{:ok, result}` with translation and definitions
    - `{:error, reason}` on failure
  """
  @callback get_definition(term :: String.t(), opts :: opts()) ::
              {:ok, definition_result()} | {:error, term()}
end
