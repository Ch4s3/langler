defmodule LanglerWeb.DictionarySearchLive.ModalIntegrationTest do
  use LanglerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Req.Test, only: [set_req_test_from_context: 1]

  alias Langler.AccountsFixtures
  alias Langler.StudyFixtures
  alias Langler.VocabularyFixtures
  alias Langler.Accounts
  alias Langler.Study
  alias Langler.Vocabulary

  @google_req Langler.External.Dictionary.GoogleReq
  @wiktionary_req Langler.External.Dictionary.WiktionaryReq
  @languagetool_req Langler.External.Dictionary.LanguageToolReq

  setup :set_req_test_from_context
  setup {Req.Test, :verify_on_exit!}

  setup do
    Application.put_env(:langler, Langler.External.Dictionary.Google,
      dictionary_endpoint: "https://google.test/dictionary",
      cache_table: :google_dictionary_integration_cache,
      req_options: [plug: {Req.Test, @google_req}]
    )

    Application.put_env(:langler, Langler.External.Dictionary.Wiktionary,
      base_url: "https://wiktionary.test/wiki",
      cache_table: :wiktionary_dictionary_integration_cache,
      req_options: [plug: {Req.Test, @wiktionary_req}]
    )

    Application.put_env(:langler, Langler.External.Dictionary.LanguageTool,
      endpoint: "https://languagetool.test/check",
      cache_table: :languagetool_dictionary_integration_cache,
      req_options: [plug: {Req.Test, @languagetool_req}]
    )

    cleanup_tables([
      :dictionary_entry_cache,
      :google_dictionary_integration_cache,
      :wiktionary_dictionary_integration_cache,
      :languagetool_dictionary_integration_cache
    ])

    on_exit(fn ->
      cleanup_tables([
        :dictionary_entry_cache,
        :google_dictionary_integration_cache,
        :wiktionary_dictionary_integration_cache,
        :languagetool_dictionary_integration_cache
      ])

      Application.delete_env(:langler, Langler.External.Dictionary.Google)
      Application.delete_env(:langler, Langler.External.Dictionary.Wiktionary)
      Application.delete_env(:langler, Langler.External.Dictionary.LanguageTool)
    end)

    {:ok, google: @google_req, wiktionary: @wiktionary_req, languagetool: @languagetool_req}
  end

  defp cleanup_tables(tables) do
    for table <- tables do
      if :ets.whereis(table) != :undefined do
        try do
          :ets.delete_all_objects(table)
        catch
          :error, :badarg -> :ok
        end
      end
    end
  end

  describe "dictionary search modal" do
    test "modal is present but closed initially", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/articles")

      # Modal wrapper should be present
      assert html =~ "id=\"dictionary-search-modal-wrapper\""
      # But modal should not have modal-open class
      refute html =~ "modal-open"

      # The modal element should exist
      assert has_element?(view, "#dictionary-search-modal")
    end

    test "modal opens when open_search event is pushed", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/articles")

      # Push the open_search event to the modal component
      view
      |> element("#dictionary-search-modal-wrapper")
      |> render_hook("open_search", %{})

      # Modal should now have modal-open class
      html = render(view)
      assert html =~ "modal-open"
    end

    test "modal closes when close_search event is pushed", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/articles")

      # Open the modal first
      view
      |> element("#dictionary-search-modal-wrapper")
      |> render_hook("open_search", %{})

      assert render(view) =~ "modal-open"

      # Now close it
      view
      |> element("#dictionary-search-modal-wrapper")
      |> render_hook("close_search", %{})

      refute render(view) =~ "modal-open"
    end

    test "search shows results from dictionary", %{
      conn: conn,
      google: google,
      wiktionary: wiktionary,
      languagetool: languagetool
    } do
      user = AccountsFixtures.user_fixture()

      Accounts.upsert_user_preference(user, %{
        target_language: "spanish",
        native_language: "en"
      })

      # Mock the API responses
      Req.Test.stub(google, fn conn ->
        Req.Test.json(conn, %{
          "sentences" => [%{"trans" => "to speak"}],
          "dict" => [
            %{
              "pos" => "verb",
              "entry" => [
                %{"word" => "to speak", "reverse_translation" => ["hablar"]}
              ]
            }
          ]
        })
      end)

      Req.Test.stub(wiktionary, fn conn ->
        Req.Test.text(conn, "<html><body>No content</body></html>")
      end)

      Req.Test.stub(languagetool, fn conn ->
        Req.Test.json(conn, %{
          "matches" => [
            %{
              "replacements" => [%{"value" => "hablar"}],
              "rule" => %{"id" => "MORFOLOGIK_RULE_ES", "category" => %{"id" => "VERB"}}
            }
          ]
        })
      end)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/articles")

      # Open the modal
      view
      |> element("#dictionary-search-modal-wrapper")
      |> render_hook("open_search", %{})

      # Submit a search
      view
      |> form("#dictionary-search-form", %{"query" => "hablar"})
      |> render_submit()

      html = render(view)

      # Should show results
      assert html =~ "dictionary-result"
      assert html =~ "hablar"
      assert html =~ "to speak"
    end

    test "shows already studying badge for words user is already studying", %{
      conn: conn,
      google: google,
      wiktionary: wiktionary,
      languagetool: languagetool
    } do
      user = AccountsFixtures.user_fixture()

      Accounts.upsert_user_preference(user, %{
        target_language: "spanish",
        native_language: "en"
      })

      # Create a word that the user is already studying
      word =
        VocabularyFixtures.word_fixture(%{
          normalized_form: "comer",
          lemma: "comer",
          language: "spanish",
          part_of_speech: "verb"
        })

      StudyFixtures.fsrs_item_fixture(%{user: user, word: word})

      # Mock the API responses to return the same word
      Req.Test.stub(google, fn conn ->
        Req.Test.json(conn, %{
          "sentences" => [%{"trans" => "to eat"}],
          "dict" => [
            %{
              "pos" => "verb",
              "entry" => [%{"word" => "to eat", "reverse_translation" => ["comer"]}]
            }
          ]
        })
      end)

      Req.Test.stub(wiktionary, fn conn ->
        Req.Test.text(conn, "<html><body>No content</body></html>")
      end)

      Req.Test.stub(languagetool, fn conn ->
        Req.Test.json(conn, %{
          "matches" => [
            %{
              "replacements" => [%{"value" => "comer"}],
              "rule" => %{"id" => "MORFOLOGIK_RULE_ES", "category" => %{"id" => "VERB"}}
            }
          ]
        })
      end)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/articles")

      # Open modal and search
      view
      |> element("#dictionary-search-modal-wrapper")
      |> render_hook("open_search", %{})

      view
      |> form("#dictionary-search-form", %{"query" => "comer"})
      |> render_submit()

      html = render(view)

      # Should show "Already Studying" badge instead of "Add to Study" button
      assert html =~ "already-studying-badge"
      refute html =~ "add-to-study-btn"
    end

    test "add to study creates word and study item", %{
      conn: conn,
      google: google,
      wiktionary: wiktionary,
      languagetool: languagetool
    } do
      user = AccountsFixtures.user_fixture()

      Accounts.upsert_user_preference(user, %{
        target_language: "spanish",
        native_language: "en"
      })

      # Mock the API responses
      Req.Test.stub(google, fn conn ->
        Req.Test.json(conn, %{
          "sentences" => [%{"trans" => "to run"}],
          "dict" => [
            %{
              "pos" => "verb",
              "entry" => [%{"word" => "to run", "reverse_translation" => ["correr"]}]
            }
          ]
        })
      end)

      Req.Test.stub(wiktionary, fn conn ->
        Req.Test.text(conn, "<html><body>No content</body></html>")
      end)

      Req.Test.stub(languagetool, fn conn ->
        Req.Test.json(conn, %{
          "matches" => [
            %{
              "replacements" => [%{"value" => "correr"}],
              "rule" => %{"id" => "MORFOLOGIK_RULE_ES", "category" => %{"id" => "VERB"}}
            }
          ]
        })
      end)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/articles")

      # Open modal and search
      view
      |> element("#dictionary-search-modal-wrapper")
      |> render_hook("open_search", %{})

      view
      |> form("#dictionary-search-form", %{"query" => "correr"})
      |> render_submit()

      # Should show add to study button
      assert has_element?(view, "#add-to-study-btn")

      # Click add to study
      view
      |> element("#add-to-study-btn")
      |> render_click()

      html = render(view)

      # Should show "Added to Study" badge
      assert html =~ "study-added-badge"
      assert html =~ "Added to Study"

      # Verify the word was created in the database
      word = Vocabulary.get_word_by_normalized_form("correr", "spanish")
      assert word != nil

      # Verify the study item was created
      item = Study.get_item_by_user_and_word(user.id, word.id)
      assert item != nil
    end

    test "empty search shows error", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/articles")

      # Open modal
      view
      |> element("#dictionary-search-modal-wrapper")
      |> render_hook("open_search", %{})

      # Submit empty search
      view
      |> form("#dictionary-search-form", %{"query" => ""})
      |> render_submit()

      html = render(view)

      # Should show error
      assert html =~ "Please enter a word to search"
    end
  end
end
