defmodule Langler.Repo.Migrations.MakeProjectIdNullableInUserTtsConfigs do
  use Ecto.Migration

  def up do
    alter table(:user_tts_configs) do
      modify :project_id, :string, null: true
    end
  end

  def down do
    alter table(:user_tts_configs) do
      modify :project_id, :string, null: false
    end
  end
end
