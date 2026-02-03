defmodule Langler.Repo.Migrations.CreateUserLanguages do
  use Ecto.Migration

  def change do
    create table(:user_languages) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :language_code, :string, null: false
      add :is_active, :boolean, default: false, null: false
      add :current_deck_id, references(:decks, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_languages, [:user_id, :language_code])

    create unique_index(:user_languages, [:user_id],
             where: "is_active = true",
             name: :user_languages_one_active_per_user
           )

    create index(:user_languages, [:current_deck_id])
  end
end
