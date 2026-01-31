defmodule Langler.Content.IdiomSpanMatcher do
  @moduledoc """
  Finds token-index spans for idiom phrases in a sentence.

  Uses the same tokenization as the article reader (ReaderTokenizer) so
  start_position and end_position match the reader's token indices.
  """

  alias Langler.Content.ReaderTokenizer

  @type span :: %{start_position: non_neg_integer(), end_position: non_neg_integer()}

  @doc """
  Finds all token-index spans for the given phrases in the sentence.

  Returns a list of %{phrase: phrase_string, start_position: i, end_position: j}
  for each occurrence of each phrase. Positions are token indices (same as reader).
  """
  @spec find_spans(String.t(), [String.t()]) :: [
          %{
            phrase: String.t(),
            start_position: non_neg_integer(),
            end_position: non_neg_integer()
          }
        ]
  def find_spans(sentence_content, phrases)
      when is_binary(sentence_content) and is_list(phrases) do
    tokens = ReaderTokenizer.tokenize(sentence_content)

    phrases
    |> Enum.reject(&(is_binary(&1) and String.trim(&1) == ""))
    |> Enum.flat_map(fn phrase ->
      phrase_tokens = ReaderTokenizer.tokenize(phrase)
      find_phrase_occurrences(tokens, phrase_tokens, phrase)
    end)
    |> Enum.uniq_by(fn %{phrase: p, start_position: s, end_position: e} -> {p, s, e} end)
  end

  def find_spans(_, _), do: []

  defp find_phrase_occurrences(_tokens, [], _phrase), do: []
  defp find_phrase_occurrences([], _phrase_tokens, _phrase), do: []

  defp find_phrase_occurrences(tokens, phrase_tokens, phrase) do
    len = length(phrase_tokens)
    max_start = max(0, length(tokens) - len)

    0..max_start
    |> Enum.reduce([], fn start_idx, acc ->
      window = Enum.slice(tokens, start_idx, len)

      if tokens_match?(window, phrase_tokens) do
        end_idx = start_idx + len - 1
        [%{phrase: phrase, start_position: start_idx, end_position: end_idx} | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp tokens_match?(window, phrase_tokens) when length(window) != length(phrase_tokens),
    do: false

  defp tokens_match?(window, phrase_tokens) do
    Enum.zip(window, phrase_tokens)
    |> Enum.all?(fn {a, b} -> token_equal?(a, b) end)
  end

  defp token_equal?(a, b) when is_binary(a) and is_binary(b) do
    a_letter = String.match?(a, ~r/^\p{L}/u)
    b_letter = String.match?(b, ~r/^\p{L}/u)

    if a_letter and b_letter do
      String.downcase(String.trim(a)) == String.downcase(String.trim(b))
    else
      a == b
    end
  end
end
