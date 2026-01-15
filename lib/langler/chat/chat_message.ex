defmodule Langler.Chat.ChatMessage do
  @moduledoc """
  Schema for encrypted chat messages.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "chat_messages" do
    belongs_to :chat_session, Langler.Chat.ChatSession
    field :role, :string
    field :encrypted_content, :binary
    field :content_hash, :string
    field :token_count, :integer
    field :metadata, :map

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(chat_message, attrs) do
    chat_message
    |> cast(attrs, [:chat_session_id, :role, :encrypted_content, :content_hash, :token_count, :metadata])
    |> validate_required([:chat_session_id, :role, :encrypted_content, :content_hash])
    |> validate_inclusion(:role, ["user", "assistant", "system"])
  end
end
