defmodule Coflux.Project.Model do
  defmacro __using__(_) do
    quote do
      use Ecto.Schema

      alias Coflux.Project.Models

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
    end
  end
end
