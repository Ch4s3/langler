defmodule Langler.Chat.Encryption do
  @moduledoc """
  Encryption utilities for chat messages and API keys.

  Uses AES-256-GCM encryption with per-user keys derived from the application
  secret and user ID. This ensures that only the user can decrypt their own messages.
  """

  @aad "LanglerChatV1"

  @doc """
  Encrypts a message for storage.

  ## Parameters
    - `user_id`: The user's ID
    - `content`: The plaintext content to encrypt

  ## Returns
    - `{:ok, encrypted_binary}` on success
    - `{:error, reason}` on failure
  """
  @spec encrypt_message(integer(), String.t()) :: {:ok, binary()} | {:error, term()}
  def encrypt_message(user_id, content) when is_integer(user_id) and is_binary(content) do
    key = derive_key(user_id)
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, content, @aad, true)

    # Format: iv (12 bytes) || tag (16 bytes) || ciphertext
    encrypted = iv <> tag <> ciphertext

    {:ok, encrypted}
  rescue
    error ->
      {:error, {:encryption_failed, error}}
  end

  @doc """
  Decrypts a message for display.

  ## Parameters
    - `user_id`: The user's ID
    - `encrypted_content`: The encrypted binary

  ## Returns
    - `{:ok, plaintext}` on success
    - `{:error, reason}` on failure
  """
  @spec decrypt_message(integer(), binary()) :: {:ok, String.t()} | {:error, term()}
  def decrypt_message(user_id, encrypted_content)
      when is_integer(user_id) and is_binary(encrypted_content) do
    key = derive_key(user_id)

    # Extract iv (12 bytes), tag (16 bytes), and ciphertext
    <<iv::binary-size(12), tag::binary-size(16), ciphertext::binary>> = encrypted_content

    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false) do
      plaintext when is_binary(plaintext) ->
        {:ok, plaintext}

      :error ->
        {:error, :decryption_failed}
    end
  rescue
    error ->
      {:error, {:decryption_failed, error}}
  end

  @doc """
  Generates a keyed HMAC hash for content deduplication.

  ## Parameters
    - `user_id`: The user's ID
    - `content`: The content to hash

  ## Returns
    - A hex-encoded SHA256 HMAC hash
  """
  @spec hash_content(integer(), String.t()) :: String.t()
  def hash_content(user_id, content) when is_integer(user_id) and is_binary(content) do
    key = derive_key(user_id)

    :crypto.mac(:hmac, :sha256, key, content)
    |> Base.encode16(case: :lower)
  end

  # Derives a 32-byte encryption key from the application secret and user ID
  defp derive_key(user_id) do
    secret = get_secret_key_base()
    salt = "user_encryption_#{user_id}"

    :crypto.hash(:sha256, secret <> salt)
  end

  defp get_secret_key_base do
    case Application.get_env(:langler, LanglerWeb.Endpoint)[:secret_key_base] do
      nil ->
        raise "secret_key_base not configured"

      secret ->
        secret
    end
  end
end
