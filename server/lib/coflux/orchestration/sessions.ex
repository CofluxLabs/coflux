defmodule Coflux.Orchestration.Sessions do
  alias Coflux.Orchestration.TagSets

  import Coflux.Store

  def start_session(db, environment_id, provides, launch_id) do
    with_transaction(db, fn ->
      case generate_external_id(db, :sessions, 30) do
        {:ok, external_id} ->
          provides_tag_set_id =
            if provides && Enum.any?(provides) do
              case TagSets.get_or_create_tag_set_id(db, provides) do
                {:ok, tag_set_id} ->
                  tag_set_id
              end
            end

          case insert_one(db, :sessions, %{
                 external_id: external_id,
                 environment_id: environment_id,
                 launch_id: launch_id,
                 provides_tag_set_id: provides_tag_set_id,
                 created_at: current_timestamp()
               }) do
            {:ok, session_id} ->
              {:ok, session_id, external_id}
          end
      end
    end)
  end

  defp current_timestamp() do
    System.os_time(:millisecond)
  end
end
