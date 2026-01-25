defmodule Langler.External.Dictionary.LLMProvider do
  @moduledoc """
  LLM-based definition provider.

  Implements the DefinitionProvider behavior using the configured LLM (ChatGPT)
  to provide word translations and definitions. This serves as a fallback when
  Google Translate is not configured, or can be used directly via user preference.
  """

  @behaviour Langler.External.Dictionary.DefinitionProvider

  alias Langler.Accounts.LlmConfig
  alias Langler.Chat.Encryption
  alias Langler.LLM.Adapters.ChatGPT

  require Logger

  @default_base_url "https://api.openai.com/v1"

  @system_prompt """
  You are a language learning dictionary assistant. Your task is to provide accurate translations and definitions for words.

  IMPORTANT: You must respond with ONLY valid JSON, no markdown code blocks, no additional text.

  Response format:
  {
    "translation": "the primary English translation of the word",
    "definitions": [
      "Definition 1 with part of speech in parentheses, e.g. 'To run (verb) — to move quickly on foot'",
      "Definition 2 if the word has multiple meanings",
      "Up to 5 most common definitions"
    ]
  }

  Guidelines:
  - The "translation" should be a single, concise translation (the most common meaning)
  - Each definition should include the part of speech in parentheses
  - Definitions should be clear and helpful for language learners
  - Include common usage context when helpful (e.g., "formal", "colloquial")
  - If the word is a verb, include the infinitive form
  - If you don't recognize the word, return: {"translation": null, "definitions": []}
  """

  @impl true
  def get_definition(term, opts) when is_binary(term) do
    language = Keyword.get(opts, :language, "spanish")
    target = Keyword.get(opts, :target, "en")
    user_id = Keyword.get(opts, :user_id)

    if is_nil(user_id) do
      {:error, :user_id_required}
    else
      get_definition_for_user(term, language, target, user_id)
    end
  end

  defp get_definition_for_user(term, language, target, user_id) do
    case get_llm_config(user_id) do
      {:ok, config} ->
        call_llm(term, language, target, config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_llm_config(user_id) do
    case LlmConfig.get_default_config(user_id) do
      nil ->
        {:error, :no_llm_config}

      config ->
        case Encryption.decrypt_message(user_id, config.encrypted_api_key) do
          {:ok, api_key} ->
            {:ok,
             %{
               api_key: api_key,
               model: config.model,
               # Use lower temperature for more deterministic definitions
               temperature: 0.3,
               max_tokens: 500,
               base_url: Map.get(config, :base_url) || @default_base_url
             }}

          {:error, reason} ->
            {:error, {:decryption_failed, reason}}
        end
    end
  end

  defp call_llm(term, language, target, config) do
    target_name = language_name(target)
    source_name = language_name(language)

    user_message = """
    Translate and define this #{source_name} word to #{target_name}: "#{term}"
    """

    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: user_message}
    ]

    case ChatGPT.chat(messages, config) do
      {:ok, response} ->
        parse_llm_response(response.content)

      {:error, reason} ->
        Logger.warning("LLM definition lookup failed: #{inspect(reason)}")
        {:error, {:llm_error, reason}}
    end
  end

  defp parse_llm_response(content) when is_binary(content) do
    # Strip potential markdown code block markers
    cleaned =
      content
      |> String.trim()
      |> String.replace(~r/^```json\s*/i, "")
      |> String.replace(~r/^```\s*/i, "")
      |> String.replace(~r/\s*```$/i, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, %{"translation" => translation, "definitions" => definitions}}
      when is_list(definitions) ->
        {:ok,
         %{
           translation: normalize_translation(translation),
           definitions: normalize_definitions(definitions)
         }}

      {:ok, _invalid_format} ->
        Logger.warning("LLM returned unexpected JSON format: #{content}")
        {:error, :invalid_response_format}

      {:error, decode_error} ->
        Logger.warning("Failed to parse LLM JSON response: #{inspect(decode_error)}")
        {:error, {:json_parse_error, decode_error}}
    end
  end

  defp normalize_translation(nil), do: nil
  defp normalize_translation(t) when is_binary(t), do: String.trim(t)
  defp normalize_translation(_), do: nil

  defp normalize_definitions(definitions) when is_list(definitions) do
    definitions
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(5)
  end

  defp normalize_definitions(_), do: []

  defp language_name("en"), do: "English"
  defp language_name("es"), do: "Spanish"
  defp language_name("spanish"), do: "Spanish"
  defp language_name("english"), do: "English"
  defp language_name("fr"), do: "French"
  defp language_name("french"), do: "French"
  defp language_name("pt"), do: "Portuguese"
  defp language_name("portuguese"), do: "Portuguese"
  defp language_name(other), do: String.capitalize(to_string(other))

  # Test helper - only used in tests to verify parsing logic
  @doc false
  def parse_response_for_test(content), do: parse_llm_response(content)
end
