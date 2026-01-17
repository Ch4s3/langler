defmodule Langler.Chat.EncryptionTest do
  use ExUnit.Case, async: false

  alias Langler.Chat.Encryption

  setup do
    original = Application.get_env(:langler, LanglerWeb.Endpoint)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:langler, LanglerWeb.Endpoint)
      else
        Application.put_env(:langler, LanglerWeb.Endpoint, original)
      end
    end)

    :ok
  end

  test "encrypts and decrypts messages with the same user id" do
    user_id = 123
    plaintext = "secret message"

    assert {:ok, encrypted} = Encryption.encrypt_message(user_id, plaintext)
    assert is_binary(encrypted)
    refute encrypted == plaintext

    assert {:ok, decrypted} = Encryption.decrypt_message(user_id, encrypted)
    assert decrypted == plaintext
  end

  test "rejects decryption with the wrong user id" do
    assert {:ok, encrypted} = Encryption.encrypt_message(1, "hello")

    assert {:error, :decryption_failed} = Encryption.decrypt_message(2, encrypted)
  end

  test "hash_content is deterministic and user-specific" do
    hash_a = Encryption.hash_content(1, "content")
    hash_b = Encryption.hash_content(1, "content")
    hash_c = Encryption.hash_content(2, "content")

    assert hash_a == hash_b
    refute hash_a == hash_c
  end

  test "returns an error when secret_key_base is missing" do
    Application.put_env(:langler, LanglerWeb.Endpoint, [])

    assert {:error, {:encryption_failed, _}} = Encryption.encrypt_message(1, "secret")
  end
end
