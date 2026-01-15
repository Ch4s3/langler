defmodule Langler.Repo.Migrations.AddFrequencyToWords do
  use Ecto.Migration

  def change do
    alter table(:words) do
      add :frequency_rank, :integer
      add :cefr_level, :string
    end

    create index(:words, [:frequency_rank])
    create index(:words, [:cefr_level])
  end
end
