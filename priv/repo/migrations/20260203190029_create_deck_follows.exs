defmodule Langler.Repo.Migrations.CreateDeckFollows do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:deck_follows) do
      add :deck_id, references(:decks, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists unique_index(:deck_follows, [:deck_id, :user_id])
    create_if_not_exists index(:deck_follows, [:user_id])
    create_if_not_exists index(:deck_follows, [:deck_id])
  end
end
