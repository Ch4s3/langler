defmodule Langler.Chat.ChatSession do
  @moduledoc """
  Schema for chat session metadata.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "chat_sessions" do
    belongs_to :user, Langler.Accounts.User
    field :title, :string
    field :context_type, :string
    field :context_id, :integer
    field :llm_provider, :string
    field :llm_model, :string
    field :target_language, :string
    field :native_language, :string

    has_many :messages, Langler.Chat.ChatMessage, foreign_key: :chat_session_id

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @doc false
  def changeset(chat_session, attrs) do
    chat_session
    |> cast(attrs, [
      :user_id,
      :title,
      :context_type,
      :context_id,
      :llm_provider,
      :llm_model,
      :target_language,
      :native_language
    ])
    |> validate_required([:user_id, :llm_provider, :target_language, :native_language])
    |> validate_inclusion(
      :context_type,
      [
        "general",
        "article",
        Langler.Quizzes.context_type(),
        "vocabulary",
        "conjugation",
        "grammar"
      ],
      allow_nil: true
    )
  end
end
