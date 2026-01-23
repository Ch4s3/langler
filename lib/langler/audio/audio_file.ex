defmodule Langler.Audio.AudioFile do
  @moduledoc """
  Schema for tracking generated audio files for articles.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "audio_files" do
    belongs_to :user, Langler.Accounts.User
    belongs_to :article, Langler.Content.Article
    field :status, :string, default: "pending"
    field :file_path, :string
    field :file_size, :integer
    field :duration_seconds, :float
    field :last_position_seconds, :float, default: 0.0
    field :error_message, :string

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @doc false
  def changeset(audio_file, attrs) do
    audio_file
    |> cast(attrs, [
      :user_id,
      :article_id,
      :status,
      :file_path,
      :file_size,
      :duration_seconds,
      :last_position_seconds,
      :error_message
    ])
    |> validate_required([:user_id, :article_id, :status])
    |> validate_inclusion(:status, ["pending", "ready", "failed"])
    |> unique_constraint([:user_id, :article_id])
  end
end
