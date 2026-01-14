defmodule Langler.Repo.Migrations.AddConjugationsToWords do
  use Ecto.Migration

  def change do
    alter table(:words) do
      add :conjugations, :jsonb
    end
  end
end
