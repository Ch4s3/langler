defmodule Langler.Repo.Migrations.AddTypeAndTranslationToWords do
  use Ecto.Migration

  def change do
    alter table(:words) do
      add :type, :string, default: "word", null: false
      add :translation, :text
    end

    create index(:words, [:type])
  end
end
