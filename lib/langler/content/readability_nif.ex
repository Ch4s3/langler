defmodule Langler.Content.ReadabilityNif do
  @moduledoc false

  def parse(_html, _opts) do
    {:error, :nif_not_loaded}
  end
end
