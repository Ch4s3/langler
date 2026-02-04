defmodule Langler.Repo.Migrations.CreateDeckShares do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:deck_shares) do
      add :deck_id, references(:decks, on_delete: :delete_all), null: false
      add :shared_with_user_id, references(:users, on_delete: :delete_all), null: false
      add :permission, :string, default: "view", null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists unique_index(:deck_shares, [:deck_id, :shared_with_user_id])
    create_if_not_exists index(:deck_shares, [:shared_with_user_id])

    execute(
      """
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint
          WHERE conname = 'valid_permission'
          AND conrelid = 'deck_shares'::regclass
        ) THEN
          ALTER TABLE deck_shares ADD CONSTRAINT valid_permission
            CHECK (permission IN ('view', 'edit'));
        END IF;
      END $$;
      """,
      "ALTER TABLE deck_shares DROP CONSTRAINT IF EXISTS valid_permission"
    )
  end
end
