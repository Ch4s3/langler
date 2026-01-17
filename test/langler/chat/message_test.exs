defmodule Langler.Chat.MessageTest do
  use Langler.DataCase, async: true

  import Ecto.Query
  import Langler.AccountsFixtures

  alias Langler.Accounts.LlmConfig
  alias Langler.Chat.{ChatMessage, Message, Session}
  alias Langler.Repo

  defp create_session(user) do
    assert {:ok, _config} =
             LlmConfig.create_config(user, %{
               provider_name: "openai",
               api_key: "secret-key-1234",
               model: "gpt-4o-mini"
             })

    assert {:ok, session} = Session.create_session(user, %{})
    session
  end

  test "create_message/4 inserts encrypted messages" do
    user = user_fixture()
    session = create_session(user)

    assert {:ok, message} = Message.create_message(session.id, "user", "Hello", %{})
    assert message.chat_session_id == session.id
    assert message.token_count >= 1
    assert is_binary(message.encrypted_content)
  end

  test "list_session_messages/2 returns decrypted messages in descending order" do
    user = user_fixture()
    session = create_session(user)

    assert {:ok, first} = Message.create_message(session.id, "user", "First", nil)

    earlier = DateTime.add(DateTime.utc_now(), -3600, :second)

    from(m in ChatMessage, where: m.id == ^first.id)
    |> Repo.update_all(set: [inserted_at: earlier, updated_at: earlier])

    assert {:ok, _second} = Message.create_message(session.id, "assistant", "Second", nil)

    [latest, older] = Message.list_session_messages(session.id, 2)

    assert latest.content == "Second"
    assert older.content == "First"
  end

  test "list_older_messages/3 returns only messages before the reference id" do
    user = user_fixture()
    session = create_session(user)

    assert {:ok, first} = Message.create_message(session.id, "user", "First", nil)

    earlier = DateTime.add(DateTime.utc_now(), -3600, :second)

    from(m in ChatMessage, where: m.id == ^first.id)
    |> Repo.update_all(set: [inserted_at: earlier, updated_at: earlier])

    assert {:ok, second} = Message.create_message(session.id, "assistant", "Second", nil)

    [older] = Message.list_older_messages(session.id, second.id, 5)
    assert older.content == "First"
  end

  test "get_message/1 returns a decrypted message map" do
    user = user_fixture()
    session = create_session(user)

    assert {:ok, message} = Message.create_message(session.id, "user", "Hello", nil)

    result = Message.get_message(message.id)

    assert result.content == "Hello"
    assert result.role == "user"
    assert result.token_count == message.token_count
  end
end
