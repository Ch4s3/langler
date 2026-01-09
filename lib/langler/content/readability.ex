defmodule Langler.Content.Readability do
  @moduledoc """
  Wrapper around the Readability Rust NIF. Falls back to a noop parser in dev/test until the NIF ships.
  """

  @spec parse(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def parse(html, opts \\ [])

  def parse(html, opts) when is_binary(html) do
    if nif_available?() do
      try do
        Langler.Content.ReadabilityNif.parse(html, opts)
      rescue
        e -> {:error, e}
      end
    else
      fallback(html)
    end
  end

  def parse(_, _), do: {:error, :invalid_content}

  defp fallback(html) do
    {:ok,
     %{
       title: nil,
       content: html,
       excerpt: nil,
       author: nil,
       length: String.length(html)
     }}
  end

  defp nif_available? do
    Code.ensure_loaded?(Langler.Content.ReadabilityNif) and
      function_exported?(Langler.Content.ReadabilityNif, :parse, 2)
  end
end
