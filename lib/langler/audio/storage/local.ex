defmodule Langler.Audio.Storage.Local do
  @moduledoc """
  Local file system storage implementation for audio files.
  Stores files in priv/static/audio/{user_id}/{article_id}.mp3
  """

  @behaviour Langler.Audio.Storage

  @base_path "priv/static/audio"

  @impl true
  def store(user_id, article_id, audio_binary)
      when is_integer(user_id) and is_integer(article_id) and is_binary(audio_binary) do
    file_path = build_file_path(user_id, article_id)
    dir_path = Path.dirname(file_path)

    with :ok <- File.mkdir_p(dir_path),
         :ok <- File.write(file_path, audio_binary) do
      public_path = "/audio/#{user_id}/#{article_id}.wav"
      {:ok, public_path}
    else
      error -> {:error, error}
    end
  end

  @impl true
  def public_url(file_path) when is_binary(file_path) do
    file_path
  end

  @impl true
  def delete(file_path) when is_binary(file_path) do
    full_path = Path.join("priv/static", String.trim_leading(file_path, "/"))

    case File.rm(full_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  defp build_file_path(user_id, article_id) do
    # Store as WAV since Gemini TTS returns PCM audio
    Path.join([@base_path, "#{user_id}", "#{article_id}.wav"])
  end
end
