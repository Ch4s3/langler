defmodule Langler.ChatFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Langler.Chat` context.
  """

  alias Langler.Chat.ChatSession

  @doc """
  Generate a chat_session struct for testing components.
  This creates a struct without persisting to the database.
  For component tests, use this version.
  """
  def chat_session_fixture(attrs \\ %{}) do
    default_attrs = %{
      id: attrs[:id] || :rand.uniform(100_000),
      user_id: attrs[:user_id] || 1,
      title: "Test Chat",
      context_type: nil,
      context_id: nil,
      llm_provider: "chatgpt",
      llm_model: "gpt-4o-mini",
      target_language: "spanish",
      native_language: "en",
      pinned: false,
      inserted_at: DateTime.utc_now()
    }

    attrs = Enum.into(attrs, default_attrs)

    %ChatSession{
      __meta__: %Ecto.Schema.Metadata{state: :loaded, source: "chat_sessions"},
      id: attrs.id,
      user_id: attrs.user_id,
      title: attrs.title,
      context_type: attrs.context_type,
      context_id: attrs.context_id,
      llm_provider: attrs.llm_provider,
      llm_model: attrs.llm_model,
      target_language: attrs.target_language,
      native_language: attrs.native_language,
      pinned: attrs.pinned || false,
      inserted_at: attrs.inserted_at || DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end
end
