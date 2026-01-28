defmodule Langler.AudioTest do
  use Langler.DataCase, async: true

  import Langler.AccountsFixtures
  import Langler.ContentFixtures

  alias Langler.Audio

  describe "get_or_create_audio_file/2" do
    test "creates a new audio file record when none exists" do
      user = user_fixture()
      article = article_fixture()

      assert {:ok, audio_file} = Audio.get_or_create_audio_file(user.id, article.id)

      assert audio_file.user_id == user.id
      assert audio_file.article_id == article.id
      assert audio_file.status == "pending"
      assert is_nil(audio_file.file_path)
      assert is_nil(audio_file.file_size)
      assert is_nil(audio_file.duration_seconds)
      assert audio_file.last_position_seconds == 0.0
    end

    test "returns existing audio file when it already exists" do
      user = user_fixture()
      article = article_fixture()

      assert {:ok, first} = Audio.get_or_create_audio_file(user.id, article.id)
      assert {:ok, second} = Audio.get_or_create_audio_file(user.id, article.id)

      assert first.id == second.id
    end

    test "creates separate records for different users on same article" do
      user1 = user_fixture()
      user2 = user_fixture()
      article = article_fixture()

      assert {:ok, audio1} = Audio.get_or_create_audio_file(user1.id, article.id)
      assert {:ok, audio2} = Audio.get_or_create_audio_file(user2.id, article.id)

      assert audio1.id != audio2.id
      assert audio1.user_id == user1.id
      assert audio2.user_id == user2.id
    end

    test "creates separate records for same user on different articles" do
      user = user_fixture()
      article1 = article_fixture()
      article2 = article_fixture()

      assert {:ok, audio1} = Audio.get_or_create_audio_file(user.id, article1.id)
      assert {:ok, audio2} = Audio.get_or_create_audio_file(user.id, article2.id)

      assert audio1.id != audio2.id
      assert audio1.article_id == article1.id
      assert audio2.article_id == article2.id
    end
  end

  describe "get_audio_file/2" do
    test "returns audio file when it exists" do
      user = user_fixture()
      article = article_fixture()
      {:ok, created} = Audio.get_or_create_audio_file(user.id, article.id)

      result = Audio.get_audio_file(user.id, article.id)

      assert result.id == created.id
    end

    test "returns nil when audio file does not exist" do
      user = user_fixture()
      article = article_fixture()

      assert Audio.get_audio_file(user.id, article.id) == nil
    end
  end

  describe "mark_ready/5" do
    test "marks audio file as ready with metadata" do
      user = user_fixture()
      article = article_fixture()
      {:ok, _} = Audio.get_or_create_audio_file(user.id, article.id)

      assert {:ok, audio_file} =
               Audio.mark_ready(user.id, article.id, "/audio/test.wav", 1024, 120.5)

      assert audio_file.status == "ready"
      assert audio_file.file_path == "/audio/test.wav"
      assert audio_file.file_size == 1024
      assert audio_file.duration_seconds == 120.5
      assert is_nil(audio_file.error_message)
    end

    test "clears error_message when marking as ready" do
      user = user_fixture()
      article = article_fixture()
      {:ok, _} = Audio.get_or_create_audio_file(user.id, article.id)
      {:ok, _} = Audio.mark_failed(user.id, article.id, "Test error")

      assert {:ok, audio_file} =
               Audio.mark_ready(user.id, article.id, "/audio/test.wav", 1024, 120.5)

      assert is_nil(audio_file.error_message)
    end

    test "returns error when audio file does not exist" do
      user = user_fixture()
      article = article_fixture()

      assert {:error, :not_found} =
               Audio.mark_ready(user.id, article.id, "/audio/test.wav", 1024, 120.5)
    end
  end

  describe "mark_failed/3" do
    test "marks audio file as failed with error message" do
      user = user_fixture()
      article = article_fixture()
      {:ok, _} = Audio.get_or_create_audio_file(user.id, article.id)

      assert {:ok, audio_file} = Audio.mark_failed(user.id, article.id, "Generation failed")

      assert audio_file.status == "failed"
      assert audio_file.error_message == "Generation failed"
    end

    test "returns error when audio file does not exist" do
      user = user_fixture()
      article = article_fixture()

      assert {:error, :not_found} = Audio.mark_failed(user.id, article.id, "Error")
    end
  end

  describe "update_listening_position/3" do
    test "updates the listening position" do
      user = user_fixture()
      article = article_fixture()
      {:ok, _} = Audio.get_or_create_audio_file(user.id, article.id)

      assert {:ok, audio_file} = Audio.update_listening_position(user.id, article.id, 45.5)

      assert audio_file.last_position_seconds == 45.5
    end

    test "updates position multiple times" do
      user = user_fixture()
      article = article_fixture()
      {:ok, _} = Audio.get_or_create_audio_file(user.id, article.id)

      {:ok, _} = Audio.update_listening_position(user.id, article.id, 10.0)
      assert {:ok, audio_file} = Audio.update_listening_position(user.id, article.id, 30.0)

      assert audio_file.last_position_seconds == 30.0
    end

    test "accepts integer positions" do
      user = user_fixture()
      article = article_fixture()
      {:ok, _} = Audio.get_or_create_audio_file(user.id, article.id)

      assert {:ok, audio_file} = Audio.update_listening_position(user.id, article.id, 60)

      assert audio_file.last_position_seconds == 60
    end

    test "returns error when audio file does not exist" do
      user = user_fixture()
      article = article_fixture()

      assert {:error, :not_found} = Audio.update_listening_position(user.id, article.id, 45.5)
    end
  end
end
