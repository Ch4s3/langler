defmodule Langler.Repo.Migrations.AddAdminAndInvitesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_admin, :boolean, default: false, null: false
      add :invites_remaining, :integer, default: 3, null: false
    end
  end
end
