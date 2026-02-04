defmodule Langler.Vocabulary.DeckSuggester do
  @moduledoc """
  LLM-powered deck suggestion service.
  Analyzes ungrouped words and suggests thematic, grammatical,
  and difficulty-based deck groupings.
  """

  require Logger

  alias Langler.Accounts.LlmConfig
  alias Langler.Chat.Encryption
  alias Langler.LLM.Adapters.ChatGPT
  alias Langler.Vocabulary

  @min_words_for_suggestions 10

  @doc """
  Suggests deck groupings for ungrouped words.
  Returns {:ok, suggestions} or {:error, reason}.

  Each suggestion is a map:
  %{
    name: "Food & Dining",
    description: "Words related to meals, ingredients, and restaurants",
    category: "thematic",  # or "grammatical" or "difficulty"
    word_ids: [1, 5, 12, 34],
    words: ["comer", "beber", ...],
    confidence: 0.85
  }
  """
  def suggest_groupings(user_id, opts \\ []) do
    with {:ok, words} <- get_ungrouped_words(user_id),
         :ok <- validate_word_count(words),
         {:ok, response} <- get_llm_response(user_id, words, opts) do
      parse_response(response, words)
    end
  end

  defp get_llm_response(user_id, words, opts) do
    if content = opts[:inject_response] do
      {:ok, content}
    else
      with {:ok, chat_config} <- build_chat_config(user_id) do
        call_llm(words, chat_config, opts)
      end
    end
  end

  defp get_ungrouped_words(user_id) do
    words = Vocabulary.list_ungrouped_words(user_id)

    if Enum.empty?(words) do
      {:error, :no_ungrouped_words}
    else
      {:ok, words}
    end
  end

  defp validate_word_count(words) do
    if length(words) < @min_words_for_suggestions do
      {:error, {:too_few_words, length(words)}}
    else
      :ok
    end
  end

  defp build_chat_config(user_id) do
    case LlmConfig.get_default_config(user_id) do
      nil ->
        {:error, :no_llm_config}

      config ->
        with {:ok, api_key} <- Encryption.decrypt_message(user_id, config.encrypted_api_key) do
          {:ok,
           %{
             api_key: api_key,
             model: config.model,
             temperature: config.temperature,
             max_tokens: config.max_tokens
           }}
        end
    end
  end

  defp call_llm(words, chat_config, _opts) do
    target_count = suggestion_count(length(words))
    prompt = build_prompt(words, target_count)

    messages = [
      %{role: "user", content: prompt}
    ]

    Logger.debug(
      "DeckSuggester: Requesting #{target_count} suggestions for #{length(words)} words"
    )

    case ChatGPT.chat(messages, chat_config) do
      {:ok, response} ->
        {:ok, response.content}

      {:error, reason} ->
        Logger.error("DeckSuggester: LLM call failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp suggestion_count(word_count) do
    cond do
      word_count < 20 -> 2
      word_count < 50 -> 3
      word_count < 100 -> 4
      word_count < 200 -> 5
      true -> 6
    end
  end

  defp build_prompt(words, target_count) do
    word_list =
      Enum.map_join(words, "\n", fn w ->
        "- #{w.normalized_form} (#{w.part_of_speech || "unknown"}): #{first_definition(w)}"
      end)

    """
    You are a language learning assistant helping organize vocabulary into study decks.

    Analyze these #{length(words)} words and suggest #{target_count} deck groupings.
    Use a MIX of grouping strategies:
    - **Thematic**: Topic-based (food, travel, emotions, work, nature, etc.)
    - **Grammatical**: Part-of-speech or pattern-based (action verbs, -tion nouns, etc.)
    - **Difficulty**: Frequency or complexity-based (everyday basics, advanced vocabulary)

    Words to analyze:
    #{word_list}

    IMPORTANT: Respond with ONLY valid JSON, no markdown code blocks. Use this exact format:
    {
      "suggestions": [
        {
          "name": "Deck Name",
          "description": "Brief description of what unifies these words",
          "category": "thematic",
          "words": ["word1", "word2", "word3"],
          "confidence": 0.85
        }
      ]
    }

    Rules:
    - Each word should appear in at most ONE suggestion
    - Not every word needs to be grouped (ungroupable words can be skipped)
    - Minimum 3 words per deck suggestion
    - Confidence is 0.0-1.0 indicating how well words fit together
    - category must be one of: "thematic", "grammatical", "difficulty"
    """
  end

  defp first_definition(word) do
    case word.definitions do
      [first | _] -> String.slice(first, 0, 80)
      _ -> "no definition"
    end
  end

  defp parse_response(content, words) do
    # Strip markdown code blocks if present
    json_content =
      content
      |> String.trim()
      |> String.replace(~r/^```json\s*/m, "")
      |> String.replace(~r/^```\s*/m, "")
      |> String.trim()

    case Jason.decode(json_content) do
      {:ok, %{"suggestions" => suggestions}} when is_list(suggestions) ->
        parsed = parse_suggestions(suggestions, words)
        {:ok, parsed}

      {:ok, _} ->
        Logger.error("DeckSuggester: Invalid response format, missing 'suggestions' key")
        {:error, :invalid_format}

      {:error, reason} ->
        Logger.error("DeckSuggester: Failed to parse JSON: #{inspect(reason)}")
        {:error, :invalid_json}
    end
  end

  defp parse_suggestions(suggestions, words) do
    word_map = build_word_map(words)

    suggestions
    |> Enum.map(&parse_single_suggestion(&1, word_map))
    |> Enum.filter(fn s -> length(s.word_ids) >= 3 end)
  end

  defp build_word_map(words) do
    Map.new(words, fn w -> {w.normalized_form, w} end)
  end

  defp parse_single_suggestion(suggestion, word_map) do
    word_list = suggestion["words"] || []

    {word_ids, found_words} =
      Enum.reduce(word_list, {[], []}, fn word_str, {ids, found} ->
        case Map.get(word_map, word_str) do
          nil -> {ids, found}
          word -> {[word.id | ids], [word_str | found]}
        end
      end)

    %{
      name: suggestion["name"],
      description: suggestion["description"],
      category: suggestion["category"] || "thematic",
      word_ids: Enum.reverse(word_ids),
      words: Enum.reverse(found_words),
      confidence: suggestion["confidence"] || 0.5
    }
  end
end
