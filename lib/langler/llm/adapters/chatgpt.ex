defmodule Langler.LLM.Adapters.ChatGPT do
  @moduledoc """
  OpenAI ChatGPT adapter implementation for language learning.

  Implements the LLM.Adapter behavior for OpenAI's ChatGPT API, providing
  chat functionality with support for multiple languages and conversation contexts.
  """

  @behaviour Langler.LLM.Adapter

  require Logger

  @default_base_url "https://api.openai.com/v1"
  @default_model "gpt-4o-mini"
  @default_temperature 0.7
  @default_max_tokens 2000

  # Valid OpenAI models (based on https://platform.openai.com/docs/models)
  # We use a pattern match approach to support models that start with known prefixes
  @valid_model_prefixes [
    # gpt-4o, gpt-4o-mini, gpt-4o-2024-08-06, etc.
    "gpt-4o",
    # gpt-4-turbo, gpt-4-turbo-preview, etc.
    "gpt-4-turbo",
    # gpt-4, gpt-4-0613, etc.
    "gpt-4",
    # gpt-3.5-turbo, gpt-3.5-turbo-16k, etc.
    "gpt-3.5-turbo",
    # o1-preview, o1-mini, etc.
    "o1",
    # o3-mini, etc.
    "o3",
    # Future models
    "gpt-5"
  ]

  @impl true
  def chat(messages, config) do
    with {:ok, validated_config} <- validate_config(config),
         {:ok, response} <- send_request(messages, validated_config) do
      parse_response(response)
    end
  end

  @impl true
  def validate_config(config) when is_map(config) do
    if !Map.has_key?(config, :api_key) or is_nil(config.api_key) or config.api_key == "" do
      {:error, "API key is required"}
    else
      model = Map.get(config, :model, @default_model)
      # Validate and correct model name
      validated_model = validate_model(model)

      # Optional: request timeout in ms (passed as receive_timeout to Finch). Default 60s.
      timeout = Map.get(config, :timeout, 60_000)

      validated = %{
        api_key: String.trim(config.api_key),
        model: validated_model,
        temperature: Map.get(config, :temperature, @default_temperature),
        max_tokens: Map.get(config, :max_tokens, @default_max_tokens),
        base_url: Map.get(config, :base_url, @default_base_url),
        timeout: timeout
      }

      {:ok, validated}
    end
  end

  @impl true
  def validate_config(_config), do: {:error, "Config must be a map"}

  # Validates model names
  defp validate_model(model) when is_binary(model) do
    model = String.trim(model)

    # Check if model starts with a valid prefix
    is_valid =
      Enum.any?(@valid_model_prefixes, fn prefix ->
        String.starts_with?(model, prefix)
      end)

    if is_valid do
      model
    else
      # Try to correct common mistakes for older models
      corrected =
        cond do
          String.contains?(model, "gpt-4-mini") ->
            "gpt-4o-mini"

          String.contains?(model, "gpt-4o") ->
            "gpt-4o-mini"

          true ->
            @default_model
        end

      Logger.warning("Invalid model '#{model}' corrected to '#{corrected}'")
      corrected
    end
  end

  defp validate_model(_), do: @default_model

  defp send_request(messages, config) do
    url = "#{config.base_url}/chat/completions"

    body = %{
      model: config.model,
      messages: messages,
      temperature: config.temperature,
      # Newer models (e.g. gpt-4o) require max_completion_tokens instead of max_tokens
      max_completion_tokens: config.max_tokens
    }

    api_key = config.api_key

    Logger.debug(
      "ChatGPT: Using API key length=#{String.length(api_key)}, starts with: #{String.slice(api_key, 0, 10)}"
    )

    headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]

    Logger.debug("ChatGPT: Sending request to #{url} with model #{config.model}")

    req_opts = [
      url: url,
      json: body,
      headers: headers,
      retry: false,
      receive_timeout: config.timeout
    ]

    case Req.post(req_opts) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %{status: 401, body: body}} ->
        Logger.error("ChatGPT API 401 error: #{inspect(body)}")
        {:error, :invalid_api_key}

      {:ok, %{status: 429, headers: headers, body: body}} ->
        error_message = extract_error_message(body)
        # Check for retry-after header (Req returns headers as a map with lowercase keys)
        retry_after =
          headers
          |> Map.get("retry-after")
          |> parse_retry_after()

        Logger.warning(
          "ChatGPT API rate limit (429): #{error_message}, retry after #{retry_after}s"
        )

        {:error, {:rate_limit_exceeded, retry_after}}

      {:ok, %{status: status, body: body}} ->
        error_message = extract_error_message(body)

        Logger.warning(
          "ChatGPT API error: status=#{status}, message=#{error_message}, body=#{inspect(body)}"
        )

        {:error, {:api_error, status, error_message}}

      {:error, %{reason: :timeout}} ->
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("ChatGPT API request failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_response(%{"choices" => [%{"message" => %{"content" => content}} | _]} = body) do
    usage = Map.get(body, "usage", %{})
    model = Map.get(body, "model", "unknown")
    total_tokens = Map.get(usage, "total_tokens", 0)

    response = %{
      content: content,
      model: model,
      token_count: total_tokens,
      usage: %{
        prompt_tokens: Map.get(usage, "prompt_tokens", 0),
        completion_tokens: Map.get(usage, "completion_tokens", 0),
        total_tokens: total_tokens
      }
    }

    {:ok, response}
  end

  defp parse_response(body) do
    Logger.error("Unexpected ChatGPT API response format: #{inspect(body)}")
    {:error, :invalid_response}
  end

  defp extract_error_message(%{"error" => %{"message" => message}}), do: message
  defp extract_error_message(%{"error" => error}) when is_binary(error), do: error
  defp extract_error_message(_), do: "Unknown error"

  defp parse_retry_after(nil), do: 60

  defp parse_retry_after(value) when is_list(value) do
    case List.first(value) do
      nil -> 60
      str when is_binary(str) -> parse_retry_after(str)
      _ -> 60
    end
  end

  defp parse_retry_after(value) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, _} -> seconds
      _ -> 60
    end
  end

  defp parse_retry_after(_), do: 60
end
