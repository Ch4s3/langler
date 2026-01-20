defmodule Langler.Repo.Migrations.AddArticleUsersUserIndexes do
  use Ecto.Migration

  @doc """
  Adds indexes on article_users for faster user-based filtering.

  The main articles listing query filters by (user_id, status) but only a
  composite unique index on (article_id, user_id) exists. Adding these indexes
  speeds up:
  - Filtering articles by user_id
  - Filtering articles by user_id + status (most common case)
  """
  def change do
    # Index for user_id alone - used when fetching all articles for a user
    create index(:article_users, [:user_id])

    # Composite index for (user_id, status) - covers the main listing filter
    create index(:article_users, [:user_id, :status])
  end
end
