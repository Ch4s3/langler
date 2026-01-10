defmodule Langler.External.Dictionary.Google do
  @moduledoc """
  Thin wrapper around the Google Translate API.
  """

  @default_target "en"

  @spec translate(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def translate(term, opts \\ []) when is_binary(term) do
    source_language = opts[:from] || "spanish"
    target_language = opts[:to] || @default_target

    with {:ok, endpoint, api_key} <- fetch_config() do
      body = build_body(term, source_language, target_language)
      request(endpoint, api_key, body)
    end
  end

  defp fetch_config do
    config = Application.get_env(:langler, __MODULE__, [])
    endpoint = Keyword.get(config, :endpoint)
    raw_key = Keyword.get(config, :api_key)
    api_key = resolve_key(raw_key)

    cond do
      is_nil(endpoint) -> {:error, :missing_endpoint}
      is_nil(api_key) -> {:error, :missing_api_key}
      true -> {:ok, endpoint, api_key}
    end
  end

  defp resolve_key(:runtime_env), do: System.get_env("GOOGLE_TRANSLATE_API_KEY")
  defp resolve_key(key), do: key

  defp build_body(term, source, target) do
    %{
      "q" => term,
      "source" => language_code(source),
      "target" => language_code(target),
      "format" => "text"
    }
  end

  defp request(endpoint, api_key, body) do
    case Req.post(url: endpoint, params: [key: api_key], json: body) do
      {:ok,
       %{
         status: 200,
         body: %{"data" => %{"translations" => [%{"translatedText" => translation}]}}
       }} ->
        {:ok, translation}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp language_code("spanish"), do: "es"
  defp language_code("english"), do: "en"
  defp language_code("french"), do: "fr"
  defp language_code("portuguese"), do: "pt"

  defp language_code(code) when is_binary(code) and byte_size(code) == 2,
    do: String.downcase(code)

  defp language_code(_), do: "en"
end
