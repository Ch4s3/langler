defmodule Langler.Chat.ChatMessageTest do
  use Langler.DataCase, async: true

  alias Langler.Chat.ChatMessage

  test "changeset validates required fields and role inclusion" do
    changeset = ChatMessage.changeset(%ChatMessage{}, %{})

    refute changeset.valid?

    assert %{
             chat_session_id: ["can't be blank"],
             role: ["can't be blank"],
             encrypted_content: ["can't be blank"],
             content_hash: ["can't be blank"]
           } = errors_on(changeset)

    invalid_role =
      ChatMessage.changeset(%ChatMessage{}, %{
        chat_session_id: 1,
        role: "invalid",
        encrypted_content: "ciphertext",
        content_hash: "hash"
      })

    assert %{role: ["is invalid"]} = errors_on(invalid_role)
  end

  test "changeset accepts valid roles" do
    changeset =
      ChatMessage.changeset(%ChatMessage{}, %{
        chat_session_id: 1,
        role: "assistant",
        encrypted_content: "ciphertext",
        content_hash: "hash",
        token_count: 10
      })

    assert changeset.valid?
  end
end
