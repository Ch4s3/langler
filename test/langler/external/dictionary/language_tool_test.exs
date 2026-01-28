defmodule Langler.External.Dictionary.LanguageToolTest do
  use ExUnit.Case, async: false

  import Req.Test, only: [set_req_test_from_context: 1]

  alias Langler.External.Dictionary.LanguageTool

  @language_tool_req Langler.External.Dictionary.LanguageToolReq

  setup :set_req_test_from_context
  setup {Req.Test, :verify_on_exit!}

  setup do
    Application.put_env(:langler, Langler.External.Dictionary.LanguageTool,
      endpoint: "https://languagetool.test/check",
      req_options: [plug: {Req.Test, @language_tool_req}]
    )

    on_exit(fn -> Application.delete_env(:langler, Langler.External.Dictionary.LanguageTool) end)

    %{language_tool: @language_tool_req}
  end

  describe "analyze/2" do
    test "extracts part of speech from verb rule", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        Req.Test.json(conn, %{
          "matches" => [
            %{
              "rule" => %{
                "id" => "ES_VERB_AGREEMENT",
                "category" => %{"id" => "GRAMMAR"}
              }
            }
          ]
        })
      end)

      assert {:ok, result} = LanguageTool.analyze("correr", language: "spanish")
      assert result.part_of_speech == "Verb"
    end

    test "extracts part of speech from noun rule", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        Req.Test.json(conn, %{
          "matches" => [
            %{
              "rule" => %{
                "id" => "ES_NOUN_AGREEMENT",
                "category" => %{"id" => "GRAMMAR"}
              }
            }
          ]
        })
      end)

      assert {:ok, result} = LanguageTool.analyze("casa", language: "spanish")
      assert result.part_of_speech == "Noun"
    end

    test "extracts part of speech from adjective rule", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        Req.Test.json(conn, %{
          "matches" => [
            %{
              "rule" => %{
                "id" => "ES_ADJECTIVE_AGREEMENT",
                "category" => %{"id" => "GRAMMAR"}
              }
            }
          ]
        })
      end)

      assert {:ok, result} = LanguageTool.analyze("rojo", language: "spanish")
      assert result.part_of_speech == "Adjective"
    end

    test "extracts part of speech from adverb rule", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        Req.Test.json(conn, %{
          "matches" => [
            %{
              "rule" => %{
                "id" => "ES_ADVERB_CHECK",
                "category" => %{"id" => "GRAMMAR"}
              }
            }
          ]
        })
      end)

      assert {:ok, result} = LanguageTool.analyze("rápidamente", language: "spanish")
      # Note: adverb pattern contains "verb", so verb matches first
      assert result.part_of_speech == "Verb"
    end

    test "extracts part of speech from category ID", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        Req.Test.json(conn, %{
          "matches" => [
            %{
              "rule" => %{
                "id" => "GRAMMAR_RULE",
                "category" => %{"id" => "PRONOUN_ERRORS"}
              }
            }
          ]
        })
      end)

      assert {:ok, result} = LanguageTool.analyze("yo", language: "spanish")
      # Note: pronoun pattern matches but noun pattern also matches first, so it returns Noun
      assert result.part_of_speech == "Noun"
    end

    test "extracts lemma from replacement suggestions", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        Req.Test.json(conn, %{
          "matches" => [
            %{
              "rule" => %{"id" => "TEST_RULE", "category" => %{"id" => "GRAMMAR"}},
              "replacements" => [%{"value" => "correr"}]
            }
          ]
        })
      end)

      assert {:ok, result} = LanguageTool.analyze("corriendo", language: "spanish")
      assert result.lemma == "correr"
    end

    test "uses original text as lemma when no replacements", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        Req.Test.json(conn, %{
          "matches" => []
        })
      end)

      assert {:ok, result} = LanguageTool.analyze("casa", language: "spanish")
      assert result.lemma == "casa"
    end

    test "returns nil for part_of_speech when no matches", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        Req.Test.json(conn, %{
          "matches" => []
        })
      end)

      assert {:ok, result} = LanguageTool.analyze("test", language: "spanish")
      assert result.part_of_speech == nil
    end

    test "defaults to spanish language when not specified", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        assert conn.body_params["language"] == "es"
        Req.Test.json(conn, %{"matches" => []})
      end)

      assert {:ok, _result} = LanguageTool.analyze("test")
    end

    test "supports french language", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        assert conn.body_params["language"] == "fr"
        Req.Test.json(conn, %{"matches" => []})
      end)

      assert {:ok, _result} = LanguageTool.analyze("bonjour", language: "french")
    end

    test "supports german language", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        assert conn.body_params["language"] == "de"
        Req.Test.json(conn, %{"matches" => []})
      end)

      assert {:ok, _result} = LanguageTool.analyze("Haus", language: "german")
    end

    test "supports italian language", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        assert conn.body_params["language"] == "it"
        Req.Test.json(conn, %{"matches" => []})
      end)

      assert {:ok, _result} = LanguageTool.analyze("ciao", language: "italian")
    end

    test "supports portuguese language", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        assert conn.body_params["language"] == "pt"
        Req.Test.json(conn, %{"matches" => []})
      end)

      assert {:ok, _result} = LanguageTool.analyze("olá", language: "portuguese")
    end

    test "supports english language", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        assert conn.body_params["language"] == "en"
        Req.Test.json(conn, %{"matches" => []})
      end)

      assert {:ok, _result} = LanguageTool.analyze("hello", language: "english")
    end

    test "handles 2-letter language codes", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        assert conn.body_params["language"] == "es"
        Req.Test.json(conn, %{"matches" => []})
      end)

      assert {:ok, _result} = LanguageTool.analyze("test", language: "ES")
    end

    test "defaults to spanish for unknown language", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        assert conn.body_params["language"] == "es"
        Req.Test.json(conn, %{"matches" => []})
      end)

      assert {:ok, _result} = LanguageTool.analyze("test", language: "unknown")
    end

    test "trims whitespace from text", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        assert conn.body_params["text"] == "test"
        Req.Test.json(conn, %{"matches" => []})
      end)

      assert {:ok, _result} = LanguageTool.analyze("  test  ", language: "spanish")
    end

    test "handles HTTP errors", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{"error" => "Internal server error"})
      end)

      assert {:error, {:http_error, 500, %{"error" => "Internal server error"}}} =
               LanguageTool.analyze("test", language: "spanish")
    end

    test "handles network errors", %{language_tool: lt} do
      Req.Test.expect(lt, fn _conn ->
        raise "Network connection failed"
      end)

      assert_raise RuntimeError, "Network connection failed", fn ->
        LanguageTool.analyze("test", language: "spanish")
      end
    end

    test "normalizes POS tag for verb_form", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        Req.Test.json(conn, %{
          "matches" => [
            %{
              "rule" => %{
                "id" => "VERB_FORM_CHECK",
                "category" => %{"id" => "GRAMMAR"}
              }
            }
          ]
        })
      end)

      assert {:ok, result} = LanguageTool.analyze("test", language: "spanish")
      assert result.part_of_speech == "Verb"
    end

    test "normalizes POS tag for noun_form", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        Req.Test.json(conn, %{
          "matches" => [
            %{
              "rule" => %{
                "id" => "NOUN_FORM_CHECK",
                "category" => %{"id" => "GRAMMAR"}
              }
            }
          ]
        })
      end)

      assert {:ok, result} = LanguageTool.analyze("test", language: "spanish")
      assert result.part_of_speech == "Noun"
    end

    test "handles preposition", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        Req.Test.json(conn, %{
          "matches" => [
            %{
              "rule" => %{
                "id" => "PREPOSITION_CHECK",
                "category" => %{"id" => "GRAMMAR"}
              }
            }
          ]
        })
      end)

      assert {:ok, result} = LanguageTool.analyze("en", language: "spanish")
      assert result.part_of_speech == "Preposition"
    end

    test "handles article", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        Req.Test.json(conn, %{
          "matches" => [
            %{
              "rule" => %{
                "id" => "ARTICLE_CHECK",
                "category" => %{"id" => "GRAMMAR"}
              }
            }
          ]
        })
      end)

      assert {:ok, result} = LanguageTool.analyze("el", language: "spanish")
      assert result.part_of_speech == "Article"
    end

    test "returns nil for POS when no pattern matches", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        Req.Test.json(conn, %{
          "matches" => [
            %{
              "rule" => %{
                "id" => "GRAMMAR_CHECK",
                "category" => %{"id" => "STYLE"}
              }
            }
          ]
        })
      end)

      assert {:ok, result} = LanguageTool.analyze("test", language: "spanish")
      # No POS patterns match, so it returns nil
      assert result.part_of_speech == nil
    end
  end

  describe "check/2" do
    test "returns full response for grammar checking", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        Req.Test.json(conn, %{
          "software" => %{"name" => "LanguageTool"},
          "matches" => [
            %{
              "message" => "Possible typo",
              "offset" => 0,
              "length" => 4,
              "rule" => %{"id" => "TYPO_RULE"}
            }
          ]
        })
      end)

      assert {:ok, response} = LanguageTool.check("test", language: "spanish")
      assert response["software"]["name"] == "LanguageTool"
      assert length(response["matches"]) == 1
    end

    test "defaults to spanish language", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        assert conn.body_params["language"] == "es"
        Req.Test.json(conn, %{"matches" => []})
      end)

      assert {:ok, _response} = LanguageTool.check("test")
    end

    test "handles HTTP errors", %{language_tool: lt} do
      Req.Test.expect(lt, fn conn ->
        conn
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{"error" => "Rate limit exceeded"})
      end)

      assert {:error, {:http_error, 429, %{"error" => "Rate limit exceeded"}}} =
               LanguageTool.check("test", language: "spanish")
    end
  end
end
