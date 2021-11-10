defmodule Coflux.Repo do
  defmodule Projects do
    use Ecto.Repo,
      otp_app: :coflux,
      adapter: Ecto.Adapters.Postgres
  end
end
