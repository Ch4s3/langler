defmodule Langler.Repo.Migrations.AddUseLlmForDefinitionsToUserPreferences do
  use Ecto.Migration

  def change do
    alter table(:user_preferences) do
      add :use_llm_for_definitions, :boolean, default: false, null: false
    end
  end
end
