defmodule Langler.Repo.Migrations.CreateAudioFiles do
  use Ecto.Migration

  def change do
    create table(:audio_files) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :article_id, references(:articles, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :file_path, :string
      add :file_size, :integer
      add :duration_seconds, :float
      add :error_message, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:audio_files, [:user_id, :article_id])
    create index(:audio_files, [:status])
  end
end
