defmodule Langler.Repo do
  use Ecto.Repo,
    otp_app: :langler,
    adapter: Ecto.Adapters.Postgres
end
