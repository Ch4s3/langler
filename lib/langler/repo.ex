defmodule Langler.Repo do
  @moduledoc """
  Ecto repository for Langler.
  """

  use Ecto.Repo,
    otp_app: :langler,
    adapter: Ecto.Adapters.Postgres
end
