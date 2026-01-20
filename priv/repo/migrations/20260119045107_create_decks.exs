defmodule Langler.Repo.Migrations.CreateDecks do
  use Ecto.Migration

  def change do
    create table(:decks) do
      add :name, :string, null: false
      add :is_default, :boolean, null: false, default: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:decks, [:user_id, :name])
    create index(:decks, [:user_id])
    # Partial unique index to ensure exactly one default deck per user
    create unique_index(:decks, [:user_id],
             where: "is_default = true",
             name: :decks_user_id_is_default_index
           )

    create table(:deck_words) do
      add :deck_id, references(:decks, on_delete: :delete_all), null: false
      add :word_id, references(:words, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:deck_words, [:deck_id, :word_id])
    create index(:deck_words, [:deck_id])
    create index(:deck_words, [:word_id])

    alter table(:user_preferences) do
      add :current_deck_id, references(:decks, on_delete: :nilify_all)
    end

    create index(:user_preferences, [:current_deck_id])
  end
end
