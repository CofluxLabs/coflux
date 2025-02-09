defmodule Coflux.Orchestration.Environments do
  alias Coflux.Orchestration.TagSets

  import Coflux.Store

  def get_all_environments(db) do
    case query(
           db,
           """
           SELECT
             e.id,
             (SELECT es.state
               FROM environment_states AS es
               WHERE es.environment_id = e.id
               ORDER BY es.created_at DESC
               LIMIT 1) AS state,
             (SELECT en.name
               FROM environment_names AS en
               WHERE en.environment_id = e.id
               ORDER BY en.created_at DESC
               LIMIT 1) AS name,
             (SELECT eb.base_id
               FROM environment_bases AS eb
               WHERE eb.environment_id = e.id
               ORDER BY eb.created_at DESC
               LIMIT 1) AS base_id
           FROM environments AS e
           """
         ) do
      {:ok, rows} ->
        environments =
          Enum.reduce(rows, %{}, fn {environment_id, state, name, base_id}, result ->
            {:ok, pools} = get_environment_pools(db, environment_id)

            Map.put(result, environment_id, %{
              name: name,
              base_id: base_id,
              pools:
                Map.new(pools, fn {pool_id, pool_name, pool_definition_id} ->
                  {:ok, pool_definition} = get_pool_definition(db, pool_definition_id)
                  {pool_name, Map.put(pool_definition, :id, pool_id)}
                end),
              state: decode_state(state)
            })
          end)

        {:ok, environments}
    end
  end

  defp environment_name_used?(db, environment_name) do
    # TODO: neater way to do this?
    case query(
           db,
           """
           SELECT
             (SELECT es.state
               FROM environment_states AS es
               WHERE es.environment_id = e.id
               ORDER BY es.created_at DESC
               LIMIT 1) AS state,
             (SELECT en.name
               FROM environment_names AS en
               WHERE en.environment_id = e.id
               ORDER BY en.created_at DESC
               LIMIT 1) AS name
           FROM environments AS e
           """
         ) do
      {:ok, rows} ->
        {:ok,
         Enum.any?(rows, fn {state, name} ->
           name == environment_name && decode_state(state) != :archived
         end)}
    end
  end

  defp has_active_child_environments?(db, environment_id) do
    # TODO: neater way to do this?
    case query(
           db,
           """
           SELECT
             (SELECT es.state
               FROM environment_states AS es
               WHERE es.environment_id = e.id
               ORDER BY es.created_at DESC
               LIMIT 1) AS state,
             (SELECT eb.base_id
               FROM environment_bases AS eb
               WHERE eb.environment_id = e.id
               ORDER BY eb.created_at DESC
               LIMIT 1) AS base_id
           FROM environments AS e
           """
         ) do
      {:ok, rows} ->
        {:ok,
         Enum.any?(rows, fn {state, base_id} ->
           base_id == environment_id && decode_state(state) != :archived
         end)}
    end
  end

  # TODO: change to 'get_active_environment_by_id'?
  defp get_environment_by_id(db, environment_id) do
    case query_one(
           db,
           """
           SELECT
             (SELECT es.state
               FROM environment_states AS es
               WHERE es.environment_id = e.id
               ORDER BY es.created_at DESC
               LIMIT 1) AS state,
             (SELECT en.name
               FROM environment_names AS en
               WHERE en.environment_id = e.id
               ORDER BY en.created_at DESC
               LIMIT 1) AS name,
             (SELECT eb.base_id
               FROM environment_bases AS eb
               WHERE eb.environment_id = e.id
               ORDER BY eb.created_at DESC
               LIMIT 1) AS base_id
           FROM environments AS e
           WHERE e.id = ?1
           """,
           {environment_id}
         ) do
      {:ok, {state, name, base_id}} ->
        {:ok, %{state: decode_state(state), name: name, base_id: base_id}}

      {:ok, nil} ->
        {:ok, nil}
    end
  end

  def create_environment(db, name, base_id, pools) do
    with_transaction(db, fn ->
      environment = %{
        state: :active,
        name: name,
        base_id: base_id,
        pools: pools || %{}
      }

      {environment, errors} =
        validate(
          environment,
          name: &validate_name(&1, db),
          base_id: &validate_base_id(&1, db),
          pools: &validate_pools/1
        )

      if Enum.any?(errors) do
        {:error, errors}
      else
        now = current_timestamp()
        {:ok, environment_id} = insert_one(db, :environments, %{})
        {:ok, _} = insert_environment_state(db, environment_id, environment.state, now)
        {:ok, _} = insert_environment_name(db, environment_id, environment.name, now)
        {:ok, _} = insert_environment_base(db, environment_id, environment.base_id, now)

        Enum.each(environment.pools, fn {pool_name, pool} ->
          {:ok, pool_definition_id} = get_or_create_pool_definition(db, pool)

          {:ok, _} =
            insert_environment_pool(db, environment_id, pool_name, pool_definition_id, now)
        end)

        {:ok, environment_id, environment}
      end
    end)
  end

  def update_environment(db, environment_id, updates) do
    with_transaction(db, fn ->
      case get_environment_by_id(db, environment_id) do
        {:ok, nil} ->
          {:error, :not_found}

        {:ok, %{state: :archived}} ->
          {:error, :not_found}

        {:ok, environment} ->
          existing_pool_definition_ids =
            case get_environment_pools(db, environment_id) do
              {:ok, existing_pools} ->
                Map.new(existing_pools, fn {_, pool_name, pool_definition_id} ->
                  {pool_name, pool_definition_id}
                end)
            end

          {updates, errors} =
            validate(
              updates,
              name: &validate_name(&1, db),
              base_id: &validate_base_id(&1, db, environment_id),
              pools: &validate_pools/1
            )

          if Enum.any?(errors) do
            {:error, errors}
          else
            now = current_timestamp()

            if Map.has_key?(updates, :name) && updates.name != environment.name do
              {:ok, _} = insert_environment_name(db, environment_id, updates.name, now)
            end

            if Map.has_key?(updates, :base_id) && updates.base_id != environment.base_id do
              {:ok, _} = insert_environment_base(db, environment_id, updates.base_id, now)
            end

            {pools_updated, pools_removed} =
              if Map.has_key?(updates, :pools) do
                pools_updated =
                  Enum.reduce(
                    updates.pools,
                    MapSet.new(),
                    fn {pool_name, pool}, pools_updated ->
                      {:ok, pool_definition_id} = get_or_create_pool_definition(db, pool)

                      existing_pool_definition_id =
                        Map.get(existing_pool_definition_ids, pool_name)

                      if pool_definition_id != existing_pool_definition_id do
                        {:ok, _} =
                          insert_environment_pool(
                            db,
                            environment_id,
                            pool_name,
                            pool_definition_id,
                            now
                          )

                        MapSet.put(pools_updated, pool_name)
                      else
                        pools_updated
                      end
                    end
                  )

                pools_removed =
                  existing_pool_definition_ids
                  |> Map.keys()
                  |> Enum.reduce(
                    MapSet.new(),
                    fn pool_name, pools_removed ->
                      if !Map.has_key?(updates.pools, pool_name) do
                        {:ok, _} =
                          insert_environment_pool(db, environment_id, pool_name, nil, now)

                        MapSet.put(pools_removed, pool_name)
                      else
                        pools_removed
                      end
                    end
                  )

                {pools_updated, pools_removed}
              else
                {MapSet.new(), MapSet.new()}
              end

            # TODO: don't return environment - move this to separate function?
            {:ok, environment} = get_environment_by_id(db, environment_id)
            {:ok, existing_pools} = get_environment_pools(db, environment_id)

            environment =
              Map.put(
                environment,
                :pools,
                Map.new(existing_pools, fn {pool_id, pool_name, pool_definition_id} ->
                  {:ok, pool_definition} = get_pool_definition(db, pool_definition_id)
                  {pool_name, Map.put(pool_definition, :id, pool_id)}
                end)
              )

            {:ok, environment, pools_updated, pools_removed}
          end
      end
    end)
  end

  def pause_environment(db, environment_id) do
    with_transaction(db, fn ->
      case get_environment_by_id(db, environment_id) do
        {:ok, nil} ->
          {:error, :not_found}

        {:ok, %{state: :archived}} ->
          {:error, :not_found}

        {:ok, %{state: :active}} ->
          {:ok, _} = insert_environment_state(db, environment_id, :paused, current_timestamp())
          :ok

        {:ok, %{state: :paused}} ->
          :ok
      end
    end)
  end

  def resume_environment(db, environment_id) do
    with_transaction(db, fn ->
      case get_environment_by_id(db, environment_id) do
        {:ok, nil} ->
          {:error, :not_found}

        {:ok, %{state: :archived}} ->
          {:error, :not_found}

        {:ok, %{state: :paused}} ->
          {:ok, _} = insert_environment_state(db, environment_id, :active, current_timestamp())
          :ok

        {:ok, %{state: :active}} ->
          :ok
      end
    end)
  end

  def archive_environment(db, environment_id) do
    with_transaction(db, fn ->
      case get_environment_by_id(db, environment_id) do
        {:ok, nil} ->
          {:error, :not_found}

        {:ok, %{state: :archived}} ->
          {:error, :not_found}

        {:ok, _} ->
          case has_active_child_environments?(db, environment_id) do
            {:ok, true} ->
              {:error, :descendants}

            {:ok, false} ->
              {:ok, _} =
                insert_environment_state(db, environment_id, :archived, current_timestamp())

              :ok
          end
      end
    end)
  end

  defp is_valid_name?(name) do
    is_binary(name) && Regex.match?(~r/^[a-z0-9_-]+(\/[a-z0-9_-]+)*$/i, name)
  end

  defp validate_name(name, db) do
    if is_valid_name?(name) do
      case environment_name_used?(db, name) do
        {:ok, false} -> :ok
        {:ok, true} -> {:error, :exists}
      end
    else
      {:error, :invalid}
    end
  end

  defp get_ancestor_ids(db, environment_id, ancestor_ids \\ []) do
    case get_environment_by_id(db, environment_id) do
      {:ok, %{base_id: nil}} ->
        {:ok, ancestor_ids}

      {:ok, %{base_id: base_id}} ->
        get_ancestor_ids(db, base_id, [environment_id | ancestor_ids])
    end
  end

  defp validate_base_id(base_id, db, environment_id \\ nil) do
    if is_nil(base_id) do
      :ok
    else
      case get_environment_by_id(db, base_id) do
        {:ok, base} ->
          if !base || base.state == :archived do
            {:error, :invalid}
          else
            if environment_id do
              case get_ancestor_ids(db, base_id) do
                {:ok, ancestor_ids} ->
                  if environment_id in ancestor_ids do
                    {:error, :invalid}
                  else
                    :ok
                  end
              end
            else
              :ok
            end
          end
      end
    end
  end

  defp validate_pools(pools) do
    cond do
      is_nil(pools) ->
        :ok

      is_map(pools) ->
        # TODO: validate each
        :ok

      true ->
        {:error, :invalid}
    end
  end

  defp validate(updates, validators) do
    Enum.reduce(validators, {updates, %{}}, fn {field, validator}, {updates, errors} ->
      if Map.has_key?(updates, field) do
        case validator.(Map.fetch!(updates, field)) do
          :ok ->
            {updates, errors}

          {:ok, value} ->
            updates = Map.put(updates, field, value)
            {updates, errors}

          {:error, error} ->
            {updates, Map.put(errors, field, error)}
        end
      else
        {updates, errors}
      end
    end)
  end

  defp hash_launcher(type, config) do
    # TODO: better hashing? (recursively sort config)
    data = [Atom.to_string(type), 0, Jason.encode!(config)]
    :crypto.hash(:sha256, data)
  end

  defp get_or_create_launcher(db, launcher) do
    type = Map.fetch!(launcher, :type)
    config = Map.delete(launcher, :type)
    hash = hash_launcher(type, config)

    case query_one(db, "SELECT id FROM launchers WHERE hash = ?1", {hash}) do
      {:ok, {id}} ->
        {:ok, id}

      {:ok, nil} ->
        insert_one(db, :launchers, %{
          hash: hash,
          type: encode_launcher_type(type),
          config: Jason.encode!(config)
        })
    end
  end

  defp hash_pool_definition(launcher_id, provides_tag_set_id, repositories) do
    data =
      Enum.intersperse(
        [
          if(launcher_id, do: Integer.to_string(launcher_id), else: ""),
          Integer.to_string(provides_tag_set_id),
          Enum.join(Enum.sort(repositories), "\n")
        ],
        0
      )

    :crypto.hash(:sha256, data)
  end

  defp get_or_create_pool_definition(db, pool) do
    repositories = Map.get(pool, :repositories, [])
    provides = Map.get(pool, :provides, %{})
    launcher = Map.get(pool, :launcher)

    launcher_id =
      if launcher do
        case get_or_create_launcher(db, launcher) do
          {:ok, launcher_id} -> launcher_id
        end
      end

    provides_tag_set_id =
      if provides && Enum.any?(provides) do
        case TagSets.get_or_create_tag_set_id(db, provides) do
          {:ok, tag_set_id} -> tag_set_id
        end
      end

    hash = hash_pool_definition(launcher_id, provides_tag_set_id, repositories)

    case query_one(db, "SELECT id FROM pool_definitions WHERE hash = ?1", {hash}) do
      {:ok, {id}} ->
        {:ok, id}

      {:ok, nil} ->
        {:ok, pool_definition_id} =
          insert_one(db, :pool_definitions, %{
            hash: hash,
            provides_tag_set_id: provides_tag_set_id,
            launcher_id: launcher_id
          })

        {:ok, _} =
          insert_many(
            db,
            :pool_definition_repositories,
            {:pool_definition_id, :pattern},
            Enum.map(repositories, fn pattern ->
              {pool_definition_id, pattern}
            end)
          )

        {:ok, pool_definition_id}
    end
  end

  def get_launcher(db, launcher_id) do
    case query_one(db, "SELECT type, config FROM launchers WHERE id = ?1", {launcher_id}) do
      {:ok, {type, config}} ->
        config = Jason.decode!(config, keys: :atoms)
        type = decode_launcher_type(type)
        {:ok, Map.put(config, :type, type)}
    end
  end

  defp get_pool_definition(db, pool_definition_id) do
    case query_one(
           db,
           "SELECT launcher_id, provides_tag_set_id FROM pool_definitions WHERE id = ?1",
           {pool_definition_id}
         ) do
      {:ok, {launcher_id, provides_tag_set_id}} ->
        provides =
          if provides_tag_set_id do
            case TagSets.get_tag_set(db, provides_tag_set_id) do
              {:ok, tag_set} ->
                tag_set
            end
          else
            %{}
          end

        repositories =
          case query(
                 db,
                 """
                 SELECT pattern
                 FROM pool_definition_repositories
                 WHERE pool_definition_id = ?1
                 """,
                 {pool_definition_id}
               ) do
            {:ok, rows} -> Enum.map(rows, fn {pattern} -> pattern end)
          end

        {:ok,
         %{
           provides: provides,
           repositories: repositories,
           launcher_id: launcher_id
         }}

      {:ok, nil} ->
        {:error, :not_found}
    end
  end

  defp get_environment_pools(db, environment_id) do
    query(
      db,
      """
      SELECT p.id, p.name, p.pool_definition_id
      FROM pools AS p
      JOIN (
          SELECT name, MAX(created_at) AS created_at
          FROM pools
          WHERE environment_id = ?1
          GROUP BY name
      ) latest ON p.name = latest.name AND p.created_at = latest.created_at
      WHERE p.environment_id = ?1 AND p.pool_definition_id IS NOT NULL
      """,
      {environment_id}
    )
  end

  defp insert_environment_state(db, environment_id, state, created_at) do
    insert_one(db, :environment_states, %{
      environment_id: environment_id,
      state: encode_state(state),
      created_at: created_at
    })
  end

  defp insert_environment_name(db, environment_id, name, created_at) do
    insert_one(db, :environment_names, %{
      environment_id: environment_id,
      name: name,
      created_at: created_at
    })
  end

  defp insert_environment_base(db, environment_id, base_id, created_at) do
    insert_one(db, :environment_bases, %{
      environment_id: environment_id,
      base_id: base_id,
      created_at: created_at
    })
  end

  defp insert_environment_pool(db, environment_id, pool_name, pool_definition_id, created_at) do
    insert_one(db, :pools, %{
      environment_id: environment_id,
      name: pool_name,
      pool_definition_id: pool_definition_id,
      created_at: created_at
    })
  end

  defp encode_state(state) do
    case state do
      :active -> 0
      :paused -> 1
      :archived -> 2
    end
  end

  defp decode_state(value) do
    case value do
      0 -> :active
      1 -> :paused
      2 -> :archived
    end
  end

  defp encode_launcher_type(type) do
    case type do
      :docker -> 0
    end
  end

  defp decode_launcher_type(value) do
    case value do
      0 -> :docker
    end
  end

  defp current_timestamp() do
    System.os_time(:millisecond)
  end
end
