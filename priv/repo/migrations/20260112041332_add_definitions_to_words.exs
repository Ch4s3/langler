defmodule Langler.Repo.Migrations.AddDefinitionsToWords do
  use Ecto.Migration

  def change do
    alter table(:words) do
      add :definitions, {:array, :text}, default: []
    end

    execute("UPDATE words SET definitions = ARRAY[]::text[] WHERE definitions IS NULL", "")
  end
end
