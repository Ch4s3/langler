defmodule Langler.Content.Readability do
  @moduledoc """
  Wrapper around the Readability Rust NIF for extracting article content.

  Falls back to a noop parser in dev/test until the NIF ships. Provides
  a consistent interface for extracting readable content from HTML.
  """

  alias Langler.Content.ReadabilityNif

  @spec parse(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def parse(html, opts \\ [])

  def parse(html, opts) when is_binary(html) do
    cond do
      not use_nif?() ->
        log_warning("[Readability] NIF disabled via config, using fallback")
        fallback(html)

      nif_available?() ->
        base_url = Keyword.get(opts, :base_url)
        parse_with_nif(base_url, html)

      true ->
        log_warning("[Readability] NIF not available, using fallback")
        fallback(html)
    end
  end

  def parse(_, _), do: {:error, :invalid_content}

  defp parse_with_nif(base_url, html) do
    ReadabilityNif.parse(html, base_url)
    |> handle_nif_result(html)
  rescue
    error ->
      log_error("[Readability] NIF raised exception: #{inspect(error)}")
      {:error, error}
  end

  defp handle_nif_result({:error, :nif_not_loaded}, html) do
    log_warning("[Readability] NIF returned :nif_not_loaded, using fallback")
    fallback(html)
  end

  defp handle_nif_result({:error, reason}, _html) do
    log_error("[Readability] NIF returned error: #{inspect(reason)}")
    {:error, reason}
  end

  defp handle_nif_result(map, _html) when is_map(map) do
    length_info = map[:length] || map["length"] || "unknown"
    log_info("[Readability] NIF successfully extracted content (length: #{length_info})")
    {:ok, map}
  end

  defp handle_nif_result(other, _html) do
    log_info("[Readability] NIF returned non-map result: #{inspect(other)}")
    {:ok, other}
  end

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
    Code.ensure_loaded?(ReadabilityNif) and function_exported?(ReadabilityNif, :parse, 2)
  end

  defp use_nif? do
    Application.get_env(:langler, __MODULE__, [])
    |> Keyword.get(:use_nif, true)
  end

  defp log_warning(message) do
    require Logger
    Logger.warning(message)
  end

  defp log_error(message) do
    require Logger
    Logger.error(message)
  end

  defp log_info(message) do
    require Logger
    Logger.info(message)
  end
end
