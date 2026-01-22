defmodule Langler.Quizzes.Service do
  @moduledoc """
  Service module for quiz orchestration and business logic.

  Handles quiz session initialization, prompt building, and result processing
  separate from UI concerns.
  """

  alias Langler.Chat.Session
  alias Langler.Quizzes
  alias Langler.Quizzes.Result
  alias Langler.Quizzes.ResultParser

  require Logger

  @doc """
  Starts a quiz session for an article.

  Creates a chat session with quiz context and initializes the quiz flow.
  """
  @spec start_quiz_session(map(), Langler.Accounts.User.t()) ::
          {:ok, Langler.Chat.ChatSession.t()} | {:error, term()}
  def start_quiz_session(assigns, user) do
    article_id = Map.get(assigns, :article_id)
    title = Map.get(assigns, :article_title, "Article")
    context_type = Map.get(assigns, :context_type, Quizzes.context_type())

    attrs = %{
      title: String.slice("#{title} quiz", 0, 60),
      context_type: context_type,
      context_id: article_id
    }

    case Session.create_session(user, attrs) do
      {:ok, session} ->
        prompt = build_quiz_prompt(assigns)

        case Session.add_message(session, "system", prompt) do
          {:ok, _msg} -> {:ok, session}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Builds the quiz prompt for the LLM based on article content.

  Returns a formatted prompt string that instructs the LLM on how to conduct the quiz.
  """
  @spec build_quiz_prompt(map()) :: String.t()
  def build_quiz_prompt(assigns) do
    context_type = Map.get(assigns, :context_type, "article_quiz")

    case context_type do
      "article_listening_quiz" ->
        build_listening_quiz_prompt(assigns)

      _ ->
        build_reading_quiz_prompt(assigns)
    end
  end

  defp build_reading_quiz_prompt(assigns) do
    language = Map.get(assigns, :article_language, "Spanish")
    content = Map.get(assigns, :article_content, "")
    topics = Map.get(assigns, :article_topics, []) |> Enum.join(", ")

    # Truncate to stay within model context
    max_content_length = Quizzes.max_content_length()
    truncated_content = String.slice(content, 0, max_content_length)
    is_truncated = String.length(content) > max_content_length

    # Determine question count based on article length
    question_count =
      if String.length(content) < 500 do
        "2-3"
      else
        "5"
      end

    truncation_note =
      if is_truncated do
        "\n\nNote: The article content has been truncated for this quiz. Please grade based on the provided excerpt."
      else
        ""
      end

    """
    You are a quizmaster conducting a quiz about an article in #{language}.

    Your role is to:
    - Ask #{question_count} questions one at a time
    - Mix question types: comprehension questions, vocabulary questions, and grammar questions based on the article content
    - Conduct the entire quiz in #{language} (the article's language)
    - Do NOT tutor, explain answers, or answer user questions - just proceed to the next question
    - After asking all questions, wait for the user's final answer, then provide your grading

    Article topics: #{topics}
    Article content:
    #{truncated_content}#{truncation_note}

    After the user answers all questions, you must provide a quiz result in this exact format:

    BEGIN_QUIZ_RESULT
    {"score": <number>, "max_score": <number>, "questions": [
      {"question": "<question text>", "user_answer": "<user's answer>", "correct": <true/false>, "explanation": "<brief explanation>"},
      ...
    ]}
    END_QUIZ_RESULT

    Start by asking the first question now.
    """
  end

  defp build_listening_quiz_prompt(assigns) do
    language = Map.get(assigns, :article_language, "Spanish")
    content = Map.get(assigns, :article_content, "")
    topics = Map.get(assigns, :article_topics, []) |> Enum.join(", ")

    # Truncate to stay within model context
    max_content_length = Quizzes.max_content_length()
    truncated_content = String.slice(content, 0, max_content_length)
    is_truncated = String.length(content) > max_content_length

    # Determine question count based on article length
    question_count =
      if String.length(content) < 500 do
        "2-3"
      else
        "5"
      end

    truncation_note =
      if is_truncated do
        "\n\nNote: The article content has been truncated for this quiz. Please grade based on the provided excerpt."
      else
        ""
      end

    """
    You are a quizmaster conducting a listening comprehension quiz about an article in #{language}.

    This was a listening exercise - the user listened to the article being read aloud.

    Your role is to:
    - Ask #{question_count} questions one at a time focused on listening comprehension
    - Focus on questions that test understanding of what was heard: main ideas, details, inference, and pronunciation comprehension
    - Mix question types: comprehension questions about the content, questions about specific details mentioned, and inference questions
    - Conduct the entire quiz in #{language} (the article's language)
    - Do NOT tutor, explain answers, or answer user questions - just proceed to the next question
    - After asking all questions, wait for the user's final answer, then provide your grading

    Article topics: #{topics}
    Article transcript (the text that was read aloud):
    #{truncated_content}#{truncation_note}

    After the user answers all questions, you must provide a quiz result in this exact format:

    BEGIN_QUIZ_RESULT
    {"score": <number>, "max_score": <number>, "questions": [
      {"question": "<question text>", "user_answer": "<user's answer>", "correct": <true/false>, "explanation": "<brief explanation>"},
      ...
    ]}
    END_QUIZ_RESULT

    Start by asking the first question now.
    """
  end

  @doc """
  Handles quiz result parsing and persistence.

  Parses the assistant message content for quiz results and persists them if found.
  Returns `{action, result}` tuple where action is `:quiz_completed`, `:quiz_parse_error`, or `nil`.
  """
  @spec handle_quiz_result(Langler.Chat.ChatSession.t(), String.t()) ::
          {:quiz_completed, Result.t()} | {:quiz_parse_error, nil} | {nil, nil}
  def handle_quiz_result(
        %{context_type: context_type} = session,
        assistant_content
      )
      when context_type in ["article_quiz", "article_listening_quiz"] do
    case ResultParser.parse(assistant_content) do
      {:ok, result} ->
        case persist_quiz_result(session, result) do
          {:ok, _attempt} -> {:quiz_completed, result}
          {:error, reason} -> log_and_return_error(reason)
        end

      {:error, :not_found} ->
        {nil, nil}

      {:error, reason} ->
        Logger.warning("Failed to parse quiz result: #{inspect(reason)}")
        {:quiz_parse_error, nil}
    end
  end

  def handle_quiz_result(_session, _assistant_content), do: {nil, nil}

  @doc """
  Validates that a session is a valid quiz session.

  Returns `:ok` if valid, `{:error, reason}` otherwise.
  """
  @spec validate_quiz_session(Langler.Chat.ChatSession.t()) :: :ok | {:error, atom()}
  def validate_quiz_session(%{context_type: context_type, context_id: context_id}) do
    cond do
      context_type != "article_quiz" -> {:error, :invalid_session_type}
      is_nil(context_id) -> {:error, :missing_article_id}
      true -> :ok
    end
  end

  def validate_quiz_session(_), do: {:error, :invalid_session}

  # Private helpers

  defp persist_quiz_result(session, result) do
    case validate_quiz_session(session) do
      :ok ->
        attrs = %{
          score: result.score,
          max_score: result.max_score,
          result_json: Result.to_map(result),
          chat_session_id: session.id,
          started_at: DateTime.utc_now(),
          completed_at: DateTime.utc_now()
        }

        Quizzes.create_attempt(session.user_id, session.context_id, attrs)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp log_and_return_error(%Ecto.Changeset{} = changeset) do
    errors = translate_errors(changeset)
    Logger.error("Failed to persist quiz result: #{inspect(errors)}")
    {:quiz_error, errors}
  end

  defp log_and_return_error(reason) do
    Logger.error("Failed to persist quiz result: #{inspect(reason)}")
    {:quiz_error, reason}
  end

  defp translate_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
