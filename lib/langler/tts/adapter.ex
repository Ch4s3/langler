defmodule Langler.TTS.Adapter do
  @moduledoc """
  Behaviour for TTS (Text-to-Speech) adapters.
  """

  @doc """
  Generates audio from text.
  Returns audio binary, transcript, and metadata.
  """
  @callback generate_audio(text :: String.t(), config :: map()) ::
              {:ok, %{audio_binary: binary(), transcript: String.t(), metadata: map()}}
              | {:error, term()}
end
