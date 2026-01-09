defmodule Langler.Content.Readability do
  @moduledoc """
  Wrapper around the Readability Rust NIF. Falls back to a noop parser in dev/test until the NIF ships.
  """

  @spec parse(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def parse(html, opts \\ [])

  def parse(html, opts) when is_binary(html) do
    cond do
      not use_nif?() ->
        fallback(html)

      nif_available?() ->
        try do
          Langler.Content.ReadabilityNif.parse(html, opts)
        rescue
          e -> {:error, e}
        end

      true ->
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

  defp use_nif? do
    Application.get_env(:langler, __MODULE__, [])
    |> Keyword.get(:use_nif, true)
  end
end
