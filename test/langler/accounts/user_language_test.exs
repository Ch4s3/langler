defmodule Langler.Accounts.UserLanguageTest do
  use Langler.DataCase

  alias Langler.Accounts

  describe "user_languages" do
    import Langler.AccountsFixtures

    test "enable_language/2 creates a new language for user" do
      user = onboarded_user_fixture()

      assert {:ok, user_lang} = Accounts.enable_language(user.id, "fr")
      assert user_lang.language_code == "fr"
      assert user_lang.is_active == false
    end

    test "enable_language/2 normalizes language codes" do
      user = onboarded_user_fixture()

      assert {:ok, user_lang} = Accounts.enable_language(user.id, "pt_BR")
      assert user_lang.language_code == "pt-BR"
    end

    test "enable_language/2 rejects invalid language codes" do
      user = onboarded_user_fixture()

      assert {:error, changeset} = Accounts.enable_language(user.id, "invalid")
      assert "is not a supported language code" in errors_on(changeset).language_code
    end

    test "enable_language/2 is idempotent when language already enabled (e.g. onboarding for existing user)" do
      user = onboarded_user_fixture()

      assert {:ok, first} = Accounts.enable_language(user.id, "fr")
      assert {:ok, second} = Accounts.enable_language(user.id, "fr")
      assert first.id == second.id
    end

    test "set_active_language/2 sets the active language" do
      user = onboarded_user_fixture()

      # Enable another language
      {:ok, _} = Accounts.enable_language(user.id, "fr")

      # Set it as active
      assert {:ok, user_lang} = Accounts.set_active_language(user.id, "fr")
      assert user_lang.is_active == true

      # Verify it's the active one
      assert "fr" = Accounts.get_active_language(user.id)
    end

    test "set_active_language/2 deactivates previous active language" do
      user = user_fixture()

      # User already has "es" active from fixture
      # Enable and activate another language
      {:ok, _} = Accounts.enable_language(user.id, "fr")
      {:ok, _} = Accounts.set_active_language(user.id, "fr")

      # Verify only one is active
      active_languages =
        Accounts.list_enabled_languages(user.id)
        |> Enum.filter(& &1.is_active)

      assert length(active_languages) == 1
      assert hd(active_languages).language_code == "fr"
    end

    test "disable_language/2 removes a language" do
      user = onboarded_user_fixture()

      # User already has "es" enabled, add another
      {:ok, _} = Accounts.enable_language(user.id, "fr")

      # Disable one
      assert {:ok, _} = Accounts.disable_language(user.id, "fr")

      # Verify only "es" remains
      languages = Accounts.list_enabled_languages(user.id)
      assert length(languages) == 1
      assert hd(languages).language_code == "es"
    end

    test "disable_language/2 prevents removing last language" do
      user = user_fixture()

      # User already has "es" enabled from fixture
      # Try to disable the only language
      assert {:error, :cannot_disable_last_language} = Accounts.disable_language(user.id, "es")
    end

    test "list_enabled_languages/1 returns all languages for user" do
      user = onboarded_user_fixture()

      # User already has "es" from fixture, add more
      {:ok, _} = Accounts.enable_language(user.id, "fr")
      {:ok, _} = Accounts.enable_language(user.id, "it")

      languages = Accounts.list_enabled_languages(user.id)
      # es (from fixture) + fr + it
      assert length(languages) == 3
      codes = Enum.map(languages, & &1.language_code)
      assert "es" in codes
      assert "fr" in codes
      assert "it" in codes
    end

    test "get_active_language/1 falls back to user_preferences during rollout" do
      user = user_fixture()

      # Set preference but don't create user_languages yet
      {:ok, _} = Accounts.upsert_user_preference(user, %{target_language: "es"})

      # Should fall back to preference
      assert "es" = Accounts.get_active_language(user.id)
    end
  end

  describe "onboarding" do
    import Langler.AccountsFixtures

    test "complete_onboarding/1 sets onboarding_completed_at" do
      user = unonboarded_user_fixture()

      assert is_nil(user.onboarding_completed_at)
      assert {:ok, updated_user} = Accounts.complete_onboarding(user)
      assert not is_nil(updated_user.onboarding_completed_at)
    end

    test "onboarding_completed?/1 returns correct status" do
      user = unonboarded_user_fixture()

      refute Accounts.onboarding_completed?(user)

      {:ok, updated_user} = Accounts.complete_onboarding(user)

      assert Accounts.onboarding_completed?(updated_user)
    end
  end
end
