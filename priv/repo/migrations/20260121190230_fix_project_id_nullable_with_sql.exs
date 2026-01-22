defmodule Langler.Repo.Migrations.FixProjectIdNullableWithSql do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE user_tts_configs ALTER COLUMN project_id DROP NOT NULL"
  end

  def down do
    execute "ALTER TABLE user_tts_configs ALTER COLUMN project_id SET NOT NULL"
  end
end
