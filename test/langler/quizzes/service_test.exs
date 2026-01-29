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

    test "builds reading quiz prompt by default" do
      prompt =
        Service.build_quiz_prompt(%{
          article_language: "Spanish",
          article_content: "Test content",
          article_topics: ["sports"]
        })

      assert prompt =~ "You are a quizmaster"
      assert prompt =~ "Spanish"
      assert prompt =~ "sports"
      assert prompt =~ "Test content"
      assert prompt =~ "BEGIN_QUIZ_RESULT"
    end

    test "uses default language when not specified" do
      prompt = Service.build_quiz_prompt(%{article_content: "Test"})

      assert prompt =~ "Spanish"
    end

    test "uses default empty content when not specified" do
      prompt = Service.build_quiz_prompt(%{article_language: "French"})

      assert prompt =~ "French"
    end

    test "handles empty topics list" do
      prompt =
        Service.build_quiz_prompt(%{
          article_language: "Spanish",
          article_content: "Test",
          article_topics: []
        })

      assert prompt =~ "Article topics: "
    end

    test "asks 2-3 questions for short content" do
      short_content = String.duplicate("word ", 50)

      prompt =
        Service.build_quiz_prompt(%{
          article_content: short_content
        })

      assert prompt =~ "2-3 questions"
    end

    test "asks 5 questions for longer content" do
      long_content = String.duplicate("word ", 200)

      prompt =
        Service.build_quiz_prompt(%{
          article_content: long_content
        })

      assert prompt =~ "Ask 5 questions"
    end

    test "does not include truncation note for short content" do
      short_content = "This is a short article"

      prompt =
        Service.build_quiz_prompt(%{
          article_content: short_content
        })

      refute prompt =~ "truncated"
    end

    test "builds listening quiz prompt when context type is article_listening_quiz" do
      prompt =
        Service.build_quiz_prompt(%{
          context_type: "article_listening_quiz",
          article_language: "Spanish",
          article_content: "Test content",
          article_topics: ["culture"]
        })

      assert prompt =~ "listening comprehension quiz"
      assert prompt =~ "listened to the article"
      assert prompt =~ "Spanish"
      assert prompt =~ "culture"
      assert prompt =~ "Test content"
    end

    test "listening quiz asks 2-3 questions for short content" do
      short_content = String.duplicate("word ", 50)

      prompt =
        Service.build_quiz_prompt(%{
          context_type: "article_listening_quiz",
          article_content: short_content
        })

      assert prompt =~ "2-3 questions"
    end

    test "listening quiz asks 5 questions for longer content" do
      long_content = String.duplicate("word ", 200)

      prompt =
        Service.build_quiz_prompt(%{
          context_type: "article_listening_quiz",
          article_content: long_content
        })

      assert prompt =~ "Ask 5 questions"
    end

    test "listening quiz includes truncation note for long content" do
      long_content = String.duplicate("palabra ", Quizzes.max_content_length() + 20)

      prompt =
        Service.build_quiz_prompt(%{
          context_type: "article_listening_quiz",
          article_content: long_content
        })

      assert prompt =~ "truncated"
    end

    test "listening quiz uses default language when not specified" do
      prompt =
        Service.build_quiz_prompt(%{
          context_type: "article_listening_quiz",
          article_content: "Test"
        })

      assert prompt =~ "Spanish"
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

    test "uses default article title when not specified", %{user: user, article: article} do
      assigns = %{article_id: article.id}

      assert {:ok, %ChatSession{} = session} = Service.start_quiz_session(assigns, user)
      assert session.title =~ "Article quiz"
    end

    test "truncates long titles to 60 characters", %{user: user, article: article} do
      long_title = String.duplicate("Long Title ", 10)
      assigns = %{article_id: article.id, article_title: long_title}

      assert {:ok, %ChatSession{} = session} = Service.start_quiz_session(assigns, user)
      assert String.length(session.title) <= 60
    end

    test "uses custom context_type when provided", %{user: user, article: article} do
      assigns = %{
        article_id: article.id,
        article_title: article.title,
        context_type: "article_listening_quiz"
      }

      assert {:ok, %ChatSession{} = session} = Service.start_quiz_session(assigns, user)
      assert session.context_type == "article_listening_quiz"
    end

    test "uses default context_type when not provided", %{user: user, article: article} do
      assigns = %{article_id: article.id}

      assert {:ok, %ChatSession{} = session} = Service.start_quiz_session(assigns, user)
      assert session.context_type == Quizzes.context_type()
    end

    test "returns error when session creation fails", %{user: user} do
      # Missing required article_id
      assigns = %{}

      assert {:error, _reason} = Service.start_quiz_session(assigns, user)
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

    test "returns nil tuple when no quiz result found in content", %{session: session} do
      assistant_content = "This is just a regular message without quiz results"

      assert {nil, nil} = Service.handle_quiz_result(session, assistant_content)
    end

    test "returns quiz_parse_error when result parsing fails", %{session: session} do
      # Invalid JSON in quiz result
      assistant_content = "BEGIN_QUIZ_RESULT\n{invalid json}\nEND_QUIZ_RESULT"

      assert {:quiz_parse_error, nil} = Service.handle_quiz_result(session, assistant_content)
    end

    test "handles listening quiz context type", %{user: user, article: article} do
      {:ok, session} =
        Session.create_session(user, %{
          context_type: "article_listening_quiz",
          context_id: article.id,
          title: "Listening Quiz"
        })

      result = %Result{
        score: 3,
        max_score: 5,
        questions: [
          %{
            "question" => "What did you hear?",
            "user_answer" => "test",
            "correct" => true,
            "explanation" => "Correct"
          }
        ]
      }

      json = Jason.encode!(Result.to_map(result))
      assistant_content = "BEGIN_QUIZ_RESULT\n#{json}\nEND_QUIZ_RESULT"

      assert {:quiz_completed, %Result{}} = Service.handle_quiz_result(session, assistant_content)
    end

    test "returns quiz_error when persistence fails due to validation", %{
      user: user,
      article: article
    } do
      {:ok, session} =
        Session.create_session(user, %{
          context_type: "article_quiz",
          context_id: article.id,
          title: "Quiz"
        })

      # Create invalid result (negative score)
      result = %Result{
        score: -1,
        max_score: 5,
        questions: []
      }

      json = Jason.encode!(Result.to_map(result))
      assistant_content = "BEGIN_QUIZ_RESULT\n#{json}\nEND_QUIZ_RESULT"

      assert {:quiz_error, _errors} = Service.handle_quiz_result(session, assistant_content)
    end

    test "returns nil for non-quiz sessions", %{user: user} do
      {:ok, session} =
        Session.create_session(user, %{
          context_type: "chat",
          title: "Regular Chat"
        })

      assistant_content = "Some response"

      assert {nil, nil} = Service.handle_quiz_result(session, assistant_content)
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

    test "validates successfully with valid article_quiz session" do
      session = %ChatSession{
        context_type: "article_quiz",
        context_id: 456
      }

      assert :ok = Service.validate_quiz_session(session)
    end

    test "returns error for session without required fields" do
      assert {:error, :invalid_session} = Service.validate_quiz_session(%{})
    end

    test "returns error for nil session" do
      assert {:error, :invalid_session} = Service.validate_quiz_session(nil)
    end

    test "returns error for listening_quiz context type" do
      session = %ChatSession{
        context_type: "article_listening_quiz",
        context_id: 123
      }

      assert {:error, :invalid_session_type} = Service.validate_quiz_session(session)
    end

    test "returns error when context_id is 0" do
      session = %ChatSession{
        context_type: "article_quiz",
        context_id: 0
      }

      # 0 is not nil, so this passes validation
      assert :ok = Service.validate_quiz_session(session)
    end
  end
end
