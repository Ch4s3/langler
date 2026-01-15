defmodule Langler.LLM.Adapter do
  @moduledoc """
  Behavior for LLM adapters.

  Defines the interface that all LLM providers must implement.
  """

  @type message :: %{role: String.t(), content: String.t()}
  @type config :: %{
          api_key: String.t(),
          model: String.t(),
          temperature: float(),
          max_tokens: integer(),
          base_url: String.t() | nil
        }
  @type chat_response :: %{
          content: String.t(),
          model: String.t(),
          usage: %{
            prompt_tokens: integer(),
            completion_tokens: integer(),
            total_tokens: integer()
          }
        }

  @doc """
  Sends a chat completion request to the LLM provider.

  ## Parameters
    - `messages`: List of message maps with `:role` and `:content`
    - `config`: Configuration map with API key and model settings

  ## Returns
    - `{:ok, response}` with the LLM response
    - `{:error, reason}` on failure
  """
  @callback chat(messages :: list(message()), config :: config()) ::
              {:ok, chat_response()} | {:error, term()}

  @doc """
  Validates the configuration for this adapter.

  ## Parameters
    - `config`: Configuration map to validate

  ## Returns
    - `{:ok, config}` if valid
    - `{:error, reason}` if invalid
  """
  @callback validate_config(config :: map()) :: {:ok, config()} | {:error, String.t()}
end
