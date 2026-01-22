defmodule Langler.Audio.Storage do
  @moduledoc """
  Behaviour for audio file storage backends.
  """

  @doc """
  Stores an audio file and returns the public path.
  """
  @callback store(integer(), integer(), binary()) :: {:ok, String.t()} | {:error, term()}

  @doc """
  Gets the public URL for an audio file.
  """
  @callback public_url(String.t()) :: String.t()

  @doc """
  Deletes an audio file.
  """
  @callback delete(String.t()) :: :ok | {:error, term()}
end
