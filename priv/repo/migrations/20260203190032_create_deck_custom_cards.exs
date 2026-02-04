defmodule Langler.Repo.Migrations.CreateDeckCustomCards do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:deck_custom_cards) do
      add :deck_id, references(:decks, on_delete: :delete_all), null: false
      add :custom_card_id, references(:custom_cards, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists unique_index(:deck_custom_cards, [:deck_id, :custom_card_id])
    create_if_not_exists index(:deck_custom_cards, [:custom_card_id])
  end
end
