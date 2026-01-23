defmodule Langler.Audio do
  @moduledoc """
  Context for managing audio files.
  """

  alias Langler.Audio.AudioFile
  alias Langler.Repo

  @doc """
  Gets or creates an audio file record for a user and article.
  Returns existing record if found, otherwise creates a pending record.
  """
  @spec get_or_create_audio_file(integer(), integer()) ::
          {:ok, AudioFile.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_audio_file(user_id, article_id)
      when is_integer(user_id) and is_integer(article_id) do
    case Repo.get_by(AudioFile, user_id: user_id, article_id: article_id) do
      nil ->
        %AudioFile{}
        |> AudioFile.changeset(%{
          user_id: user_id,
          article_id: article_id,
          status: "pending"
        })
        |> Repo.insert()

      audio_file ->
        {:ok, audio_file}
    end
  end

  @doc """
  Gets an audio file for a user and article.
  """
  @spec get_audio_file(integer(), integer()) :: AudioFile.t() | nil
  def get_audio_file(user_id, article_id)
      when is_integer(user_id) and is_integer(article_id) do
    Repo.get_by(AudioFile, user_id: user_id, article_id: article_id)
  end

  @doc """
  Marks an audio file as ready with file path and metadata.
  """
  @spec mark_ready(integer(), integer(), String.t(), integer(), float()) ::
          {:ok, AudioFile.t()} | {:error, Ecto.Changeset.t()}
  def mark_ready(user_id, article_id, file_path, file_size, duration_seconds)
      when is_integer(user_id) and is_integer(article_id) and is_binary(file_path) do
    case get_audio_file(user_id, article_id) do
      nil ->
        {:error, :not_found}

      audio_file ->
        audio_file
        |> AudioFile.changeset(%{
          status: "ready",
          file_path: file_path,
          file_size: file_size,
          duration_seconds: duration_seconds,
          error_message: nil
        })
        |> Repo.update()
    end
  end

  @doc """
  Marks an audio file as failed with an error message.
  """
  @spec mark_failed(integer(), integer(), String.t()) ::
          {:ok, AudioFile.t()} | {:error, Ecto.Changeset.t()}
  def mark_failed(user_id, article_id, error_message)
      when is_integer(user_id) and is_integer(article_id) and is_binary(error_message) do
    case get_audio_file(user_id, article_id) do
      nil ->
        {:error, :not_found}

      audio_file ->
        audio_file
        |> AudioFile.changeset(%{
          status: "failed",
          error_message: error_message
        })
        |> Repo.update()
    end
  end

  @doc """
  Updates the saved listening position for a user's audio file.
  """
  @spec update_listening_position(integer(), integer(), number()) ::
          {:ok, AudioFile.t()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  def update_listening_position(user_id, article_id, position_seconds)
      when is_integer(user_id) and is_integer(article_id) and is_number(position_seconds) do
    case get_audio_file(user_id, article_id) do
      nil ->
        {:error, :not_found}

      audio_file ->
        audio_file
        |> AudioFile.changeset(%{last_position_seconds: position_seconds})
        |> Repo.update()
    end
  end
end
