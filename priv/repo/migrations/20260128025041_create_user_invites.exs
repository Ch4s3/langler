defmodule Langler.Repo.Migrations.CreateUserInvites do
  use Ecto.Migration

  def change do
    create table(:user_invites) do
      add :token, :string, null: false
      add :inviter_id, references(:users, on_delete: :delete_all), null: false
      add :invitee_id, references(:users, on_delete: :nilify_all), null: true
      add :email, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime, null: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_invites, [:token])
    create index(:user_invites, [:inviter_id])
    create index(:user_invites, [:invitee_id])
    create index(:user_invites, [:email])
    create index(:user_invites, [:expires_at])
  end
end
