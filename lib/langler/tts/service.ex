defmodule Langler.TTS.Service do
  @moduledoc """
  Service for orchestrating text-to-speech generation.
  """

  alias Langler.Accounts.TtsConfig
  alias Langler.Audio
  alias Langler.Audio.Storage
  alias Langler.Chat.Encryption
  alias Langler.Content
  alias Langler.TTS.Adapters.VertexAI

  @doc """
  Generates or retrieves audio for an article.
  Returns the audio file record.
  """
  @spec generate_audio(integer(), integer()) ::
          {:ok, Langler.Audio.AudioFile.t()} | {:error, term()}
  def generate_audio(user_id, article_id) when is_integer(user_id) and is_integer(article_id) do
    # Get or create audio file record
    case Audio.get_or_create_audio_file(user_id, article_id) do
      {:ok, audio_file} ->
        case audio_file.status do
          "ready" ->
            {:ok, audio_file}

          "pending" ->
            # When called from a job, generate the audio even if status is pending
            # (the pending status was set when the job was enqueued)
            do_generate_audio(user_id, article_id, audio_file)

          "failed" ->
            # Retry generation
            do_generate_audio(user_id, article_id, audio_file)

          _ ->
            do_generate_audio(user_id, article_id, audio_file)
        end

      error ->
        error
    end
  end

  defp do_generate_audio(user_id, article_id, _audio_file) do
    with {:ok, article} <- get_article(article_id),
         {:ok, config} <- get_tts_config(user_id, article.language),
         {:ok, audio_binary} <- generate_audio_chunked(article.content, config),
         {:ok, file_path} <- store_audio(user_id, article_id, audio_binary),
         {:ok, _} <-
           Audio.mark_ready(
             user_id,
             article_id,
             file_path,
             byte_size(audio_binary),
             estimate_duration(audio_binary)
           ) do
      audio_file = Audio.get_audio_file(user_id, article_id)

      # Notify any LiveViews waiting for this audio
      Phoenix.PubSub.broadcast(
        Langler.PubSub,
        "audio:user:#{user_id}:article:#{article_id}",
        {:audio_ready, audio_file}
      )

      {:ok, audio_file}
    else
      {:error, reason} ->
        # Mark as failed with detailed error message
        require Logger
        error_msg = inspect(reason)

        Logger.error(
          "TTS generation failed for user_id=#{user_id}, article_id=#{article_id}: #{error_msg}"
        )

        _ = Audio.mark_failed(user_id, article_id, error_msg)
        {:error, reason}
    end
  end

  # Chunk text into pieces under 3500 bytes (safety margin for 4000 byte limit)
  # and generate audio for each chunk, then concatenate
  defp generate_audio_chunked(text, config) do
    require Logger
    text_bytes = byte_size(text)

    if text_bytes <= 3500 do
      # Small enough, generate directly
      case call_adapter(text, config) do
        {:ok, audio_data} -> {:ok, audio_data.audio_binary}
        error -> error
      end
    else
      # Need to chunk
      Logger.info("TTS: Article is #{text_bytes} bytes, chunking into smaller pieces")
      chunks = chunk_text(text, 3500)

      # Verify we captured all text
      total_chunked_bytes = Enum.sum(Enum.map(chunks, &byte_size/1))

      if total_chunked_bytes != text_bytes do
        Logger.warning(
          "TTS: Chunking mismatch! Original: #{text_bytes} bytes, Chunked: #{total_chunked_bytes} bytes, Missing: #{text_bytes - total_chunked_bytes} bytes"
        )
      end

      Logger.info(
        "TTS: Split into #{length(chunks)} chunks (total: #{total_chunked_bytes} bytes)"
      )

      # Generate audio for each chunk
      chunk_results = generate_chunk_audio(chunks, config)

      # Check for errors and concatenate
      process_chunk_results(chunk_results)
    end
  end

  # Split text into chunks, trying to break at sentence boundaries
  # Preserves original punctuation and spacing
  defp chunk_text(text, max_bytes) do
    # Use Regex.scan with return: :index to get byte positions
    # Returns: [[{full_match_start, full_match_len}, {capture1_start, capture1_len},
    #            {capture2_start, capture2_len}], ...]
    sentence_matches = Regex.scan(~r/(.+?)([.!?])\s+/, text, return: :index)

    # Reconstruct sentences from matches, preserving original punctuation
    # Convert byte positions to character positions for String.slice
    sentences =
      Enum.map(sentence_matches, fn [full_match, sentence_match, punct_match] ->
        {_full_start, _full_len} = full_match
        {s_start, s_length} = sentence_match
        {p_start, p_length} = punct_match
        # Convert byte positions to character positions
        s_char_start = String.length(binary_part(text, 0, s_start))
        s_char_len = String.length(binary_part(text, s_start, s_length))
        p_char_start = String.length(binary_part(text, 0, p_start))
        p_char_len = String.length(binary_part(text, p_start, p_length))
        # Extract using String.slice which handles UTF-8 correctly
        sentence = String.slice(text, s_char_start, s_char_len)
        punct = String.slice(text, p_char_start, p_char_len)
        sentence <> punct <> " "
      end)

    # Find the character position where the last match ends
    last_match_char_end =
      if sentence_matches != [] do
        [{start, length} | _] = List.last(sentence_matches)
        # Convert byte position to character position
        char_start = String.length(binary_part(text, 0, start))
        match_text = binary_part(text, start, length)
        char_len = String.length(match_text)
        char_start + char_len
      else
        0
      end

    # Add any remaining text that doesn't end with punctuation+space
    sentences =
      if last_match_char_end < String.length(text) do
        remaining = String.slice(text, last_match_char_end..-1)

        if String.trim(remaining) != "" do
          sentences ++ [remaining]
        else
          sentences
        end
      else
        sentences
      end

    # Handle case where no matches (text has no sentence-ending punctuation)
    sentences = if Enum.empty?(sentences), do: [text], else: sentences

    # Now chunk the sentences respecting max_bytes
    chunk_sentences(sentences, max_bytes)
  end

  defp generate_chunk_audio(chunks, config) do
    require Logger

    Enum.with_index(chunks, 1)
    |> Enum.map(fn {chunk, index} ->
      Logger.info(
        "TTS: Generating audio for chunk #{index}/#{length(chunks)} (#{byte_size(chunk)} bytes)"
      )

      call_adapter(chunk, config)
    end)
  end

  defp process_chunk_results(chunk_results) do
    require Logger

    case Enum.find(chunk_results, fn result -> match?({:error, _}, result) end) do
      {:error, reason} = error ->
        Logger.error("TTS: Failed to generate audio for a chunk: #{inspect(reason)}")
        error

      nil ->
        # All chunks succeeded, extract audio binaries
        audio_chunks =
          Enum.map(chunk_results, fn {:ok, audio_data} -> audio_data.audio_binary end)

        # Concatenate WAV files
        case concatenate_wav_files(audio_chunks) do
          {:ok, combined_audio} ->
            chunk_count = length(audio_chunks)
            Logger.info("TTS: Successfully concatenated #{chunk_count} audio chunks")
            {:ok, combined_audio}

          {:error, _reason} = error ->
            Logger.error("TTS: Failed to concatenate audio chunks: #{inspect(error)}")
            error
        end
    end
  end

  defp chunk_sentences(sentences, max_bytes) do
    sentences
    |> Enum.reduce([], fn sentence, acc ->
      add_sentence_to_chunks(sentence, acc, max_bytes)
    end)
    |> Enum.reverse()
    |> Enum.filter(fn chunk -> String.trim(chunk) != "" end)
  end

  defp add_sentence_to_chunks(sentence, [], _max_bytes) do
    [sentence]
  end

  defp add_sentence_to_chunks(sentence, [current_chunk | rest], max_bytes) do
    current_size = byte_size(current_chunk)
    sentence_size = byte_size(sentence)

    if current_size + sentence_size <= max_bytes do
      [current_chunk <> sentence | rest]
    else
      [sentence, current_chunk | rest]
    end
  end

  # Concatenate multiple WAV files into one
  # All WAV files should have the same format (sample rate, channels, bits per sample)
  defp concatenate_wav_files([single_file]) do
    {:ok, single_file}
  end

  defp concatenate_wav_files(wav_files) when is_list(wav_files) and length(wav_files) > 1 do
    require Logger

    # Extract PCM data from each WAV file (skip headers)
    pcm_chunks =
      Enum.map(wav_files, fn wav_data ->
        # WAV header is 44 bytes (standard) or 36 + fmt chunk size
        # Find the "data" chunk
        case find_data_chunk(wav_data) do
          {:ok, pcm_data, sample_rate, channels, bits_per_sample} ->
            {:ok, pcm_data, sample_rate, channels, bits_per_sample}

          error ->
            error
        end
      end)

    # Check for errors
    case Enum.find(pcm_chunks, fn result -> match?({:error, _}, result) end) do
      {:error, reason} = error ->
        Logger.error("TTS: Failed to extract PCM data from WAV: #{inspect(reason)}")
        error

      nil ->
        combine_pcm_chunks(pcm_chunks)
    end
  end

  defp combine_pcm_chunks(pcm_chunks) do
    [{:ok, _first_pcm, sample_rate, channels, bits_per_sample} | _] = pcm_chunks

    # Verify all chunks have the same format
    if all_chunks_same_format?(pcm_chunks, sample_rate, channels, bits_per_sample) do
      # Concatenate all PCM data
      combined_pcm =
        Enum.map_join(pcm_chunks, "", fn {:ok, pcm, _, _, _} -> pcm end)

      # Create new WAV file with combined PCM data
      wav_audio = pcm_to_wav(combined_pcm, sample_rate, channels, bits_per_sample)
      {:ok, wav_audio}
    else
      {:error, :incompatible_audio_formats}
    end
  end

  defp all_chunks_same_format?(pcm_chunks, sample_rate, channels, bits_per_sample) do
    Enum.all?(pcm_chunks, fn {:ok, _, sr, ch, bps} ->
      sr == sample_rate and ch == channels and bps == bits_per_sample
    end)
  end

  # Find the "data" chunk in a WAV file and extract PCM data
  defp find_data_chunk(<<
         "RIFF"::binary,
         _file_size::little-32,
         "WAVE"::binary,
         rest::binary
       >>) do
    parse_wav_chunks(rest)
  end

  defp find_data_chunk(_), do: {:error, :invalid_wav_format}

  defp parse_wav_chunks(<<
         "fmt "::binary,
         fmt_size::little-32,
         fmt_data::binary-size(fmt_size),
         rest::binary
       >>) do
    <<
      audio_format::little-16,
      channels::little-16,
      sample_rate::little-32,
      _byte_rate::little-32,
      _block_align::little-16,
      bits_per_sample::little-16,
      _extra::binary
    >> = fmt_data

    if audio_format == 1 do
      # PCM format, now find data chunk
      find_data_chunk_in_rest(rest, sample_rate, channels, bits_per_sample)
    else
      {:error, :unsupported_audio_format}
    end
  end

  defp parse_wav_chunks(<<_chunk_id::binary-size(4), chunk_size::little-32, rest::binary>>) do
    # Skip this chunk and continue - ensure we don't read past the end
    if byte_size(rest) >= chunk_size do
      <<_chunk_data::binary-size(^chunk_size), next_rest::binary>> = rest
      parse_wav_chunks(next_rest)
    else
      {:error, :invalid_chunk_size}
    end
  end

  defp parse_wav_chunks(_), do: {:error, :no_fmt_chunk}

  defp find_data_chunk_in_rest(
         <<
           "data"::binary,
           data_size::little-32,
           pcm_data::binary-size(data_size),
           _rest::binary
         >>,
         sample_rate,
         channels,
         bits_per_sample
       ) do
    {:ok, pcm_data, sample_rate, channels, bits_per_sample}
  end

  defp find_data_chunk_in_rest(
         <<
           _chunk_id::binary-size(4),
           chunk_size::little-32,
           rest::binary
         >>,
         sample_rate,
         channels,
         bits_per_sample
       ) do
    # Skip this chunk - ensure we don't read past the end
    if byte_size(rest) >= chunk_size do
      <<_chunk_data::binary-size(^chunk_size), next_rest::binary>> = rest
      find_data_chunk_in_rest(next_rest, sample_rate, channels, bits_per_sample)
    else
      {:error, :invalid_chunk_size}
    end
  end

  defp find_data_chunk_in_rest(_, _, _, _), do: {:error, :no_data_chunk}

  # Convert PCM to WAV format (same as in VertexAI adapter)
  defp pcm_to_wav(pcm_data, sample_rate, channels, bits_per_sample) do
    data_size = byte_size(pcm_data)
    file_size = 36 + data_size

    header = <<
      "RIFF"::binary,
      file_size::little-32,
      "WAVE"::binary,
      "fmt "::binary,
      16::little-32,
      1::little-16,
      channels::little-16,
      sample_rate::little-32,
      sample_rate * channels * div(bits_per_sample, 8)::little-32,
      channels * div(bits_per_sample, 8)::little-16,
      bits_per_sample::little-16,
      "data"::binary,
      data_size::little-32
    >>

    header <> pcm_data
  end

  defp get_tts_config(user_id, article_language) do
    case TtsConfig.get_default_config(user_id) do
      nil ->
        {:error, :no_tts_config}

      config ->
        case Encryption.decrypt_message(user_id, config.encrypted_api_key) do
          {:ok, api_key} ->
            # Auto-select voice based on article language if not configured
            voice_name = config.voice_name || Langler.Languages.tts_voice(article_language)

            {:ok,
             %{
               api_key: api_key,
               voice_name: voice_name
             }}

          error ->
            error
        end
    end
  end

  defp get_article(article_id) do
    article = Content.get_article!(article_id)
    {:ok, article}
  rescue
    Ecto.NoResultsError -> {:error, :article_not_found}
  end

  defp call_adapter(text, config) do
    VertexAI.generate_audio(text, config)
  end

  defp store_audio(user_id, article_id, audio_binary) do
    Storage.Local.store(user_id, article_id, audio_binary)
  end

  # Rough estimate: MP3 files are typically ~1MB per minute at 128kbps
  # This is a very rough estimate, actual duration would require parsing the MP3
  defp estimate_duration(audio_binary) when is_binary(audio_binary) do
    # Assume ~1MB per minute, so bytes / (1024 * 1024) * 60
    size_mb = byte_size(audio_binary) / (1024 * 1024)
    seconds = size_mb * 60
    Float.round(seconds, 1)
  end
end
