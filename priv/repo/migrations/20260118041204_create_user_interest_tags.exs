defmodule Langler.Repo.Migrations.CreateUserInterestTags do
  use Ecto.Migration

  def change do
    create table(:user_interest_tags) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :tag, :string, null: false
      add :language, :string, null: false, default: "spanish"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_interest_tags, [:user_id, :tag, :language])
    create index(:user_interest_tags, [:user_id])
  end
end
