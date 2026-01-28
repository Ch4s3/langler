defmodule Langler.ContentTest do
  use Langler.DataCase, async: true

  import Langler.ContentFixtures

  alias Langler.AccountsFixtures
  alias Langler.Content

  test "create_article/1 inserts an article and associates user" do
    user = AccountsFixtures.user_fixture()

    {:ok, article} =
      Content.create_article(%{
        title: "Hola",
        url: "https://example.com/#{System.unique_integer()}",
        language: "spanish"
      })

    assert article.title == "Hola"

    {:ok, article_user} = Content.ensure_article_user(article, user.id)
    assert article_user.user_id == user.id
  end

  test "list_articles_for_user/1 returns scoped articles" do
    user = AccountsFixtures.user_fixture()

    {:ok, article} =
      Content.create_article(%{
        title: "Scoped",
        url: "https://example.com/#{System.unique_integer()}",
        language: "spanish"
      })

    {:ok, _} = Content.ensure_article_user(article, user.id)
    article_id = article.id

    assert [%Content.Article{id: ^article_id}] = Content.list_articles_for_user(user.id)
  end

  test "create_sentence/1 stores sentence for article" do
    user = AccountsFixtures.user_fixture()

    {:ok, article} =
      Content.create_article(%{
        title: "Sentences",
        url: "https://example.com/#{System.unique_integer()}",
        language: "spanish"
      })

    {:ok, _} = Content.ensure_article_user(article, user.id)

    {:ok, sentence} =
      Content.create_sentence(%{
        position: 0,
        content: "Hola mundo.",
        article_id: article.id
      })

    assert sentence.article_id == article.id

    [fetched] = Content.list_sentences(article)
    assert fetched.id == sentence.id
    assert fetched.article_id == article.id
    assert fetched.content == "Hola mundo."
  end

  describe "finished article state" do
    test "ArticleUser changeset accepts finished status" do
      user = AccountsFixtures.user_fixture()

      {:ok, article} =
        Content.create_article(%{
          title: "Test Article",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      {:ok, article_user} =
        Content.ensure_article_user(article, user.id, %{status: "finished"})

      assert article_user.status == "finished"
    end

    test "ArticleUser changeset rejects invalid status" do
      user = AccountsFixtures.user_fixture()

      {:ok, article} =
        Content.create_article(%{
          title: "Test Article",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      changeset =
        Content.ArticleUser.changeset(%Content.ArticleUser{}, %{
          status: "invalid_status",
          article_id: article.id,
          user_id: user.id
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "list_articles_for_user excludes finished articles" do
      user = AccountsFixtures.user_fixture()

      {:ok, article1} =
        Content.create_article(%{
          title: "Article 1",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      {:ok, article2} =
        Content.create_article(%{
          title: "Article 2",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      {:ok, article3} =
        Content.create_article(%{
          title: "Article 3",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      Content.ensure_article_user(article1, user.id, %{status: "imported"})
      Content.ensure_article_user(article2, user.id, %{status: "imported"})
      Content.ensure_article_user(article3, user.id, %{status: "finished"})

      articles = Content.list_articles_for_user(user.id)
      article_ids = Enum.map(articles, & &1.id)

      assert article1.id in article_ids
      assert article2.id in article_ids
      refute article3.id in article_ids
    end

    test "list_articles_for_user excludes both archived and finished" do
      user = AccountsFixtures.user_fixture()

      {:ok, article1} =
        Content.create_article(%{
          title: "Article 1",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      {:ok, article2} =
        Content.create_article(%{
          title: "Article 2",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      {:ok, article3} =
        Content.create_article(%{
          title: "Article 3",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      Content.ensure_article_user(article1, user.id, %{status: "imported"})
      Content.ensure_article_user(article2, user.id, %{status: "archived"})
      Content.ensure_article_user(article3, user.id, %{status: "finished"})

      articles = Content.list_articles_for_user(user.id)
      assert length(articles) == 1
      assert hd(articles).id == article1.id
    end

    test "list_finished_articles_for_user returns only finished articles" do
      user = AccountsFixtures.user_fixture()

      {:ok, article1} =
        Content.create_article(%{
          title: "Article 1",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      {:ok, article2} =
        Content.create_article(%{
          title: "Article 2",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      {:ok, article3} =
        Content.create_article(%{
          title: "Article 3",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      Content.ensure_article_user(article1, user.id, %{status: "imported"})
      Content.ensure_article_user(article2, user.id, %{status: "finished"})
      Content.ensure_article_user(article3, user.id, %{status: "finished"})

      finished = Content.list_finished_articles_for_user(user.id)
      finished_ids = Enum.map(finished, & &1.id)

      refute article1.id in finished_ids
      assert article2.id in finished_ids
      assert article3.id in finished_ids
    end

    test "list_archived_articles_for_user excludes finished articles" do
      user = AccountsFixtures.user_fixture()

      {:ok, article1} =
        Content.create_article(%{
          title: "Article 1",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      {:ok, article2} =
        Content.create_article(%{
          title: "Article 2",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      Content.ensure_article_user(article1, user.id, %{status: "archived"})
      Content.ensure_article_user(article2, user.id, %{status: "finished"})

      archived = Content.list_archived_articles_for_user(user.id)
      assert length(archived) == 1
      assert hd(archived).id == article1.id
    end

    test "finish_article_for_user sets status to finished" do
      user = AccountsFixtures.user_fixture()

      {:ok, article} =
        Content.create_article(%{
          title: "Test Article",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      Content.ensure_article_user(article, user.id, %{status: "imported"})

      assert {:ok, article_user} = Content.finish_article_for_user(user.id, article.id)
      assert article_user.status == "finished"
    end

    test "finish_article_for_user returns error for non-existent article_user" do
      user = AccountsFixtures.user_fixture()

      {:ok, article} =
        Content.create_article(%{
          title: "Test Article",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      assert {:error, :not_found} = Content.finish_article_for_user(user.id, article.id)
    end

    test "restore_article_for_user works for finished articles" do
      user = AccountsFixtures.user_fixture()

      {:ok, article} =
        Content.create_article(%{
          title: "Test Article",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      Content.ensure_article_user(article, user.id, %{status: "finished"})

      assert {:ok, article_user} = Content.restore_article_for_user(user.id, article.id)
      assert article_user.status == "imported"
    end

    test "restore_article_for_user works for archived articles" do
      user = AccountsFixtures.user_fixture()

      {:ok, article} =
        Content.create_article(%{
          title: "Test Article",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      Content.ensure_article_user(article, user.id, %{status: "archived"})

      assert {:ok, article_user} = Content.restore_article_for_user(user.id, article.id)
      assert article_user.status == "imported"
    end

    test "get_article_for_user! works for finished articles" do
      user = AccountsFixtures.user_fixture()

      {:ok, article} =
        Content.create_article(%{
          title: "Test Article",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      Content.ensure_article_user(article, user.id, %{status: "finished"})

      # Should not raise
      retrieved = Content.get_article_for_user!(user.id, article.id)
      assert retrieved.id == article.id
    end
  end

  describe "article archiving" do
    test "archive_article_for_user/2 sets status to archived" do
      user = AccountsFixtures.user_fixture()

      {:ok, article} =
        Content.create_article(%{
          title: "Test Article",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      Content.ensure_article_user(article, user.id, %{status: "imported"})

      assert {:ok, article_user} = Content.archive_article_for_user(user.id, article.id)
      assert article_user.status == "archived"
    end

    test "archive_article_for_user/2 returns error for non-existent article_user" do
      user = AccountsFixtures.user_fixture()

      {:ok, article} =
        Content.create_article(%{
          title: "Test Article",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      assert {:error, :not_found} = Content.archive_article_for_user(user.id, article.id)
    end
  end

  describe "article topics" do
    test "tag_article/2 tags article with topics" do
      {:ok, article} =
        Content.create_article(%{
          title: "Science Article",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      assert :ok = Content.tag_article(article, [{"ciencia", 0.9}, {"tecnología", 0.7}])
      topics = Content.list_topics_for_article(article.id)
      assert length(topics) == 2
    end

    test "tag_article/2 replaces existing topics" do
      {:ok, article} =
        Content.create_article(%{
          title: "Science Article",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      Content.tag_article(article, [{"ciencia", 0.9}])
      Content.tag_article(article, [{"política", 0.8}])

      topics = Content.list_topics_for_article(article.id)
      assert length(topics) == 1
      assert hd(topics).topic == "política"
    end

    test "get_articles_by_topic/2 returns articles with topic" do
      user = AccountsFixtures.user_fixture()

      {:ok, article} =
        Content.create_article(%{
          title: "Science Article",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      Content.ensure_article_user(article, user.id)
      Content.tag_article(article, [{"ciencia", 0.9}])

      articles = Content.get_articles_by_topic("ciencia", user.id)
      assert Enum.any?(articles, &(&1.id == article.id))
    end

    test "get_user_topics/1 returns unique topics for user" do
      user = AccountsFixtures.user_fixture()

      {:ok, article1} =
        Content.create_article(%{
          title: "Article 1",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      {:ok, article2} =
        Content.create_article(%{
          title: "Article 2",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      Content.ensure_article_user(article1, user.id)
      Content.ensure_article_user(article2, user.id)

      Content.tag_article(article1, [{"ciencia", 0.9}])
      Content.tag_article(article2, [{"ciencia", 0.8}, {"política", 0.7}])

      topics = Content.get_user_topics(user.id)
      assert "ciencia" in topics
      assert "política" in topics
    end
  end

  describe "article deletion" do
    test "delete_article_for_user/2 deletes article_user" do
      user = AccountsFixtures.user_fixture()

      {:ok, article} =
        Content.create_article(%{
          title: "Test Article",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      Content.ensure_article_user(article, user.id)

      assert {:ok, :ok} = Content.delete_article_for_user(user.id, article.id)
    end

    test "delete_article_for_user/2 deletes article when no users left" do
      user = AccountsFixtures.user_fixture()

      {:ok, article} =
        Content.create_article(%{
          title: "Test Article",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      Content.ensure_article_user(article, user.id)

      assert {:ok, :ok} = Content.delete_article_for_user(user.id, article.id)

      assert_raise Ecto.NoResultsError, fn ->
        Content.get_article!(article.id)
      end
    end
  end

  describe "source sites" do
    test "list_source_sites/0 returns all sites" do
      {:ok, site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish",
          is_active: true
        })

      sites = Content.list_source_sites()
      assert Enum.any?(sites, &(&1.id == site.id))
    end

    test "list_active_source_sites/0 returns only active sites" do
      {:ok, active_site} =
        Content.create_source_site(%{
          name: "Active",
          url: "https://active.com",
          discovery_method: "rss",
          language: "spanish",
          is_active: true
        })

      {:ok, _inactive_site} =
        Content.create_source_site(%{
          name: "Inactive",
          url: "https://inactive.com",
          discovery_method: "rss",
          language: "spanish",
          is_active: false
        })

      active_sites = Content.list_active_source_sites()
      assert Enum.any?(active_sites, &(&1.id == active_site.id))
      assert Enum.all?(active_sites, & &1.is_active)
    end

    test "mark_source_checked/3 updates last_checked_at" do
      {:ok, site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish"
        })

      {:ok, updated} = Content.mark_source_checked(site, "etag123", "last-modified")
      assert updated.last_checked_at != nil
      assert updated.etag == "etag123"
    end

    test "mark_source_error/2 sets error fields" do
      {:ok, site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish"
        })

      {:ok, updated} = Content.mark_source_error(site, "Error message")
      assert updated.last_error == "Error message"
      assert updated.last_error_at != nil
    end

    test "get_source_site!/1 returns site" do
      {:ok, site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish"
        })

      found = Content.get_source_site!(site.id)
      assert found.id == site.id
    end

    test "get_source_site/1 returns site or nil" do
      {:ok, site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish"
        })

      assert Content.get_source_site(site.id).id == site.id
      assert Content.get_source_site(-1) == nil
    end

    test "update_source_site/2 updates site" do
      {:ok, site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish"
        })

      {:ok, updated} = Content.update_source_site(site, %{name: "Updated Site"})
      assert updated.name == "Updated Site"
    end

    test "delete_source_site/1 deletes site" do
      {:ok, site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish"
        })

      {:ok, _} = Content.delete_source_site(site)
      assert Content.get_source_site(site.id) == nil
    end
  end

  describe "discovered articles" do
    test "get_discovered_article!/1 returns discovered article" do
      {:ok, source_site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish"
        })

      {count, _} =
        Content.upsert_discovered_articles(source_site.id, [
          %{
            url: "https://example.com/article1",
            title: "Test Article",
            summary: "Test summary"
          }
        ])

      assert count == 1

      discovered = Content.get_discovered_article_by_url("https://example.com/article1")
      found = Content.get_discovered_article!(discovered.id)
      assert found.title == "Test Article"
    end

    test "get_discovered_article/1 returns discovered article or nil" do
      {:ok, source_site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish"
        })

      {count, _} =
        Content.upsert_discovered_articles(source_site.id, [
          %{
            url: "https://example.com/article1",
            title: "Test Article"
          }
        ])

      assert count == 1

      discovered = Content.get_discovered_article_by_url("https://example.com/article1")
      id = discovered.id
      assert Content.get_discovered_article(id).id == id
      assert Content.get_discovered_article(-1) == nil
    end

    test "get_discovered_article_by_url/1 returns discovered article" do
      {:ok, source_site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish"
        })

      url = "https://example.com/article1"

      {count, _} =
        Content.upsert_discovered_articles(source_site.id, [
          %{
            url: url,
            title: "Test Article"
          }
        ])

      assert count == 1
      found = Content.get_discovered_article_by_url(url)
      assert found.url == url
    end

    test "update_discovered_article/2 updates discovered article" do
      {:ok, source_site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish"
        })

      {count, _} =
        Content.upsert_discovered_articles(source_site.id, [
          %{
            url: "https://example.com/article1",
            title: "Original Title"
          }
        ])

      assert count == 1

      article = Content.get_discovered_article_by_url("https://example.com/article1")

      {:ok, updated} =
        Content.update_discovered_article(article, %{title: "Updated Title"})

      assert updated.title == "Updated Title"
    end
  end

  describe "article queries" do
    test "get_article_by_url/1 returns article by URL" do
      url = "https://example.com/#{System.unique_integer()}"

      {:ok, article} =
        Content.create_article(%{
          title: "Test",
          url: url,
          language: "spanish"
        })

      found = Content.get_article_by_url(url)
      assert found.id == article.id
    end

    test "get_article_by_url/1 returns nil when not found" do
      assert Content.get_article_by_url("https://nonexistent.com") == nil
    end

    test "list_articles/0 returns all articles" do
      {:ok, article1} =
        Content.create_article(%{
          title: "Article 1",
          url: "https://example.com/1",
          language: "spanish"
        })

      {:ok, article2} =
        Content.create_article(%{
          title: "Article 2",
          url: "https://example.com/2",
          language: "spanish"
        })

      articles = Content.list_articles()
      article_ids = Enum.map(articles, & &1.id)

      assert article1.id in article_ids
      assert article2.id in article_ids
    end

    test "update_article/2 updates article" do
      {:ok, article} =
        Content.create_article(%{
          title: "Original",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      {:ok, updated} = Content.update_article(article, %{title: "Updated"})
      assert updated.title == "Updated"
    end

    test "change_article/2 returns changeset" do
      {:ok, article} =
        Content.create_article(%{
          title: "Test",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      changeset = Content.change_article(article, %{title: "Changed"})
      assert changeset.changes.title == "Changed"
    end

    test "score_article_for_user/2 scores article based on topics" do
      user = AccountsFixtures.user_fixture()

      {:ok, article} =
        Content.create_article(%{
          title: "Science Article",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      Content.ensure_article_user(article, user.id)
      Langler.Accounts.set_user_topic_preference(user.id, "ciencia", 1.5)
      Content.tag_article(article, [{"ciencia", 0.9}])

      score = Content.score_article_for_user(article, user.id)
      assert is_float(score)
      assert score > 0.0
    end

    test "calculate_article_difficulty/1 calculates and stores difficulty" do
      {:ok, article} =
        Content.create_article(%{
          title: "Test Article",
          url: "https://example.com/#{System.unique_integer()}",
          language: "spanish"
        })

      Content.calculate_article_difficulty(article.id)

      updated = Content.get_article!(article.id)
      assert updated.difficulty_score != nil
    end
  end

  describe "discovered article users" do
    test "get_or_create_discovered_article_user/3 creates new user association" do
      user = AccountsFixtures.user_fixture()

      {:ok, source_site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish"
        })

      {count, _} =
        Content.upsert_discovered_articles(source_site.id, [
          %{
            url: "https://example.com/article1",
            title: "Test Article"
          }
        ])

      assert count == 1

      article = Content.get_discovered_article_by_url("https://example.com/article1")

      {:ok, dau} =
        Content.get_or_create_discovered_article_user(article.id, user.id, %{
          status: "recommended"
        })

      assert dau.user_id == user.id
      assert dau.discovered_article_id == article.id
    end

    test "get_or_create_discovered_article_user/3 returns existing association" do
      user = AccountsFixtures.user_fixture()

      {:ok, source_site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish"
        })

      {count, _} =
        Content.upsert_discovered_articles(source_site.id, [
          %{
            url: "https://example.com/article1",
            title: "Test Article"
          }
        ])

      assert count == 1

      article = Content.get_discovered_article_by_url("https://example.com/article1")

      {:ok, _} = Content.get_or_create_discovered_article_user(article.id, user.id)
      {:ok, existing} = Content.get_or_create_discovered_article_user(article.id, user.id)

      assert existing.user_id == user.id
    end

    test "mark_discovered_article_imported/2 marks as imported" do
      user = AccountsFixtures.user_fixture()

      {:ok, source_site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish"
        })

      {count, _} =
        Content.upsert_discovered_articles(source_site.id, [
          %{
            url: "https://example.com/article1",
            title: "Test Article"
          }
        ])

      assert count == 1

      article = Content.get_discovered_article_by_url("https://example.com/article1")

      {:ok, dau} = Content.mark_discovered_article_imported(article.id, user.id)
      assert dau.status == "imported"
      assert dau.imported_at != nil
    end

    test "mark_discovered_article_dismissed/2 marks as dismissed" do
      user = AccountsFixtures.user_fixture()

      {:ok, source_site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish"
        })

      {count, _} =
        Content.upsert_discovered_articles(source_site.id, [
          %{
            url: "https://example.com/article1",
            title: "Test Article"
          }
        ])

      assert count == 1

      article = Content.get_discovered_article_by_url("https://example.com/article1")

      {:ok, dau} = Content.mark_discovered_article_dismissed(article.id, user.id)
      assert dau.status == "dismissed"
    end

    test "update_discovered_article_user/2 updates association" do
      user = AccountsFixtures.user_fixture()

      {:ok, source_site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish"
        })

      {count, _} =
        Content.upsert_discovered_articles(source_site.id, [
          %{
            url: "https://example.com/article1",
            title: "Test Article"
          }
        ])

      assert count == 1

      article = Content.get_discovered_article_by_url("https://example.com/article1")

      {:ok, dau} = Content.get_or_create_discovered_article_user(article.id, user.id)
      {:ok, updated} = Content.update_discovered_article_user(dau, %{status: "dismissed"})

      assert updated.status == "dismissed"
    end
  end

  describe "get_recommended_articles/2" do
    test "ensures source diversity in recommendations" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()

      # Create articles from different sources
      article1 =
        article_fixture(%{
          user: other_user,
          title: "Article 1",
          source: "BBC Mundo",
          url: "https://www.bbc.com/article1"
        })

      article2 =
        article_fixture(%{
          user: other_user,
          title: "Article 2",
          source: "El País",
          url: "https://elpais.com/article2"
        })

      article3 =
        article_fixture(%{
          user: other_user,
          title: "Article 3",
          source: "BBC Mundo",
          url: "https://www.bbc.com/article3"
        })

      article4 =
        article_fixture(%{
          user: other_user,
          title: "Article 4",
          source: "El País",
          url: "https://elpais.com/article4"
        })

      # Tag articles with topics
      Content.tag_article(article1, [{"cultura", 0.8}])
      Content.tag_article(article2, [{"cultura", 0.8}])
      Content.tag_article(article3, [{"cultura", 0.8}])
      Content.tag_article(article4, [{"cultura", 0.8}])

      Langler.Accounts.set_user_topic_preference(user.id, "cultura", 1.5)

      # Get recommendations (limit 3)
      recommendations = Content.get_recommended_articles(user.id, 3)

      assert length(recommendations) <= 3

      # Extract sources from recommendations
      sources = Enum.map(recommendations, & &1.source) |> Enum.uniq()

      # Should have multiple sources (not all from one source)
      assert length(sources) > 1
    end

    test "filters out sports articles when user has no preference" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()

      # Create a sports article
      sports_article =
        article_fixture(%{
          user: other_user,
          title: "Harden lleva a Clippers a vencer 121-117 a Raptors",
          source: "AP News",
          url: "https://apnews.com/sports"
        })

      # Create a non-sports article
      culture_article =
        article_fixture(%{
          user: other_user,
          title: "Arte y cultura en la ciudad",
          source: "El País",
          url: "https://elpais.com/culture"
        })

      Content.tag_article(sports_article, [{"deportes", 0.9}])
      Content.tag_article(culture_article, [{"cultura", 0.9}])

      # User has no topic preferences
      recommendations = Content.get_recommended_articles(user.id, 10)

      # Sports article should be filtered out (scored too low)
      sports_urls = Enum.filter(recommendations, &(&1.url == sports_article.url))
      assert Enum.empty?(sports_urls)
    end

    test "includes sports articles when user has sports preference" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()

      # Create a sports article
      sports_article =
        article_fixture(%{
          user: other_user,
          title: "Harden lleva a Clippers a vencer 121-117 a Raptors",
          source: "AP News",
          url: "https://apnews.com/sports"
        })

      Content.tag_article(sports_article, [{"deportes", 0.9}])

      # User has sports preference
      Langler.Accounts.set_user_topic_preference(user.id, "deportes", 1.5)

      recommendations = Content.get_recommended_articles(user.id, 10)

      # Sports article should be included
      sports_urls = Enum.filter(recommendations, &(&1.url == sports_article.url))
      assert length(sports_urls) > 0
    end

    test "filters discovered articles by topic classification" do
      user = AccountsFixtures.user_fixture()

      {:ok, source_site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          discovery_method: "rss",
          language: "spanish"
        })

      # Create discovered articles
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, sports_discovered} =
        %Langler.Content.DiscoveredArticle{}
        |> Langler.Content.DiscoveredArticle.changeset(%{
          source_site_id: source_site.id,
          url: "https://example.com/sports",
          title: "Harden lleva a Clippers a vencer 121-117 a Raptors",
          summary: "El jugador anotó 31 puntos en tiempo extra.",
          language: "spanish",
          status: "new",
          discovered_at: now
        })
        |> Langler.Repo.insert()

      {:ok, culture_discovered} =
        %Langler.Content.DiscoveredArticle{}
        |> Langler.Content.DiscoveredArticle.changeset(%{
          source_site_id: source_site.id,
          url: "https://example.com/culture",
          title: "Arte y cultura en la ciudad",
          summary: "Exposición de arte moderno en el museo.",
          language: "spanish",
          status: "new",
          discovered_at: now
        })
        |> Langler.Repo.insert()

      # Mark as recommended for user
      Content.get_or_create_discovered_article_user(sports_discovered.id, user.id, %{
        status: "recommended"
      })

      Content.get_or_create_discovered_article_user(culture_discovered.id, user.id, %{
        status: "recommended"
      })

      # User has no topic preferences
      recommendations = Content.get_recommended_articles(user.id, 10)

      # Sports discovered article should be filtered out
      sports_urls = Enum.filter(recommendations, &(&1.url == sports_discovered.url))
      assert Enum.empty?(sports_urls)
    end
  end

  describe "list_articles_for_user/2 with search" do
    test "filters articles by title search query" do
      user = AccountsFixtures.user_fixture()

      article1 =
        article_fixture(%{
          title: "Learning Spanish Grammar",
          url: "https://example.com/grammar"
        })

      article2 =
        article_fixture(%{
          title: "Advanced Vocabulary Tips",
          url: "https://example.com/vocab"
        })

      article3 =
        article_fixture(%{
          title: "Spanish Food Culture",
          url: "https://example.com/food"
        })

      # Associate all articles with user
      Content.ensure_article_user(article1, user.id)
      Content.ensure_article_user(article2, user.id)
      Content.ensure_article_user(article3, user.id)

      # Search for "spanish"
      results = Content.list_articles_for_user(user.id, query: "spanish")
      result_ids = Enum.map(results, & &1.id)

      assert article1.id in result_ids
      assert article3.id in result_ids
      refute article2.id in result_ids
    end

    test "filters articles by URL search query" do
      user = AccountsFixtures.user_fixture()

      article1 =
        article_fixture(%{
          title: "Test Article 1",
          url: "https://example.com/spanish-grammar"
        })

      article2 =
        article_fixture(%{
          title: "Test Article 2",
          url: "https://example.com/french-grammar"
        })

      Content.ensure_article_user(article1, user.id)
      Content.ensure_article_user(article2, user.id)

      # Search by URL pattern
      results = Content.list_articles_for_user(user.id, query: "spanish")
      result_ids = Enum.map(results, & &1.id)

      assert article1.id in result_ids
      refute article2.id in result_ids
    end

    test "filters articles by source search query" do
      user = AccountsFixtures.user_fixture()

      article1 =
        article_fixture(%{
          title: "Article 1",
          source: "El País",
          url: "https://example.com/1"
        })

      article2 =
        article_fixture(%{
          title: "Article 2",
          source: "BBC News",
          url: "https://example.com/2"
        })

      Content.ensure_article_user(article1, user.id)
      Content.ensure_article_user(article2, user.id)

      # Search by source
      results = Content.list_articles_for_user(user.id, query: "país")
      result_ids = Enum.map(results, & &1.id)

      assert article1.id in result_ids
      refute article2.id in result_ids
    end

    test "returns empty list when search query matches nothing" do
      user = AccountsFixtures.user_fixture()

      article =
        article_fixture(%{
          title: "Spanish Grammar",
          url: "https://example.com/test"
        })

      Content.ensure_article_user(article, user.id)

      results = Content.list_articles_for_user(user.id, query: "nonexistentquery")
      assert results == []
    end

    test "trims whitespace from search query" do
      user = AccountsFixtures.user_fixture()

      article =
        article_fixture(%{
          title: "Spanish Grammar",
          url: "https://example.com/test"
        })

      Content.ensure_article_user(article, user.id)

      # Query with extra whitespace
      results = Content.list_articles_for_user(user.id, query: "  spanish  ")
      assert length(results) == 1
      assert hd(results).id == article.id
    end

    test "treats empty string query as nil" do
      user = AccountsFixtures.user_fixture()

      article1 = article_fixture(%{title: "Article 1"})
      article2 = article_fixture(%{title: "Article 2"})

      Content.ensure_article_user(article1, user.id)
      Content.ensure_article_user(article2, user.id)

      # Empty string should return all articles
      results = Content.list_articles_for_user(user.id, query: "")
      assert length(results) == 2
    end

    test "search is case insensitive" do
      user = AccountsFixtures.user_fixture()

      article =
        article_fixture(%{
          title: "Spanish Grammar Basics",
          url: "https://example.com/test"
        })

      Content.ensure_article_user(article, user.id)

      # Search with different cases
      results_lower = Content.list_articles_for_user(user.id, query: "spanish")
      results_upper = Content.list_articles_for_user(user.id, query: "SPANISH")
      results_mixed = Content.list_articles_for_user(user.id, query: "SpAnIsH")

      assert length(results_lower) == 1
      assert length(results_upper) == 1
      assert length(results_mixed) == 1
    end
  end

  describe "list_articles_for_user/2 with topic filter" do
    test "filters articles by topic" do
      user = AccountsFixtures.user_fixture()

      # Create articles
      article1 = article_fixture(%{title: "Sports News"})
      article2 = article_fixture(%{title: "Tech News"})
      article3 = article_fixture(%{title: "More Sports"})

      # Associate with user
      Content.ensure_article_user(article1, user.id)
      Content.ensure_article_user(article2, user.id)
      Content.ensure_article_user(article3, user.id)

      # Tag articles with topics
      Content.tag_article(article1, [{"sports", 0.9}])
      Content.tag_article(article2, [{"technology", 0.9}])
      Content.tag_article(article3, [{"sports", 0.8}])

      # Filter by sports topic
      results = Content.list_articles_for_user(user.id, topic: "sports")
      result_ids = Enum.map(results, & &1.id)

      assert article1.id in result_ids
      assert article3.id in result_ids
      refute article2.id in result_ids
    end

    test "returns empty list when topic has no matching articles" do
      user = AccountsFixtures.user_fixture()

      article = article_fixture(%{title: "Tech Article"})
      Content.ensure_article_user(article, user.id)
      Content.tag_article(article, [{"technology", 0.9}])

      results = Content.list_articles_for_user(user.id, topic: "sports")
      assert results == []
    end

    test "returns all articles when topic is empty string" do
      user = AccountsFixtures.user_fixture()

      article1 = article_fixture(%{title: "Article 1"})
      article2 = article_fixture(%{title: "Article 2"})

      Content.ensure_article_user(article1, user.id)
      Content.ensure_article_user(article2, user.id)

      # Empty string topic should not filter
      results = Content.list_articles_for_user(user.id, topic: "")
      assert length(results) == 2
    end

    test "returns all articles when topic is nil" do
      user = AccountsFixtures.user_fixture()

      article1 = article_fixture(%{title: "Article 1"})
      article2 = article_fixture(%{title: "Article 2"})

      Content.ensure_article_user(article1, user.id)
      Content.ensure_article_user(article2, user.id)

      # Nil topic should not filter
      results = Content.list_articles_for_user(user.id, topic: nil)
      assert length(results) == 2
    end
  end

  describe "list_articles_for_user/2 with combined filters" do
    test "applies both search and topic filters together" do
      user = AccountsFixtures.user_fixture()

      article1 = article_fixture(%{title: "Spanish Sports News"})
      article2 = article_fixture(%{title: "Spanish Tech News"})
      article3 = article_fixture(%{title: "French Sports News"})

      Content.ensure_article_user(article1, user.id)
      Content.ensure_article_user(article2, user.id)
      Content.ensure_article_user(article3, user.id)

      Content.tag_article(article1, [{"sports", 0.9}])
      Content.tag_article(article2, [{"technology", 0.9}])
      Content.tag_article(article3, [{"sports", 0.9}])

      # Filter by both topic and search query
      results = Content.list_articles_for_user(user.id, topic: "sports", query: "spanish")

      assert length(results) == 1
      assert hd(results).id == article1.id
    end
  end

  describe "list_topics_for_article/1" do
    test "returns empty list for nil article_id" do
      assert Content.list_topics_for_article(nil) == []
    end

    test "returns topics ordered by confidence desc" do
      article = article_fixture()

      Content.tag_article(article, [
        {"sports", 0.9},
        {"culture", 0.5},
        {"politics", 0.7}
      ])

      topics = Content.list_topics_for_article(article.id)
      confidences = Enum.map(topics, fn t -> Decimal.to_float(t.confidence) end)

      assert confidences == Enum.sort(confidences, :desc)
      assert List.first(topics).topic == "sports"
    end
  end

  describe "get_articles_by_topic/2" do
    test "excludes archived articles" do
      user = AccountsFixtures.user_fixture()

      article1 = article_fixture(%{title: "Sports 1"})
      article2 = article_fixture(%{title: "Sports 2"})

      Content.ensure_article_user(article1, user.id)
      Content.ensure_article_user(article2, user.id)

      # Archive one article
      Content.archive_article_for_user(user.id, article2.id)

      Content.tag_article(article1, [{"sports", 0.9}])
      Content.tag_article(article2, [{"sports", 0.9}])

      results = Content.get_articles_by_topic("sports", user.id)
      result_ids = Enum.map(results, & &1.id)

      assert article1.id in result_ids
      refute article2.id in result_ids
    end

    test "preloads article_topics" do
      user = AccountsFixtures.user_fixture()

      article = article_fixture()
      Content.ensure_article_user(article, user.id)
      Content.tag_article(article, [{"sports", 0.9}])

      [result] = Content.get_articles_by_topic("sports", user.id)

      assert Ecto.assoc_loaded?(result.article_topics)
      assert length(result.article_topics) == 1
    end
  end

  describe "list_archived_articles_for_user/1" do
    test "only returns archived articles" do
      user = AccountsFixtures.user_fixture()

      article1 = article_fixture(%{title: "Active Article"})
      article2 = article_fixture(%{title: "Archived Article"})

      Content.ensure_article_user(article1, user.id)
      Content.ensure_article_user(article2, user.id)

      Content.archive_article_for_user(user.id, article2.id)

      archived = Content.list_archived_articles_for_user(user.id)
      archived_ids = Enum.map(archived, & &1.id)

      refute article1.id in archived_ids
      assert article2.id in archived_ids
    end
  end

  describe "list_finished_articles_for_user/1" do
    test "preloads article_topics" do
      user = AccountsFixtures.user_fixture()

      article = article_fixture()
      Content.ensure_article_user(article, user.id)
      Content.tag_article(article, [{"sports", 0.9}])
      Content.finish_article_for_user(user.id, article.id)

      [result] = Content.list_finished_articles_for_user(user.id)

      assert Ecto.assoc_loaded?(result.article_topics)
      assert length(result.article_topics) == 1
    end
  end

  describe "get_article_by_url/1" do
    test "returns article when URL matches" do
      article = article_fixture(%{url: "https://example.com/test"})

      result = Content.get_article_by_url("https://example.com/test")

      assert result.id == article.id
    end

    test "returns nil when URL doesn't match" do
      article_fixture(%{url: "https://example.com/test"})

      result = Content.get_article_by_url("https://example.com/other")

      assert result == nil
    end
  end

  describe "get_article_for_user/2" do
    test "returns article when user has access" do
      user = AccountsFixtures.user_fixture()
      article = article_fixture()

      Content.ensure_article_user(article, user.id)

      result = Content.get_article_for_user(user.id, article.id)

      assert result.id == article.id
    end

    test "returns nil when user doesn't have access" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      article = article_fixture()

      Content.ensure_article_user(article, other_user.id)

      result = Content.get_article_for_user(user.id, article.id)

      assert result == nil
    end
  end

  describe "restore_article_for_user/2" do
    test "returns error when article_user doesn't exist" do
      user = AccountsFixtures.user_fixture()
      article = article_fixture()

      # Don't create article_user association

      assert {:error, :not_found} = Content.restore_article_for_user(user.id, article.id)
    end
  end

  describe "get_discovered_article_by_url/1" do
    test "returns discovered article when URL matches" do
      {:ok, source_site} =
        Content.create_source_site(%{
          name: "Test Site",
          url: "https://example.com",
          feed_url: "https://example.com/feed",
          language: "spanish",
          discovery_method: "rss"
        })

      Content.upsert_discovered_articles(source_site.id, [
        %{url: "https://example.com/article1", title: "Test"}
      ])

      result = Content.get_discovered_article_by_url("https://example.com/article1")

      assert result.url == "https://example.com/article1"
    end

    test "returns nil when URL doesn't match" do
      result = Content.get_discovered_article_by_url("https://nonexistent.com/test")

      assert result == nil
    end
  end
end
