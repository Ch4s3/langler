defmodule Langler.Repo.Migrations.CreateCustomCards do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:custom_cards) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :front, :text, null: false
      add :back, :text, null: false
      add :language, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:custom_cards, [:user_id])
  end
end
