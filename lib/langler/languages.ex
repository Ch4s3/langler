defmodule Langler.Languages do
  @moduledoc """
  Central authority for supported languages, canonical codes, and external service mappings.
  """

  @supported_languages %{
    "es" => %{
      name: "Spanish",
      native_name: "Español",
      gettext: "es",
      external: %{
        language_tool: "es",
        translate: "es",
        tts_voice: "es-ES-Standard-A"
      }
    },
    "fr" => %{
      name: "French",
      native_name: "Français",
      gettext: "fr",
      external: %{
        language_tool: "fr",
        translate: "fr",
        tts_voice: "fr-FR-Standard-A"
      }
    },
    "it" => %{
      name: "Italian",
      native_name: "Italiano",
      gettext: "it",
      external: %{
        language_tool: "it",
        translate: "it",
        tts_voice: "it-IT-Standard-A"
      }
    },
    "ro" => %{
      name: "Romanian",
      native_name: "Română",
      gettext: "ro",
      external: %{
        language_tool: "ro",
        translate: "ro",
        tts_voice: "ro-RO-Standard-A"
      }
    },
    "ca" => %{
      name: "Catalan",
      native_name: "Català",
      gettext: "ca",
      external: %{
        language_tool: "ca",
        translate: "ca",
        tts_voice: "ca-ES-Standard-A"
      }
    },
    "pt-BR" => %{
      name: "Portuguese (Brazil)",
      native_name: "Português (Brasil)",
      gettext: "pt_BR",
      external: %{
        language_tool: "pt-BR",
        translate: "pt",
        tts_voice: "pt-BR-Standard-A"
      }
    },
    "pt-PT" => %{
      name: "Portuguese (Portugal)",
      native_name: "Português (Portugal)",
      gettext: "pt_PT",
      external: %{
        language_tool: "pt-PT",
        translate: "pt",
        tts_voice: "pt-PT-Standard-A"
      }
    },
    "en" => %{
      name: "English",
      native_name: "English",
      gettext: "en",
      external: %{
        language_tool: "en",
        translate: "en",
        tts_voice: "en-US-Standard-A"
      }
    }
  }

  @doc """
  Returns the map of all supported languages.
  """
  def supported_languages, do: @supported_languages

  @doc """
  Returns a list of all supported language codes.
  """
  def supported_codes, do: Map.keys(@supported_languages)

  @doc """
  Returns a list of study language codes (excludes English which is primarily for UI/native).
  """
  def study_language_codes do
    ["es", "fr", "it", "ro", "ca", "pt-BR", "pt-PT"]
  end

  @doc """
  Checks if a language code is supported.

  ## Examples

      iex> Langler.Languages.supported?("es")
      true

      iex> Langler.Languages.supported?("de")
      false
  """
  def supported?(code) when is_binary(code) do
    normalized = normalize(code)
    Map.has_key?(@supported_languages, normalized)
  end

  def supported?(_), do: false

  @doc """
  Normalizes a language code to canonical format.
  Accepts common variants and returns the canonical code.

  ## Examples

      iex> Langler.Languages.normalize("pt_BR")
      "pt-BR"

      iex> Langler.Languages.normalize("pt-br")
      "pt-BR"

      iex> Langler.Languages.normalize("ES")
      "es"
  """
  def normalize(code) when is_binary(code) do
    code
    |> String.downcase()
    |> case do
      "pt_br" -> "pt-BR"
      "pt-br" -> "pt-BR"
      "pt_pt" -> "pt-PT"
      "pt-pt" -> "pt-PT"
      other -> other
    end
  end

  def normalize(_), do: nil

  @doc """
  Normalizes a language code and raises if not supported.

  ## Examples

      iex> Langler.Languages.normalize!("es")
      "es"

      iex> Langler.Languages.normalize!("invalid")
      ** (ArgumentError) Unsupported language code: invalid
  """
  def normalize!(code) do
    normalized = normalize(code)

    if supported?(normalized) do
      normalized
    else
      raise ArgumentError, "Unsupported language code: #{inspect(code)}"
    end
  end

  @doc """
  Returns the display name for a language code in English.

  ## Examples

      iex> Langler.Languages.display_name("es")
      "Spanish"

      iex> Langler.Languages.display_name("pt-BR")
      "Portuguese (Brazil)"
  """
  def display_name(code) do
    code
    |> normalize()
    |> then(&get_in(@supported_languages, [&1, :name]))
  end

  @doc """
  Returns the native name for a language code.

  ## Examples

      iex> Langler.Languages.native_name("es")
      "Español"

      iex> Langler.Languages.native_name("pt-BR")
      "Português (Brasil)"
  """
  def native_name(code) do
    code
    |> normalize()
    |> then(&get_in(@supported_languages, [&1, :native_name]))
  end

  @doc """
  Returns the Gettext locale for a language code.

  ## Examples

      iex> Langler.Languages.gettext_locale("pt-BR")
      "pt_BR"

      iex> Langler.Languages.gettext_locale("es")
      "es"
  """
  def gettext_locale(code) do
    code
    |> normalize()
    |> then(&get_in(@supported_languages, [&1, :gettext]))
  end

  @doc """
  Returns the external service code for a given service.

  ## Examples

      iex> Langler.Languages.external_code("es", :translate)
      "es"

      iex> Langler.Languages.external_code("pt-BR", :translate)
      "pt"
  """
  def external_code(code, service) when service in [:language_tool, :translate, :tts_voice] do
    code
    |> normalize()
    |> then(&get_in(@supported_languages, [&1, :external, service]))
  end

  @doc """
  Returns the TTS voice ID for a language code.

  ## Examples

      iex> Langler.Languages.tts_voice("fr")
      "fr-FR-Standard-A"
  """
  def tts_voice(code) do
    external_code(code, :tts_voice)
  end

  @doc """
  Converts a language code to the format expected by LanguageTool.
  """
  def to_language_tool_code(code) do
    external_code(code, :language_tool)
  end

  @doc """
  Converts a language code to the format expected by Google Translate.
  """
  def to_translate_code(code) do
    external_code(code, :translate)
  end
end
