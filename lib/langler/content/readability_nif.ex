defmodule Langler.Content.ReadabilityNif do
  @moduledoc false

  # Only use Rustler if cargo is available at compile time
  # The library may still be available at runtime even if cargo isn't in PATH
  if System.find_executable("cargo") do
    use Rustler,
      otp_app: :langler,
      crate: "readability_nif",
      path: "native/readability_nif",
      mode: if(Mix.env() == :prod, do: :release, else: :debug)

    # When the NIF is loaded, this will be replaced by the actual NIF function
    def parse(_html, _base_url), do: :erlang.nif_error(:nif_not_loaded)
  else
    # Fallback when cargo is not available at compile time
    # Try to load the NIF manually if it exists
    @on_load :load_nif
    require Logger

    def load_nif do
      # On macOS, the library is .dylib, on Linux it's .so
      base_path =
        :code.priv_dir(:langler) |> Path.join("native/libreadability_nif") |> to_string()

      extensions = [".dylib", ".so"]

      extensions
      |> Enum.find_value(&load_extension(base_path, &1))
      |> case do
        nil -> :ok
        other -> other
      end
    end

    def parse(_html, _base_url), do: :erlang.nif_error(:nif_not_loaded)

    defp load_extension(base_path, extension) do
      nif_path = base_path <> extension

      if File.exists?(nif_path) do
        do_load_nif(base_path, nif_path)
      end
    end

    defp do_load_nif(base_path, nif_path) do
      case :erlang.load_nif(String.to_charlist(base_path), 0) do
        :ok ->
          Logger.info("[ReadabilityNif] Successfully loaded NIF from #{nif_path}")
          :ok

        {:error, reason} ->
          Logger.warning(
            "[ReadabilityNif] Failed to load NIF from #{nif_path}: #{inspect(reason)}"
          )

          nil
      end
    end
  end
end
