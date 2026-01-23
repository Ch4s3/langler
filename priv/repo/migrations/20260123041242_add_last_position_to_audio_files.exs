defmodule Langler.Repo.Migrations.AddLastPositionToAudioFiles do
  use Ecto.Migration

  def change do
    alter table(:audio_files) do
      add :last_position_seconds, :float, default: 0.0, null: false
    end
  end
end
