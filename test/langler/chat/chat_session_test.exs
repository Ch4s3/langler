defmodule Langler.Chat.ChatSessionTest do
  use Langler.DataCase, async: true

  alias Langler.Chat.ChatSession

  test "changeset validates required fields and context type inclusion" do
    changeset = ChatSession.changeset(%ChatSession{}, %{})

    refute changeset.valid?

    assert %{
             user_id: ["can't be blank"],
             llm_provider: ["can't be blank"],
             target_language: ["can't be blank"],
             native_language: ["can't be blank"]
           } = errors_on(changeset)

    invalid_context =
      ChatSession.changeset(%ChatSession{}, %{
        user_id: 1,
        llm_provider: "openai",
        target_language: "spanish",
        native_language: "en",
        context_type: "invalid"
      })

    assert %{context_type: ["is invalid"]} = errors_on(invalid_context)
  end

  test "changeset accepts valid context type" do
    changeset =
      ChatSession.changeset(%ChatSession{}, %{
        user_id: 1,
        llm_provider: "openai",
        target_language: "spanish",
        native_language: "en",
        context_type: "article"
      })

    assert changeset.valid?
  end
end
