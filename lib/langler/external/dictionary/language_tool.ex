defmodule Langler.External.Dictionary.LanguageTool do
  @moduledoc """
  Integration with LanguageTool API for grammar checking and part-of-speech tagging.
  """

  alias Langler.External.Dictionary.Cache

  @default_endpoint "https://api.languagetool.org/v2/check"

  @type pos_result :: %{
          part_of_speech: String.t() | nil,
          lemma: String.t() | nil
        }

  @doc """
  Analyzes a word or phrase to extract part-of-speech and lemma information.

  Returns {:ok, result} with part_of_speech and lemma, or {:error, reason} on failure.
  """
  @spec analyze(String.t(), keyword()) :: {:ok, pos_result()} | {:error, term()}
  def analyze(text, opts \\ []) when is_binary(text) do
    language = opts[:language] || "spanish"
    cache_key = {String.downcase(language), String.downcase(text)}
    table = cache_table()

    Cache.get_or_store(table, cache_key, [ttl: ttl()], fn ->
      with {:ok, endpoint} <- fetch_config(),
           {:ok, response} <- request(endpoint, text, language) do
        extract_pos_info(response, text)
      end
    end)
  end

  @doc """
  Checks grammar and returns full analysis including part-of-speech tags.
  """
  @spec check(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def check(text, opts \\ []) when is_binary(text) do
    language = opts[:language] || "spanish"

    with {:ok, endpoint} <- fetch_config() do
      request(endpoint, text, language)
    end
  end

  defp fetch_config do
    config = Application.get_env(:langler, __MODULE__, [])
    endpoint = Keyword.get(config, :endpoint, @default_endpoint)

    {:ok, endpoint}
  end

  defp request(endpoint, text, language) do
    language_code = language_to_code(language)

    # LanguageTool API expects form-encoded POST data
    form_data = %{
      "text" => String.trim(to_string(text || "")),
      "language" => language_code,
      "enabledOnly" => "false",
      "level" => "default"
    }

    case Req.post(
           url: endpoint,
           form: form_data,
           retry: false
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_pos_info(response, text) do
    # LanguageTool response structure:
    # {
    #   "software": {...},
    #   "language": {...},
    #   "matches": [
    #     {
    #       "message": "...",
    #       "shortMessage": "...",
    #       "replacements": [...],
    #       "offset": 0,
    #       "length": 4,
    #       "context": {...},
    #       "rule": {
    #         "id": "...",
    #         "description": "...",
    #         "category": {
    #           "id": "GRAMMAR|TYPOS|STYLE|...",
    #           "name": "..."
    #         }
    #       }
    #     }
    #   ],
    #   "sentenceRanges": [...]
    # }

    matches = Map.get(response, "matches", [])

    # Extract POS from rule categories
    # LanguageTool categories can give us hints about word types
    pos_tag =
      matches
      |> Enum.find_value(fn match ->
        rule = Map.get(match, "rule", %{})
        category = Map.get(rule, "category", %{})
        category_id = Map.get(category, "id", "")
        rule_id = Map.get(rule, "id", "")

        # Try to extract POS from rule ID or category
        extract_pos_from_rule(rule_id, category_id)
      end)

    # For lemma, try to extract from replacements or use the word itself
    lemma = extract_lemma_from_response(response, text) || text

    result = %{
      part_of_speech: normalize_pos_tag(pos_tag),
      lemma: lemma
    }

    {:ok, result}
  end

  defp extract_pos_from_rule(rule_id, category_id) do
    # LanguageTool rule IDs often contain POS information
    # Examples: "ES_VERB_AGREEMENT", "ES_NOUN_AGREEMENT", etc.
    rule_lower = String.downcase(rule_id)
    category_lower = String.downcase(category_id)

    cond do
      String.contains?(rule_lower, "verb") or String.contains?(category_lower, "verb") ->
        "Verb"

      String.contains?(rule_lower, "noun") or String.contains?(category_lower, "noun") ->
        "Noun"

      String.contains?(rule_lower, "adjective") or String.contains?(category_lower, "adjective") ->
        "Adjective"

      String.contains?(rule_lower, "adverb") or String.contains?(category_lower, "adverb") ->
        "Adverb"

      String.contains?(rule_lower, "pronoun") or String.contains?(category_lower, "pronoun") ->
        "Pronoun"

      String.contains?(rule_lower, "preposition") or
          String.contains?(category_lower, "preposition") ->
        "Preposition"

      String.contains?(rule_lower, "article") or String.contains?(category_lower, "article") ->
        "Article"

      true ->
        nil
    end
  end

  defp extract_lemma_from_response(response, _text) do
    # LanguageTool doesn't always provide lemma directly
    # We can try to extract it from matches or use the word itself
    matches = Map.get(response, "matches", [])

    # Look for replacement suggestions that might indicate lemma
    # Often the first replacement is the corrected/lemma form
    lemma =
      matches
      |> Enum.find_value(fn match ->
        replacements = Map.get(match, "replacements", [])
        first_replacement = List.first(replacements)

        if first_replacement do
          Map.get(first_replacement, "value")
        else
          nil
        end
      end)

    # If no lemma found, return nil (caller will use capitalized word)
    lemma
  end

  defp normalize_pos_tag(nil), do: nil

  defp normalize_pos_tag(tag) when is_binary(tag) do
    # Map LanguageTool category IDs to standard POS tags
    case String.downcase(tag) do
      tag when tag in ["verb", "verb_form"] -> "Verb"
      tag when tag in ["noun", "noun_form"] -> "Noun"
      tag when tag in ["adjective", "adj"] -> "Adjective"
      tag when tag in ["adverb", "adv"] -> "Adverb"
      tag when tag in ["pronoun"] -> "Pronoun"
      tag when tag in ["preposition", "prep"] -> "Preposition"
      tag when tag in ["conjunction", "conj"] -> "Conjunction"
      tag when tag in ["article", "art"] -> "Article"
      tag when tag in ["determiner", "det"] -> "Determiner"
      _ -> tag |> String.split("_") |> List.first() |> String.capitalize()
    end
  end

  defp language_to_code("spanish"), do: "es"
  defp language_to_code("english"), do: "en"
  defp language_to_code("french"), do: "fr"
  defp language_to_code("portuguese"), do: "pt"
  defp language_to_code("german"), do: "de"
  defp language_to_code("italian"), do: "it"

  defp language_to_code(code) when is_binary(code) and byte_size(code) == 2,
    do: String.downcase(code)

  defp language_to_code(_), do: "es"

  defp cache_table do
    config = Application.get_env(:langler, __MODULE__, [])
    Keyword.get(config, :cache_table, :language_tool_cache)
  end

  defp ttl do
    config = Application.get_env(:langler, __MODULE__, [])
    Keyword.get(config, :ttl, :timer.hours(12))
  end
end
