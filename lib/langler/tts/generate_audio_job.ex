defmodule Langler.TTS.GenerateAudioJob do
  @moduledoc """
  Oban worker for generating audio files asynchronously.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Langler.TTS.Service

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "article_id" => article_id}}) do
    case Service.generate_audio(user_id, article_id) do
      {:ok, _audio_file} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
