defmodule Langler.TTS.ServiceTest do
  use Langler.DataCase, async: true

  import Langler.AccountsFixtures
  import Langler.ContentFixtures

  alias Langler.Audio
  alias Langler.TTS.Service

  describe "generate_audio/2" do
    test "creates pending audio file when none exists" do
      user = user_fixture()
      article = article_fixture()

      # Will fail due to no TTS config, but should create audio file
      Service.generate_audio(user.id, article.id)

      audio_file = Audio.get_audio_file(user.id, article.id)
      assert audio_file
      assert audio_file.status in ["pending", "failed"]
    end

    test "returns existing ready audio file without regenerating" do
      user = user_fixture()
      article = article_fixture()

      # Create a ready audio file
      {:ok, _audio_file} = Audio.get_or_create_audio_file(user.id, article.id)

      {:ok, audio_file} =
        Audio.mark_ready(user.id, article.id, "/audio/test.wav", 1024, 120.0)

      # Should return immediately without trying to regenerate
      assert {:ok, returned} = Service.generate_audio(user.id, article.id)
      assert returned.id == audio_file.id
      assert returned.status == "ready"
    end

    test "retries generation for failed audio file" do
      user = user_fixture()
      article = article_fixture()

      # Create a failed audio file
      {:ok, _audio_file} = Audio.get_or_create_audio_file(user.id, article.id)
      {:ok, _} = Audio.mark_failed(user.id, article.id, "Previous failure")

      # Should attempt to regenerate (will fail due to no config)
      result = Service.generate_audio(user.id, article.id)

      # Should have attempted generation
      assert match?({:error, _}, result)

      # Audio file should still be in failed state
      audio_file = Audio.get_audio_file(user.id, article.id)
      assert audio_file.status == "failed"
    end
  end
end
