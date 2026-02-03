defmodule Langler.Repo.Migrations.AddOnboardingAndUiLocale do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :onboarding_completed_at, :utc_datetime
    end

    alter table(:user_preferences) do
      add :ui_locale, :string, default: "en", null: false
    end
  end
end
