defmodule Langler.Repo.Migrations.ExtendFsrsItemsForCustomCards do
  use Ecto.Migration

  def change do
    # Add column and FK only if missing (add_if_not_exists with references can duplicate FK)
    execute(
      """
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_name = 'fsrs_items' AND column_name = 'custom_card_id'
        ) THEN
          ALTER TABLE fsrs_items
          ADD COLUMN custom_card_id bigint REFERENCES custom_cards(id) ON DELETE CASCADE;
        END IF;
      END $$;
      """,
      "ALTER TABLE fsrs_items DROP COLUMN IF EXISTS custom_card_id"
    )

    # Drop the existing unique constraint on user_id + word_id (if present)
    drop_if_exists unique_index(:fsrs_items, [:user_id, :word_id])

    # Create partial unique indexes
    create_if_not_exists unique_index(:fsrs_items, [:user_id, :word_id],
                           where: "word_id IS NOT NULL",
                           name: :fsrs_items_user_id_word_id_index
                         )

    create_if_not_exists unique_index(:fsrs_items, [:user_id, :custom_card_id],
                           where: "custom_card_id IS NOT NULL",
                           name: :fsrs_items_user_id_custom_card_id_index
                         )

    # Add check constraint to ensure exactly one of word_id or custom_card_id is set
    execute(
      """
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint
          WHERE conname = 'word_or_custom_card'
          AND conrelid = 'fsrs_items'::regclass
        ) THEN
          ALTER TABLE fsrs_items ADD CONSTRAINT word_or_custom_card
            CHECK (
              (word_id IS NOT NULL AND custom_card_id IS NULL)
              OR (word_id IS NULL AND custom_card_id IS NOT NULL)
            );
        END IF;
      END $$;
      """,
      "ALTER TABLE fsrs_items DROP CONSTRAINT IF EXISTS word_or_custom_card"
    )

    create_if_not_exists index(:fsrs_items, [:custom_card_id])
  end
end
