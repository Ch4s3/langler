defmodule Langler.Audio.Storage.LocalTest do
  use ExUnit.Case, async: true

  alias Langler.Audio.Storage.Local

  @test_audio_binary <<1, 2, 3, 4, 5>>
  @test_base_path "priv/static/audio"

  setup do
    # Clean up test files before and after each test
    on_exit(fn -> cleanup_test_files() end)
    :ok
  end

  describe "store/3" do
    test "stores audio file to local filesystem" do
      user_id = 123
      article_id = 456

      assert {:ok, public_path} = Local.store(user_id, article_id, @test_audio_binary)

      assert public_path == "/audio/123/456.wav"

      # Verify file was actually written
      full_path = Path.join([@test_base_path, "123", "456.wav"])
      assert File.exists?(full_path)
      assert File.read!(full_path) == @test_audio_binary
    end

    test "creates directory structure if it doesn't exist" do
      user_id = 999
      article_id = 888

      # Ensure directory doesn't exist
      dir_path = Path.join(@test_base_path, "999")
      File.rm_rf(dir_path)
      refute File.exists?(dir_path)

      assert {:ok, _public_path} = Local.store(user_id, article_id, @test_audio_binary)

      assert File.exists?(dir_path)
    end

    test "overwrites existing file" do
      user_id = 111
      article_id = 222

      {:ok, _} = Local.store(user_id, article_id, @test_audio_binary)
      new_binary = <<9, 8, 7, 6, 5>>
      {:ok, _} = Local.store(user_id, article_id, new_binary)

      full_path = Path.join([@test_base_path, "111", "222.wav"])
      assert File.read!(full_path) == new_binary
    end

    test "stores files for different users separately" do
      article_id = 123

      {:ok, path1} = Local.store(100, article_id, @test_audio_binary)
      {:ok, path2} = Local.store(200, article_id, @test_audio_binary)

      assert path1 == "/audio/100/123.wav"
      assert path2 == "/audio/200/123.wav"

      assert File.exists?(Path.join(@test_base_path, "100/123.wav"))
      assert File.exists?(Path.join(@test_base_path, "200/123.wav"))
    end
  end

  describe "public_url/1" do
    test "returns the file path as-is" do
      assert Local.public_url("/audio/123/456.wav") == "/audio/123/456.wav"
    end

    test "works with any path format" do
      assert Local.public_url("custom/path/file.wav") == "custom/path/file.wav"
    end
  end

  describe "delete/1" do
    test "deletes existing file" do
      user_id = 333
      article_id = 444

      {:ok, public_path} = Local.store(user_id, article_id, @test_audio_binary)
      full_path = Path.join("priv/static", String.trim_leading(public_path, "/"))

      assert File.exists?(full_path)

      assert :ok = Local.delete(public_path)

      refute File.exists?(full_path)
    end

    test "returns :ok when file doesn't exist" do
      assert :ok = Local.delete("/audio/nonexistent/file.wav")
    end

    test "handles paths with and without leading slash" do
      user_id = 555
      article_id = 666

      {:ok, public_path} = Local.store(user_id, article_id, @test_audio_binary)

      # Test with leading slash
      assert :ok = Local.delete(public_path)

      # Store again and test without leading slash
      {:ok, _} = Local.store(user_id, article_id, @test_audio_binary)
      path_without_slash = String.trim_leading(public_path, "/")
      assert :ok = Local.delete(path_without_slash)
    end
  end

  defp cleanup_test_files do
    # Clean up test audio files
    test_dirs = [
      Path.join(@test_base_path, "123"),
      Path.join(@test_base_path, "456"),
      Path.join(@test_base_path, "999"),
      Path.join(@test_base_path, "888"),
      Path.join(@test_base_path, "111"),
      Path.join(@test_base_path, "222"),
      Path.join(@test_base_path, "100"),
      Path.join(@test_base_path, "200"),
      Path.join(@test_base_path, "333"),
      Path.join(@test_base_path, "444"),
      Path.join(@test_base_path, "555"),
      Path.join(@test_base_path, "666")
    ]

    Enum.each(test_dirs, &File.rm_rf/1)
  end
end
