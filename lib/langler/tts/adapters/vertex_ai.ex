defmodule Langler.TTS.Adapters.VertexAI do
  @moduledoc """
  Google Vertex AI adapter for text-to-speech using Gemini-TTS models.
  """

  @behaviour Langler.TTS.Adapter

  require Logger

  @default_model "gemini-2.5-flash-preview-tts"
  @default_voice "Kore"

  @impl true
  def generate_audio(text, config) when is_binary(text) and is_map(config) do
    with {:ok, validated_config} <- validate_config(config),
         {:ok, response} <- send_request(text, validated_config) do
      parse_response(response, text)
    end
  end

  defp validate_config(config) do
    with :ok <- validate_required_field(config, :api_key, "API key is required") do
      validated = %{
        api_key: String.trim(config.api_key),
        model: Map.get(config, :model, @default_model),
        voice: Map.get(config, :voice_name, @default_voice)
      }

      {:ok, validated}
    end
  end

  defp validate_required_field(config, field, error_message) do
    value = Map.get(config, field)

    if is_nil(value) or value == "" do
      {:error, error_message}
    else
      :ok
    end
  end

  defp send_request(text, config) do
    # Use Generative AI API endpoint which accepts API keys
    # This endpoint supports Gemini-TTS models and accepts API key authentication
    url =
      "https://generativelanguage.googleapis.com/v1beta/models/#{config.model}:generateContent"

    headers = [
      {"X-goog-api-key", config.api_key},
      {"content-type", "application/json"}
    ]

    # Gemini-TTS request format
    # Note: According to docs, system instructions must be embedded in text inputs
    # The responseModalities: ["AUDIO"] should be sufficient, but we ensure
    # the text is treated as a transcript to be spoken
    voice_config = %{
      voiceConfig: %{
        prebuiltVoiceConfig: %{
          voiceName: config.voice
        }
      }
    }

    # Ensure we only request audio, not text
    # The text in contents is the transcript to be spoken
    body = %{
      contents: [
        %{
          parts: [
            %{
              text: text
            }
          ]
        }
      ],
      generationConfig: %{
        # Only request audio output, explicitly exclude text
        responseModalities: ["AUDIO"],
        speechConfig: voice_config
      }
    }

    Logger.debug("VertexAI TTS request body: #{inspect(body, pretty: true)}")

    Logger.debug("VertexAI TTS: Sending request to #{url}")

    Logger.info(
      "VertexAI TTS: Generating audio for text length #{String.length(text)} characters"
    )

    case Req.post(
           url: url,
           json: body,
           headers: headers,
           retry: false,
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %{status: 401, body: body}} ->
        Logger.error("VertexAI TTS API 401 error: #{inspect(body)}")
        {:error, :invalid_api_key}

      {:ok, %{status: status, body: body}} ->
        error_message = extract_error_message(body)
        Logger.warning("VertexAI TTS API error: status=#{status}, message=#{error_message}")
        Logger.debug("Full error response: #{inspect(body)}")
        {:error, {:api_error, status, error_message}}

      {:error, %{reason: :timeout}} ->
        Logger.error(
          "VertexAI TTS API request timed out. The article may be too long or the API is slow."
        )

        {:error, :timeout}

      {:error, reason} ->
        Logger.error("VertexAI TTS API request failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_response(response_body, original_text) do
    with {:ok, parts} <- extract_parts(response_body),
         {:ok, audio_data, sample_rate} <- find_audio_data(parts),
         {:ok, audio_binary} <- decode_audio(audio_data, sample_rate) do
      metadata = %{
        model: Map.get(response_body, "model", "unknown"),
        voice: "default"
      }

      {:ok,
       %{
         audio_binary: audio_binary,
         transcript: original_text,
         metadata: metadata
       }}
    end
  end

  defp extract_parts(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]}),
    do: {:ok, parts}

  defp extract_parts(_) do
    Logger.error("Unexpected VertexAI TTS response format")
    {:error, :invalid_response}
  end

  defp find_audio_data(parts) do
    # Gemini TTS returns PCM audio data (audio/L16;codec=pcm;rate=24000)
    # Look for inlineData with any audio mimeType
    audio_part =
      Enum.find(parts, fn part ->
        case part do
          %{"inlineData" => %{"mimeType" => mime_type}} when is_binary(mime_type) ->
            String.starts_with?(mime_type, "audio/")

          _ ->
            false
        end
      end)

    case audio_part do
      %{"inlineData" => %{"data" => audio_data, "mimeType" => mime_type}} ->
        # Extract sample rate from mimeType if present (e.g., "audio/L16;codec=pcm;rate=24000")
        sample_rate = extract_sample_rate(mime_type)
        {:ok, audio_data, sample_rate}

      %{"inlineData" => %{"data" => audio_data}} ->
        # Default to 24kHz if not specified
        {:ok, audio_data, 24_000}

      _ ->
        {:error, :no_audio_data}
    end
  end

  defp extract_sample_rate(mime_type) when is_binary(mime_type) do
    case Regex.run(~r/rate=(\d+)/, mime_type) do
      [_, rate_str] ->
        case Integer.parse(rate_str) do
          {rate, _} -> rate
          _ -> 24_000
        end

      _ ->
        24_000
    end
  end

  defp extract_sample_rate(_), do: 24_000

  defp decode_audio(audio_data, sample_rate) do
    # Gemini TTS returns PCM audio (typically 24kHz, mono, 16-bit) as base64
    # Convert PCM to WAV format (PCM with WAV header) for browser compatibility
    case Base.decode64(audio_data) do
      {:ok, pcm_audio} ->
        wav_audio = pcm_to_wav(pcm_audio, sample_rate, 1, 16)
        {:ok, wav_audio}

      :error ->
        {:error, :invalid_audio_data}
    end
  end

  # Convert PCM to WAV format by adding WAV header
  # Parameters: pcm_data, sample_rate (Hz), channels (1=mono, 2=stereo), bits_per_sample (16)
  defp pcm_to_wav(pcm_data, sample_rate, channels, bits_per_sample) do
    data_size = byte_size(pcm_data)
    file_size = 36 + data_size

    # WAV header
    header = <<
      # RIFF header
      "RIFF"::binary,
      file_size::little-32,
      "WAVE"::binary,
      # fmt chunk
      "fmt "::binary,
      16::little-32,
      # Audio format (1 = PCM)
      1::little-16,
      channels::little-16,
      sample_rate::little-32,
      # Byte rate
      sample_rate * channels * div(bits_per_sample, 8)::little-32,
      # Block align
      channels * div(bits_per_sample, 8)::little-16,
      bits_per_sample::little-16,
      # data chunk
      "data"::binary,
      data_size::little-32
    >>

    header <> pcm_data
  end

  defp extract_error_message(%{"error" => %{"message" => message}}), do: message
  defp extract_error_message(%{"error" => error}) when is_binary(error), do: error
  defp extract_error_message(_), do: "Unknown error"
end
