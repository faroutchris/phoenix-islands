defmodule SelfService.Repo do
  use Ecto.Repo,
    otp_app: :selfservice_test,
    adapter: Ecto.Adapters.SQLite3
end
