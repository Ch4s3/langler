defmodule Langler.Chat.SessionTest do
  use Langler.DataCase, async: true

  import Langler.AccountsFixtures

  alias Langler.Accounts.LlmConfig
  alias Langler.Chat.{ChatMessage, ChatSession, Session}
  alias Langler.Repo

  defp create_default_config(user) do
    LlmConfig.create_config(user, %{
      provider_name: "openai",
      api_key: "secret-key-1234",
      model: "gpt-4o-mini"
    })
  end

  test "create_session/2 fails without a default LLM config" do
    user = onboarded_user_fixture()

    assert {:error, :no_default_llm_config} = Session.create_session(user, %{})
  end

  test "create_session/2 uses default config and preferences" do
    user = onboarded_user_fixture()
    assert {:ok, _config} = create_default_config(user)

    assert {:ok, session} = Session.create_session(user, %{title: "Hello"})

    assert session.user_id == user.id
    assert session.llm_provider == "openai"
    assert session.llm_model == "gpt-4o-mini"
    assert session.target_language == "es"
    assert session.native_language == "en"
  end

  test "create_session/2 respects provided language overrides" do
    user = onboarded_user_fixture()
    assert {:ok, _config} = create_default_config(user)

    assert {:ok, session} =
             Session.create_session(user, %{
               target_language: "german",
               native_language: "fr"
             })

    assert session.target_language == "german"
    assert session.native_language == "fr"
  end

  test "add_message/3 inserts and returns a decrypted message" do
    user = user_fixture()
    assert {:ok, _config} = create_default_config(user)
    assert {:ok, session} = Session.create_session(user, %{})

    assert {:ok, message} = Session.add_message(session, "user", "Hola")
    assert message.content == "Hola"
    assert message.token_count >= 1

    messages = Session.list_session_messages(session.id)
    assert length(messages) == 1
    assert %ChatMessage{role: "user"} = hd(messages)
  end

  test "get_decrypted_messages/2 returns decrypted content" do
    user = user_fixture()
    assert {:ok, _config} = create_default_config(user)
    assert {:ok, session} = Session.create_session(user, %{})

    assert {:ok, _message} = Session.add_message(session, "assistant", "Bonjour")

    [result] = Session.get_decrypted_messages(session)
    assert result.content == "Bonjour"
  end

  test "update_session_title/2 truncates the title" do
    user = user_fixture()
    assert {:ok, _config} = create_default_config(user)
    assert {:ok, session} = Session.create_session(user, %{})

    long_title = String.duplicate("a", 80)
    assert {:ok, updated} = Session.update_session_title(session, long_title)

    assert String.length(updated.title) == 50
  end

  test "delete_session/1 removes the session" do
    user = user_fixture()
    assert {:ok, _config} = create_default_config(user)
    assert {:ok, session} = Session.create_session(user, %{})

    assert {:ok, _} = Session.delete_session(session)
    assert Repo.get(ChatSession, session.id) == nil
  end
end
