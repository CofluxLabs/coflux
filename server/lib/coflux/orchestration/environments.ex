defmodule Coflux.Orchestration.Environments do
  alias Coflux.Orchestration.TagSets

  import Coflux.Store

  def get_all_environments(db) do
    case query(
           db,
           """
           SELECT
             e.id,
             (SELECT es.status
               FROM environment_statuses AS es
               WHERE es.environment_id = e.id
               ORDER BY es.created_at DESC
               LIMIT 1) AS status,
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
          Enum.reduce(rows, %{}, fn {environment_id, status, name, base_id}, result ->
            {:ok, pools} = get_environment_pools(db, environment_id)

            Map.put(result, environment_id, %{
              name: name,
              base_id: base_id,
              pools: pools,
              status: status
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
             (SELECT es.status
               FROM environment_statuses AS es
               WHERE es.environment_id = e.id
               ORDER BY es.created_at DESC
               LIMIT 1) AS status,
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
         Enum.any?(rows, fn {status, name} ->
           name == environment_name && status != 1
         end)}
    end
  end

  defp has_active_child_environments?(db, environment_id) do
    # TODO: neater way to do this?
    case query(
           db,
           """
           SELECT
             (SELECT es.status
               FROM environment_statuses AS es
               WHERE es.environment_id = e.id
               ORDER BY es.created_at DESC
               LIMIT 1) AS status,
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
         Enum.any?(rows, fn {status, base_id} ->
           base_id == environment_id && status != 1
         end)}
    end
  end

  # TODO: change to 'get_active_environment_by_id'?
  defp get_environment_by_id(db, environment_id) do
    case query_one(
           db,
           """
           SELECT
             (SELECT es.status
               FROM environment_statuses AS es
               WHERE es.environment_id = e.id
               ORDER BY es.created_at DESC
               LIMIT 1) AS status,
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
      {:ok, {status, name, base_id}} ->
        {:ok, %{status: status, name: name, base_id: base_id}}

      {:ok, nil} ->
        {:ok, nil}
    end
  end

  def create_environment(db, name, base_id, pools) do
    with_transaction(db, fn ->
      environment = %{
        status: 0,
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
        {:ok, _} = insert_environment_status(db, environment_id, environment.status, now)
        {:ok, _} = insert_environment_name(db, environment_id, environment.name, now)
        {:ok, _} = insert_environment_base(db, environment_id, environment.base_id, now)
        {:ok, pools} = insert_environment_pools(db, environment_id, environment.pools, now)
        environment = Map.put(environment, :pools, pools)
        {:ok, environment_id, environment}
      end
    end)
  end

  def update_environment(db, environment_id, updates) do
    with_transaction(db, fn ->
      case get_environment_by_id(db, environment_id) do
        {:ok, nil} ->
          {:error, :not_found}

        {:ok, %{status: 1}} ->
          {:error, :not_found}

        {:ok, environment} ->
          {:ok, existing_pools} = get_environment_pools(db, environment_id)
          environment = Map.put(environment, :pools, existing_pools)

          changes = extract_changes(environment, updates, [:name, :base_id, :pools])

          {changes, errors} =
            validate(
              changes,
              name: &validate_name(&1, db),
              base_id: &validate_base_id(&1, db, environment_id),
              pools: &validate_pools/1
            )

          if Enum.any?(errors) do
            {:error, errors}
          else
            now = current_timestamp()

            if Map.has_key?(changes, :name) do
              {:ok, _} = insert_environment_name(db, environment_id, changes.name, now)
            end

            if Map.has_key?(changes, :base_id) do
              {:ok, _} = insert_environment_base(db, environment_id, changes.base_id, now)
            end

            if Map.has_key?(changes, :pools) do
              {:ok, _} = insert_environment_pools(db, environment_id, changes.pools, now)
            end

            environment = Map.merge(environment, changes)
            {:ok, environment}
          end
      end
    end)
  end

  def archive_environment(db, environment_id) do
    with_transaction(db, fn ->
      case get_environment_by_id(db, environment_id) do
        {:ok, nil} ->
          {:error, :not_found}

        {:ok, %{status: 1}} ->
          {:error, :not_found}

        {:ok, environment} ->
          case has_active_child_environments?(db, environment_id) do
            {:ok, true} ->
              {:error, :descendants}

            {:ok, false} ->
              now = current_timestamp()
              {:ok, _} = insert_environment_status(db, environment_id, 1, now)
              {:ok, pools} = get_environment_pools(db, environment_id)

              environment =
                environment
                |> Map.put(:pools, pools)
                |> Map.put(:status, 1)

              {:ok, environment}
          end
      end
    end)
  end

  defp extract_changes(original, updates, fields) do
    Enum.reduce(fields, %{}, fn field, changes ->
      case Map.fetch(updates, field) do
        {:ok, value} ->
          if value != Map.fetch!(original, field) do
            Map.put(changes, field, value)
          else
            changes
          end

        :error ->
          changes
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
          if !base || base.status == 1 do
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

  defp validate(changes, validators) do
    Enum.reduce(validators, {changes, %{}}, fn {field, validator}, {changes, errors} ->
      if Map.has_key?(changes, field) do
        case validator.(Map.fetch!(changes, field)) do
          :ok ->
            {changes, errors}

          {:ok, value} ->
            changes = Map.put(changes, field, value)
            {changes, errors}

          {:error, error} ->
            {changes, Map.put(errors, field, error)}
        end
      else
        {changes, errors}
      end
    end)
  end

  defp hash_pool_definition(provides_tag_set_id, repositories, launcher) do
    # TODO: better hashing? (recursively sort launcher?)
    data =
      Enum.intersperse(
        [
          Integer.to_string(provides_tag_set_id),
          Enum.join(Enum.sort(repositories), "\n"),
          if(launcher, do: Atom.to_string(launcher.type), else: ""),
          if(launcher, do: Jason.encode!(Map.delete(launcher, :type)), else: "")
        ],
        0
      )

    :crypto.hash(:sha256, data)
  end

  defp get_or_create_pool_definition(db, pool) do
    repositories = Map.get(pool, :repositories, [])
    provides = Map.get(pool, :provides, %{})
    launcher = Map.get(pool, :launcher)

    provides_tag_set_id =
      if provides && Enum.any?(provides) do
        case TagSets.get_or_create_tag_set_id(db, provides) do
          {:ok, tag_set_id} -> tag_set_id
        end
      end

    hash = hash_pool_definition(provides_tag_set_id, repositories, launcher)

    case query_one(db, "SELECT id FROM pool_definitions WHERE hash = ?1", {hash}) do
      {:ok, {id}} ->
        {:ok, id}

      {:ok, nil} ->
        {:ok, pool_definition_id} =
          insert_one(db, :pool_definitions, %{
            hash: hash,
            provides_tag_set_id: provides_tag_set_id
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

        if launcher do
          launcher_type =
            case launcher.type do
              :docker -> 0
            end

          {:ok, _} =
            insert_one(db, :pool_definition_launchers, %{
              pool_definition_id: pool_definition_id,
              type: launcher_type,
              config: Jason.encode!(Map.delete(launcher, :type))
            })
        end

        {:ok, pool_definition_id}
    end
  end

  defp get_environment_pools(db, environment_id) do
    case query(
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
           WHERE p.environment_id = ?1
           """,
           {environment_id}
         ) do
      {:ok, rows} ->
        {:ok,
         Map.new(rows, fn {id, pool_name, pool_definition_id} ->
           provides =
             case query_one(
                    db,
                    "SELECT provides_tag_set_id FROM pool_definitions WHERE id = ?1",
                    {pool_definition_id}
                  ) do
               {:ok, {nil}} ->
                 %{}

               {:ok, {provides_tag_set_id}} ->
                 case TagSets.get_tag_set(db, provides_tag_set_id) do
                   {:ok, tag_set} ->
                     tag_set
                 end
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

           launcher =
             case query_one(
                    db,
                    """
                    SELECT type, config
                    FROM pool_definition_launchers
                    WHERE pool_definition_id = ?1
                    """,
                    {pool_definition_id}
                  ) do
               {:ok, {type, config}} ->
                 config = Jason.decode!(config, keys: :atoms)

                 case type do
                   0 -> Map.put(config, :type, :docker)
                 end

               {:ok, nil} ->
                 nil
             end

           {id,
            %{
              name: pool_name,
              provides: provides,
              repositories: repositories,
              launcher: launcher
            }}
         end)}
    end
  end

  defp insert_environment_status(db, environment_id, status, created_at) do
    insert_one(db, :environment_statuses, %{
      environment_id: environment_id,
      status: status,
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

  defp insert_environment_pools(db, environment_id, pools, created_at) do
    pools =
      Map.new(pools, fn {pool_name, pool} ->
        {:ok, pool_definition_id} = get_or_create_pool_definition(db, pool)

        {:ok, pool_id} =
          insert_one(db, :pools, %{
            environment_id: environment_id,
            name: pool_name,
            pool_definition_id: pool_definition_id,
            created_at: created_at
          })

        {pool_name, Map.put(pool, :id, pool_id)}
      end)

    {:ok, pools}
  end

  defp current_timestamp() do
    System.os_time(:millisecond)
  end
end
