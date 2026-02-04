defmodule Langler.Repo.Migrations.AddVisibilityDescriptionLanguageToDecks do
  use Ecto.Migration

  def change do
    alter table(:decks) do
      add :visibility, :string, default: "private", null: false
      add :description, :text
      add :language, :string
    end

    create constraint(:decks, :valid_visibility,
             check: "visibility IN ('private', 'shared', 'public')"
           )
  end
end
