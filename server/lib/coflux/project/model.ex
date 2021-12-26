defmodule Coflux.Project.Model do
  defmacro __using__(_) do
    quote do
      use Ecto.Schema

      alias Coflux.Project.Models
      alias Coflux.Project.Models.Types
    end
  end
end
