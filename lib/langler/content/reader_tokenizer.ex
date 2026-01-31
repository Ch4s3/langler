defmodule Langler.Content.ReaderTokenizer do
  @moduledoc """
  Tokenizes article/sentence content the same way as the article reader (ArticleLive.Show).

  Used by IdiomSpanMatcher so idiom start/end positions match the reader's token indices.
  """

  alias Langler.Content.ArticleImporter

  @token_regex ~r/\p{L}+\p{M}*|[^\p{L}]+/u

  @doc """
  Tokenizes content into the same token list as the reader.

  Returns a list of token strings (words, spaces, punctuation) so that
  index i corresponds to the same token as in ArticleLive.Show.
  """
  @spec tokenize(String.t()) :: [String.t()]
  def tokenize(content) when is_binary(content) do
    normalized = ArticleImporter.normalize_punctuation_spacing(content)

    normalized
    |> extract_tokens()
    |> normalize_tokens()
    |> attach_spaces_to_tokens()
  end

  def tokenize(_), do: []

  defp extract_tokens(content) do
    @token_regex
    |> Regex.scan(content)
    |> Enum.map(&hd/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_tokens(tokens) do
    tokens
    |> Enum.flat_map(&split_punctuation_token/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_punctuation_token(text) do
    cond do
      dash_with_adjacent_punct?(text) -> split_dash_from_punct(text)
      space_surrounded_punctuation?(text) -> split_and_trim(text)
      punctuation_with_spaces?(text) -> split_and_trim(text)
      true -> [text]
    end
  end

  defp space_surrounded_punctuation?(text),
    do: String.match?(text, ~r/^\s+[^\p{L}\s]+\s+$/u)

  defp punctuation_with_spaces?(text) do
    String.match?(text, ~r/^[^\p{L}]+$/u) and not String.match?(text, ~r/^\s+$/u) and
      String.contains?(text, " ")
  end

  defp dash_with_adjacent_punct?(text) do
    String.match?(text, ~r/^[^\p{L}]+$/u) and contains_dash?(text) and String.length(text) > 1
  end

  defp contains_dash?(text) do
    String.contains?(text, "—") or String.contains?(text, "–") or
      String.contains?(text, "−") or String.contains?(text, "-")
  end

  defp split_dash_from_punct(text) do
    {tokens, current} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], ""}, &split_grapheme_by_dash/2)

    tokens = if current != "", do: [current | tokens], else: tokens

    tokens
    |> Enum.reverse()
    |> Enum.flat_map(&split_with_spaces/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_grapheme_by_dash(grapheme, {tokens, current}) do
    if dash_grapheme?(grapheme) do
      emit_dash_token(grapheme, tokens, current)
    else
      {tokens, current <> grapheme}
    end
  end

  defp emit_dash_token(grapheme, tokens, current) do
    tokens =
      if current != "" do
        [grapheme, current | tokens]
      else
        [grapheme | tokens]
      end

    {tokens, ""}
  end

  defp dash_grapheme?(grapheme), do: grapheme in ["—", "–", "−", "-"]

  defp split_and_trim(text) do
    split_with_spaces(text)
    |> Enum.map(&normalize_punctuation_chunk/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp normalize_punctuation_chunk(token) do
    if String.match?(token, ~r/^[^\p{L}\s]+$/u), do: String.trim(token), else: token
  end

  defp split_with_spaces(text) do
    if String.match?(text, ~r/^\s+$/) do
      [text]
    else
      trimmed = String.trim(text)
      trimmed_leading = String.trim_leading(text)
      trimmed_trailing = String.trim_trailing(text)
      leading_len = String.length(text) - String.length(trimmed_leading)
      trailing_start = String.length(trimmed_trailing)
      text_len = String.length(text)
      leading_space = if leading_len > 0, do: String.slice(text, 0, leading_len), else: ""

      trailing_space =
        if trailing_start < text_len,
          do: String.slice(text, trailing_start, text_len - trailing_start),
          else: ""

      result = []
      result = if leading_space != "", do: [leading_space | result], else: result
      result = if trimmed != "", do: [trimmed | result], else: result
      result = if trailing_space != "", do: [trailing_space | result], else: result
      Enum.reverse(result) |> Enum.filter(&(&1 != ""))
    end
  end

  defp attach_spaces_to_tokens(tokens) do
    tokens
    |> ensure_spaces_around_dashes()
    |> collapse_space_before_punct()
  end

  defp ensure_spaces_around_dashes([]), do: []
  defp ensure_spaces_around_dashes([single]), do: [single]

  defp ensure_spaces_around_dashes(tokens) do
    tokens
    |> Enum.with_index()
    |> Enum.flat_map(fn {token, idx} ->
      prev = if idx > 0, do: Enum.at(tokens, idx - 1), else: nil
      next = Enum.at(tokens, idx + 1)
      if dash_token?(token), do: build_dash_with_spaces(token, prev, next), else: [token]
    end)
  end

  defp build_dash_with_spaces(token, prev, next) do
    [token]
    |> maybe_prepend_space(prev)
    |> maybe_append_space(next)
  end

  defp maybe_prepend_space(result, prev) do
    if prev != nil and word_token?(prev), do: [" " | result], else: result
  end

  defp maybe_append_space(result, next) do
    if next != nil and (word_token?(next) or opening_quote_token?(next)),
      do: result ++ [" "],
      else: result
  end

  defp dash_token?(token), do: token in ["—", "–", "−", "-"]

  defp word_token?(token), do: String.match?(token, ~r/^\p{L}+$/u)

  defp opening_quote_token?(token) do
    left_double_quote = <<226, 128, 156>>
    token == "\"" or token == "'" or token == left_double_quote or token == "«" or token == "‹"
  end

  defp collapse_space_before_punct([]), do: []
  defp collapse_space_before_punct([single]), do: [single]

  defp collapse_space_before_punct(tokens) do
    tokens_with_next = Enum.zip(tokens, tl(tokens) ++ [nil])

    tokens_with_next
    |> Enum.reject(fn {current, next} ->
      is_space = String.match?(current, ~r/^\s+$/)
      is_space and next != nil and attaching_punct?(next)
    end)
    |> Enum.map(fn {current, next} ->
      if next != nil and attaching_punct?(next), do: String.trim_trailing(current), else: current
    end)
    |> Enum.filter(&(&1 != ""))
  end

  defp attaching_punct?(token) do
    right_double_quote = <<226, 128, 157>>
    right_single_quote = <<226, 128, 153>>

    String.match?(token, ~r/^[,\.;:!?\)\]\}»›]/u) or
      String.starts_with?(token, right_double_quote) or
      String.starts_with?(token, right_single_quote)
  end
end
