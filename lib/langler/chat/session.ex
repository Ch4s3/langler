defmodule Langler.Chat.Session do
  @moduledoc """
  Context module for managing encrypted chat sessions.

  Provides functions for creating, updating, and querying chat sessions
  with encrypted message content for language learning conversations.
  """

  import Ecto.Query
  alias Langler.Accounts.{LlmConfig, User}
  alias Langler.Chat.{ChatMessage, ChatSession}
  alias Langler.Repo

  @doc """
  Creates a new chat session for a user.
  """
  @spec create_session(User.t(), map()) :: {:ok, ChatSession.t()} | {:error, term()}
  def create_session(%User{} = user, attrs \\ %{}) do
    default_config = LlmConfig.get_default_config(user.id)

    if is_nil(default_config) do
      {:error, :no_default_llm_config}
    else
      # Fetch user preference separately
      alias Langler.Accounts.UserPreference

      user_pref =
        Repo.one(from p in UserPreference, where: p.user_id == ^user.id) ||
          %UserPreference{target_language: "spanish", native_language: "en"}

      attrs =
        attrs
        |> Map.put_new(:llm_provider, default_config.provider_name)
        |> Map.put_new(:llm_model, default_config.model)
        |> Map.put_new(:target_language, user_pref.target_language)
        |> Map.put_new(:native_language, user_pref.native_language)
        |> Map.put(:user_id, user.id)

      %ChatSession{}
      |> ChatSession.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Gets a chat session by ID.
  """
  @spec get_session(integer()) :: ChatSession.t() | nil
  def get_session(session_id) do
    Repo.get(ChatSession, session_id)
  end

  @doc """
  Lists recent chat sessions for a user.
  """
  @spec list_user_sessions(integer(), keyword()) :: list(ChatSession.t())
  def list_user_sessions(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    ChatSession
    |> where(user_id: ^user_id)
    |> order_by([s], desc: s.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Lists messages for a session.
  Returns raw encrypted messages.
  """
  @spec list_session_messages(integer(), keyword()) :: list(ChatMessage.t())
  def list_session_messages(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    ChatMessage
    |> where(chat_session_id: ^session_id)
    |> order_by([m], asc: m.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets decrypted messages for a session.
  Returns a list of message maps with decrypted content.
  """
  @spec get_decrypted_messages(ChatSession.t(), keyword()) :: list(map())
  def get_decrypted_messages(%ChatSession{} = session, opts \\ []) do
    alias Langler.Chat.Encryption

    session_id = session.id
    messages = list_session_messages(session_id, opts)

    messages
    |> Enum.map(fn message ->
      case Encryption.decrypt_message(session.user_id, message.encrypted_content) do
        {:ok, content} ->
          %{
            role: message.role,
            content: content,
            token_count: message.token_count,
            inserted_at: message.inserted_at
          }

        {:error, _reason} ->
          %{
            role: message.role,
            content: "[Unable to decrypt message]",
            token_count: message.token_count,
            inserted_at: message.inserted_at
          }
      end
    end)
  end

  @doc """
  Adds a message to a session.
  Returns the decrypted message map.
  """
  @spec add_message(ChatSession.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def add_message(%ChatSession{} = session, role, content)
      when role in ["user", "assistant", "system"] and is_binary(content) do
    alias Langler.Chat.{Encryption, TokenCounter}

    with {:ok, encrypted_content} <- Encryption.encrypt_message(session.user_id, content) do
      content_hash = Encryption.hash_content(session.user_id, content)
      token_count = TokenCounter.count_tokens(content)

      attrs = %{
        chat_session_id: session.id,
        role: role,
        encrypted_content: encrypted_content,
        content_hash: content_hash,
        token_count: token_count
      }

      case %ChatMessage{}
           |> ChatMessage.changeset(attrs)
           |> Repo.insert() do
        {:ok, _message} ->
          # Return decrypted message for immediate display
          {:ok,
           %{
             role: role,
             content: content,
             token_count: token_count,
             inserted_at: DateTime.utc_now()
           }}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Updates a session title (e.g., from first user message).
  """
  @spec update_session_title(ChatSession.t(), String.t()) ::
          {:ok, ChatSession.t()} | {:error, term()}
  def update_session_title(%ChatSession{} = session, title) do
    session
    |> ChatSession.changeset(%{title: String.slice(title, 0, 50)})
    |> Repo.update()
  end

  @doc """
  Deletes a chat session and all its messages.
  """
  @spec delete_session(ChatSession.t()) :: {:ok, ChatSession.t()} | {:error, term()}
  def delete_session(%ChatSession{} = session) do
    Repo.delete(session)
  end
end
