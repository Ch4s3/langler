defmodule Langler.LLM.IdiomDetector do
  @moduledoc """
  Detects idioms and multi-word expressions in article text using an LLM.

  Returns phrases only (no positions); span matching is done deterministically
  by IdiomSpanMatcher so token indices stay in sync with the reader.
  """

  require Logger

  alias Langler.LLM.Adapters.ChatGPT

  @max_sentences 60
  @max_idioms_per_sentence 3

  @type idiom_sentence_result :: %{
          sentence_index: non_neg_integer(),
          phrases: [String.t()]
        }

  @doc """
  Detects idioms in article content.

  Sends the first N sentences to the LLM and parses a JSON response with
  idiom phrases per sentence. Returns phrases as they appear in the text.

  ## Options
  - `:max_sentences` - cap sentences sent to LLM (default: 60)
  - `:max_idioms_per_sentence` - prompt asks for at most this many per sentence (default: 3)

  ## Returns
  - `{:ok, [idiom_sentence_result()]}` - list of %{sentence_index: i, phrases: ["phrase1", ...]}
  - `{:error, term()}` - LLM or parse error
  """
  @spec detect(String.t(), String.t(), map(), keyword()) ::
          {:ok, [idiom_sentence_result()]} | {:error, term()}
  def detect(content, language, llm_config, opts \\ []) do
    max_sentences = Keyword.get(opts, :max_sentences, @max_sentences)
    max_per = Keyword.get(opts, :max_idioms_per_sentence, @max_idioms_per_sentence)

    sentences = split_sentences(content) |> Enum.take(max_sentences)

    if sentences == [] do
      {:ok, []}
    else
      prompt = build_prompt(sentences, language, max_per)
      messages = [%{role: "user", content: prompt}]

      config =
        llm_config
        |> Map.take([:api_key, :model, :base_url])
        |> Map.put_new(:temperature, 0.3)
        |> Map.put_new(:max_tokens, 2000)

      case ChatGPT.chat(messages, config) do
        {:ok, %{content: response_content}} ->
          parse_response(response_content, length(sentences))

        {:error, reason} ->
          Logger.warning("IdiomDetector LLM call failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Parses LLM JSON response into idiom sentence results.

  Expects JSON array of objects: [{"sentence_index": 0, "idioms": ["phrase1", ...]}, ...]
  """
  @spec parse_response(String.t(), non_neg_integer()) ::
          {:ok, [idiom_sentence_result()]} | {:error, term()}
  def parse_response(raw_content, num_sentences) do
    json_text = strip_json_block(raw_content)

    case Jason.decode(json_text) do
      {:ok, decoded} when is_list(decoded) ->
        results = decode_results(decoded)

        if valid_sentence_indices?(results, num_sentences),
          do: {:ok, results},
          else: {:error, :invalid_sentence_index}

      {:ok, _} ->
        {:error, :invalid_structure}

      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  defp decode_results(decoded) do
    decoded
    |> Enum.filter(&is_map/1)
    |> Enum.map(&row_to_result/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.sentence_index)
  end

  defp valid_sentence_indices?(results, num_sentences) do
    not Enum.any?(results, fn r -> r.sentence_index < 0 or r.sentence_index >= num_sentences end)
  end

  defp build_prompt(sentences, language, max_per) do
    lang_name = language_name(language)

    numbered =
      sentences
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {text, i} -> "#{i}: #{text}" end)

    """
    You are an expert in #{lang_name} idioms and fixed expressions.

    Below are #{length(sentences)} sentences from an article (index: sentence text).
    Identify up to #{max_per} idioms or multi-word expressions in each sentence.
    Return ONLY a JSON array of objects. No markdown, no explanation.

    Format for each object:
    - "sentence_index": (integer, 0-based)
    - "idioms": (array of strings - the exact phrase as it appears in the sentence)

    Rules:
    - Only multi-word expressions (at least 2 words). No single words.
    - Use the exact wording from the sentence.
    - Prefer common idioms and set phrases. Skip rare or doubtful cases.
    - If a sentence has no idioms, omit it or use "idioms": [].

    Sentences:
    #{numbered}

    JSON array:
    """
  end

  defp language_name("spanish"), do: "Spanish"
  defp language_name("es"), do: "Spanish"
  defp language_name(lang) when is_binary(lang), do: String.capitalize(lang)
  defp language_name(_), do: "the target language"

  defp split_sentences(content) when is_binary(content) do
    content
    |> String.trim()
    |> String.split(~r/(?<=[\.!\?])\s+/, trim: true)
  end

  defp row_to_result(%{"sentence_index" => idx, "idioms" => idioms})
       when is_integer(idx) and is_list(idioms) do
    phrases =
      idioms
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    %{sentence_index: idx, phrases: phrases}
  end

  defp row_to_result(_), do: nil

  defp strip_json_block(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.replace(~r/^```(?:json)?\s*/i, "")
    |> String.replace(~r/\s*```\s*$/i, "")
    |> String.trim()
  end
end
