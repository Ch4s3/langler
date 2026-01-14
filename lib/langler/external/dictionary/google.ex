defmodule Langler.External.Dictionary.Google do
  @moduledoc """
  Lightweight wrapper around Google Translate's dictionary data.
  """

  alias Langler.External.Dictionary.Cache

  @default_target "en"
  @default_dictionary_endpoint "https://translate.googleapis.com/translate_a/single"

  @spec translate(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def translate(term, opts \\ []) when is_binary(term) do
    source_language = opts[:from] || "spanish"
    target_language = opts[:to] || @default_target

    cache_key =
      {String.downcase(source_language), String.downcase(target_language),
       String.downcase(term)}

    table = cache_table()

    Cache.get_or_store(table, cache_key, [ttl: ttl()], fn ->
      endpoint = dictionary_endpoint()

      with {:ok, response} <- request_dictionary(endpoint, term, source_language, target_language) do
        {:ok, response}
      end
    end)
  end

  defp request_dictionary(endpoint, term, source, target) do
    params = [
      {"client", "gtx"},
      {"sl", language_code(source)},
      {"tl", language_code(target)},
      {"hl", language_code(target)},
      {"dt", "t"},
      {"dt", "bd"},
      {"dj", "1"},
      {"source", "input"},
      {"q", term}
    ]

    case Req.get(url: endpoint, params: params, retry: false) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, parse_dictionary_response(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_dictionary_response(%{"sentences" => sentences} = body) do
    translation =
      sentences
      |> Enum.map(&Map.get(&1, "trans", ""))
      |> Enum.join(" ")
      |> String.trim()
      |> blank_to_nil()

    definitions =
      body
      |> Map.get("dict", [])
      |> Enum.flat_map(&format_dictionary_entry/1)

    %{
      translation: translation,
      definitions: definitions
    }
  end

  defp parse_dictionary_response(_body) do
    %{
      translation: nil,
      definitions: []
    }
  end

  defp format_dictionary_entry(%{"entry" => entries} = dict) do
    IO.inspect(dict, label: "dict")
    pos = Map.get(dict, "pos")

    entries
    |> Enum.take(5)
    |> Enum.map(fn entry ->
      word = Map.get(entry, "word")
      reverse = Map.get(entry, "reverse_translation", [])

      [
        capitalize_word(word),
        render_pos(pos),
        render_reverse(reverse)
      ]
      |> Enum.reject(&is_nil_or_blank/1)
      |> Enum.join(" ")
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp format_dictionary_entry(_), do: []

  defp capitalize_word(nil), do: nil
  defp capitalize_word(""), do: ""

  defp capitalize_word(word) do
    word
    |> String.split(" ", parts: 2)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp render_pos(nil), do: nil
  defp render_pos(pos), do: "(#{pos})"

  defp render_reverse([]), do: nil

  defp render_reverse(list) when is_list(list) do
    "— #{Enum.join(list, ", ")}"
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp is_nil_or_blank(value) when is_binary(value), do: String.trim(value) == ""
  defp is_nil_or_blank(nil), do: true
  defp is_nil_or_blank(_), do: false

  defp dictionary_endpoint do
    config = Application.get_env(:langler, __MODULE__, [])
    Keyword.get(config, :dictionary_endpoint, @default_dictionary_endpoint)
  end

  defp language_code("spanish"), do: "es"
  defp language_code("english"), do: "en"
  defp language_code("french"), do: "fr"
  defp language_code("portuguese"), do: "pt"

  defp language_code(code) when is_binary(code) and byte_size(code) == 2,
    do: String.downcase(code)

  defp language_code(_), do: "en"

  defp cache_table do
    config = Application.get_env(:langler, __MODULE__, [])
    Keyword.get(config, :cache_table, :google_translation_cache)
  end

  defp ttl do
    config = Application.get_env(:langler, __MODULE__, [])
    Keyword.get(config, :ttl, :timer.hours(6))
  end
end
