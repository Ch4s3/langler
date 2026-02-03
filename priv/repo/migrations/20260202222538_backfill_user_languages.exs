defmodule Langler.Repo.Migrations.BackfillUserLanguages do
  use Ecto.Migration

  def up do
    # For each user with preferences, create a user_languages row
    # based on their target_language (which has been converted to code)
    execute """
    INSERT INTO user_languages (user_id, language_code, is_active, current_deck_id, inserted_at, updated_at)
    SELECT
      up.user_id,
      up.target_language,
      true as is_active,
      up.current_deck_id,
      NOW(),
      NOW()
    FROM user_preferences up
    ON CONFLICT (user_id, language_code) DO NOTHING
    """
  end

  def down do
    # Clear user_languages table
    execute "DELETE FROM user_languages"
  end
end
