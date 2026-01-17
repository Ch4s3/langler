defmodule Langler.Content.ClassifierNif do
  @moduledoc """
  Rust NIF wrapper for ML classifier.
  """

  # Only use Rustler if cargo is available
  if System.find_executable("cargo") do
    use Rustler,
      otp_app: :langler,
      crate: "classifier_nif",
      path: "native/classifier_nif",
      mode: if(Mix.env() == :prod, do: :release, else: :debug)

    # When the NIF is loaded, this will be replaced by the actual NIF function
    def train(_training_data), do: :erlang.nif_error(:nif_not_loaded)
    def classify(_document, _model_json), do: :erlang.nif_error(:nif_not_loaded)
  else
    # Fallback when cargo is not available
    @on_load :load_nif
    require Logger

    def load_nif do
      nif_path = :code.priv_dir(:langler) |> Path.join("native/libclassifier_nif")
      # On macOS, NIFs are .dylib, on Linux it's .so
      lib_path =
        if System.type() == {:system, :darwin} do
          nif_path <> ".dylib"
        else
          nif_path <> ".so"
        end

      case :erlang.load_nif(String.to_charlist(lib_path), 0) do
        :ok ->
          Logger.info("[ClassifierNif] Successfully loaded NIF from #{lib_path}")
          :ok

        {:error, reason} ->
          Logger.warning(
            "[ClassifierNif] Failed to load NIF from #{lib_path}: #{inspect(reason)}"
          )

          :ok
      end
    end

    def train(_training_data), do: {:error, :nif_not_loaded}
    def classify(_document, _model_json), do: {:error, :nif_not_loaded}
  end
end
