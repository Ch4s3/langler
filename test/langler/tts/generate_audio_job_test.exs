defmodule Langler.TTS.GenerateAudioJobTest do
  use Langler.DataCase, async: true
  use Oban.Testing, repo: Langler.Repo

  import Langler.AccountsFixtures
  import Langler.ContentFixtures

  alias Langler.TTS.GenerateAudioJob

  describe "perform/1" do
    test "creates job with correct args" do
      user = user_fixture()
      article = article_fixture()

      # Create job changeset
      job =
        GenerateAudioJob.new(%{
          user_id: user.id,
          article_id: article.id
        })

      # Verify it's a valid changeset with correct structure
      assert job.valid?
      assert job.changes.worker == "Langler.TTS.GenerateAudioJob"
      assert job.changes.args.user_id == user.id
      assert job.changes.args.article_id == article.id
    end

    test "job has correct worker configuration" do
      # Verify the worker is configured properly
      assert GenerateAudioJob.__opts__()[:queue] == :default
      assert GenerateAudioJob.__opts__()[:max_attempts] == 3
    end
  end
end
