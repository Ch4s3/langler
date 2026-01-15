defmodule Langler.Chat.TokenCounter do
  @moduledoc """
  Token counting utilities for chat messages.

  Uses approximate counting: token_count ≈ string_length / 4
  This is a rough approximation that works reasonably well for English
  and Romance languages.

  For accurate token counting, use tiktoken or similar libraries in the future.
  """

  @doc """
  Counts approximate tokens for a given string.

  ## Examples

      iex> TokenCounter.count_tokens("Hello world")
      3

      iex> TokenCounter.count_tokens("A longer message with more words")
      9
  """
  @spec count_tokens(String.t()) :: integer()
  def count_tokens(content) when is_binary(content) do
    # Approximate: 1 token ≈ 4 characters
    char_count = String.length(content)
    max(1, div(char_count, 4))
  end

  def count_tokens(_), do: 0

  @doc """
  Counts tokens for an entire message array.

  ## Parameters
    - `messages`: List of message maps with `:content` field

  ## Returns
    - Total approximate token count across all messages
  """
  @spec count_message_tokens(list(map())) :: integer()
  def count_message_tokens(messages) when is_list(messages) do
    messages
    |> Enum.map(fn
      %{content: content} -> count_tokens(content)
      _ -> 0
    end)
    |> Enum.sum()
  end

  def count_message_tokens(_), do: 0

  @doc """
  Formats token count for display.

  ## Examples

      iex> TokenCounter.format_count(1234)
      "~1.2k tokens"

      iex> TokenCounter.format_count(567)
      "~567 tokens"

      iex> TokenCounter.format_count(42_567)
      "~42.6k tokens"
  """
  @spec format_count(integer()) :: String.t()
  def format_count(count) when is_integer(count) and count >= 10_000 do
    "~#{Float.round(count / 1000, 1)}k tokens"
  end

  def format_count(count) when is_integer(count) and count >= 1_000 do
    "~#{Float.round(count / 1000, 1)}k tokens"
  end

  def format_count(count) when is_integer(count) do
    "~#{count} tokens"
  end

  def format_count(_), do: "~0 tokens"
end
