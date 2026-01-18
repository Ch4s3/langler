defmodule Langler.Quizzes.ServiceTest do
  use Langler.DataCase, async: true

  alias Langler.AccountsFixtures
  alias Langler.Accounts.LlmConfig
  alias Langler.Chat.Session
  alias Langler.Chat.ChatSession
  alias Langler.ContentFixtures
  alias Langler.Quizzes
  alias Langler.Quizzes.Result
  alias Langler.Quizzes.Service

  setup do
    user = AccountsFixtures.user_fixture()

    {:ok, _config} =
      LlmConfig.create_config(user, %{
        provider_name: "openai",
        api_key: "secret-key",
        model: "gpt-4o-mini"
      })

    article = ContentFixtures.article_fixture(%{user: user})

    %{user: user, article: article}
  end

  describe "build_quiz_prompt/1" do
    test "includes language, topics, and truncation information" do
      long_content = String.duplicate("palabra ", Quizzes.max_content_length() + 20)

      prompt =
        Service.build_quiz_prompt(%{
          article_language: "French",
          article_content: long_content,
          article_topics: ["ciencia", "política"]
        })

      assert prompt =~ "French"
      assert prompt =~ "ciencia, política"
      assert prompt =~ "Note: The article content has been truncated"
      assert prompt =~ "Ask 5 questions"
    end
  end

  describe "start_quiz_session/2" do
    test "creates a quiz session and adds the system prompt", %{user: user, article: article} do
      assigns = %{article_id: article.id, article_title: article.title}

      assert {:ok, %ChatSession{} = session} = Service.start_quiz_session(assigns, user)
      assert session.context_type == "article_quiz"
      assert session.context_id == article.id
      assert session.user_id == user.id

      messages = Session.list_session_messages(session.id)
      assert Enum.any?(messages, fn msg -> msg.role == "system" end)
    end
  end

  describe "handle_quiz_result/2" do
    setup %{user: user, article: article} do
      {:ok, session} =
        Session.create_session(user, %{
          context_type: "article_quiz",
          context_id: article.id,
          title: "Quiz"
        })

      %{session: session}
    end

    test "persists parsed quiz results and returns completed tuple", %{
      user: user,
      article: article,
      session: session
    } do
      result = %Result{
        score: 4,
        max_score: 5,
        questions: [
          %{
            "question" => "¿Cuál es el tema?",
            "user_answer" => "ciencia",
            "correct" => true,
            "explanation" => "Because the article is about science."
          }
        ]
      }

      json = Jason.encode!(Result.to_map(result))
      assistant_content = "BEGIN_QUIZ_RESULT\n#{json}\nEND_QUIZ_RESULT"

      assert {:quiz_completed, %Result{} = parsed} =
               Service.handle_quiz_result(session, assistant_content)

      assert parsed.score == 4
      assert 1 == Quizzes.count_attempts_for_article(user.id, article.id)
    end

    test "ignores invalid sessions", %{article: article} do
      session = %ChatSession{context_type: "chat", context_id: article.id, user_id: 1}

      assert {nil, nil} = Service.handle_quiz_result(session, "foo")
    end
  end

  describe "validate_quiz_session/1" do
    test "returns errors for invalid context types or missing article id" do
      assert {:error, :invalid_session_type} =
               Service.validate_quiz_session(%ChatSession{context_type: "chat"})

      assert {:error, :missing_article_id} =
               Service.validate_quiz_session(%ChatSession{
                 context_type: "article_quiz",
                 context_id: nil
               })

      assert :ok =
               Service.validate_quiz_session(%ChatSession{
                 context_type: "article_quiz",
                 context_id: 123
               })
    end
  end
end
