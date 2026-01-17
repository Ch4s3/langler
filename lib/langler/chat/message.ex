defmodule Langler.Chat.Message do
  @moduledoc """
  Context for managing encrypted chat messages.
  """

  import Ecto.Query
  alias Langler.Chat.{ChatMessage, ChatSession, Encryption, TokenCounter}
  alias Langler.Repo

  @doc """
  Creates a new encrypted message and counts tokens.

  ## Parameters
    - `session_id`: The chat session ID
    - `role`: Message role ("user", "assistant", "system")
    - `content`: Plaintext content
    - `metadata`: Optional metadata map

  ## Returns
    - `{:ok, message}` on success
    - `{:error, reason}` on failure
  """
  @spec create_message(integer(), String.t(), String.t(), map() | nil) ::
          {:ok, ChatMessage.t()} | {:error, term()}
  def create_message(session_id, role, content, metadata \\ nil)
      when is_integer(session_id) and is_binary(role) and is_binary(content) do
    with {:ok, session} <- get_session_with_user(session_id),
         {:ok, encrypted_content} <- Encryption.encrypt_message(session.user_id, content),
         content_hash <- Encryption.hash_content(session.user_id, content),
         token_count <- TokenCounter.count_tokens(content) do
      attrs = %{
        chat_session_id: session_id,
        role: role,
        encrypted_content: encrypted_content,
        content_hash: content_hash,
        token_count: token_count,
        metadata: metadata
      }

      %ChatMessage{}
      |> ChatMessage.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Lists session messages (decrypted), paginated.

  Returns the most recent messages first (descending by inserted_at).
  """
  @spec list_session_messages(integer(), integer()) :: list(map())
  def list_session_messages(session_id, limit \\ 10)
      when is_integer(session_id) and is_integer(limit) do
    case get_session_with_user(session_id) do
      {:ok, session} ->
        messages =
          ChatMessage
          |> where(chat_session_id: ^session_id)
          |> order_by([m], desc: m.inserted_at)
          |> limit(^limit)
          |> Repo.all()

        decrypt_messages(messages, session.user_id)

      {:error, _} ->
        []
    end
  end

  @doc """
  Loads older messages before a given message ID.
  """
  @spec list_older_messages(integer(), integer(), integer()) :: list(map())
  def list_older_messages(session_id, before_message_id, limit \\ 10)
      when is_integer(session_id) and is_integer(before_message_id) and is_integer(limit) do
    case get_session_with_user(session_id) do
      {:ok, session} ->
        # Get the timestamp of the "before" message
        before_message = Repo.get(ChatMessage, before_message_id)

        if before_message && before_message.chat_session_id == session_id do
          messages =
            ChatMessage
            |> where(chat_session_id: ^session_id)
            |> where([m], m.inserted_at < ^before_message.inserted_at)
            |> order_by([m], desc: m.inserted_at)
            |> limit(^limit)
            |> Repo.all()

          decrypt_messages(messages, session.user_id)
        else
          []
        end

      {:error, _} ->
        []
    end
  end

  @doc """
  Gets a single decrypted message.
  """
  @spec get_message(integer()) :: map() | nil
  def get_message(message_id) when is_integer(message_id) do
    case Repo.get(ChatMessage, message_id) |> Repo.preload(chat_session: :user) do
      nil ->
        nil

      message ->
        user_id = message.chat_session.user_id

        case Encryption.decrypt_message(user_id, message.encrypted_content) do
          {:ok, content} ->
            %{
              id: message.id,
              role: message.role,
              content: content,
              token_count: message.token_count,
              metadata: message.metadata,
              inserted_at: message.inserted_at
            }

          {:error, _} ->
            nil
        end
    end
  end

  ## Private Functions

  defp get_session_with_user(session_id) do
    case Repo.get(ChatSession, session_id) |> Repo.preload(:user) do
      nil -> {:error, :session_not_found}
      session -> {:ok, session}
    end
  end

  defp decrypt_messages(messages, user_id) do
    messages
    |> Enum.map(fn message ->
      case Encryption.decrypt_message(user_id, message.encrypted_content) do
        {:ok, content} ->
          %{
            id: message.id,
            role: message.role,
            content: content,
            token_count: message.token_count,
            metadata: message.metadata,
            inserted_at: message.inserted_at
          }

        {:error, _} ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
