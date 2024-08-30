defmodule Coflux.Orchestration.Environments do
  import Coflux.Store

  def get_all_environments(db) do
    case query(
           db,
           """
           SELECT ev.environment_id, ev.name, ev.base_id, ev.status, ev.version
           FROM environment_versions AS ev
           JOIN (
             SELECT environment_id, MAX(version) AS max_version
             FROM environment_versions
             GROUP BY environment_id
           ) AS latest
           ON ev.environment_id = latest.environment_id AND ev.version = latest.max_version
           """
         ) do
      {:ok, rows} ->
        environments =
          Enum.reduce(rows, %{}, fn {environment_id, name, base_id, status, version}, result ->
            Map.put(result, environment_id, %{
              name: name,
              base_id: base_id,
              status: status,
              version: version
            })
          end)

        {:ok, environments}
    end
  end

  defp get_active_environment_by_name(db, environment_name) do
    case query_one(
           db,
           """
           SELECT ev.environment_id, ev.name, ev.base_id, ev.status, ev.version
           FROM environment_versions AS ev
           JOIN (
             SELECT environment_id, MAX(version) AS max_version
             FROM environment_versions
             GROUP BY environment_id
           ) AS latest
           ON ev.environment_id = latest.environment_id AND ev.version = latest.max_version
           WHERE ev.name = ?1 AND ev.status = 0
           """,
           {environment_name}
         ) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, {environment_id, name, base_id, status, version}} ->
        {:ok, environment_id,
         %{
           name: name,
           base_id: base_id,
           status: status,
           version: version
         }}
    end
  end

  defp has_active_child_environments?(db, environment_id) do
    case query(
           db,
           """
           SELECT 1
           FROM environment_versions AS ev
           JOIN (
            SELECT environment_id, MAX(version) AS max_version
            FROM environment_versions
            GROUP BY environment_id
           ) AS latest
           ON ev.environment_id = latest.environment_id AND ev.version = latest.max_version
           WHERE ev.base_id = ?1 AND ev.status = 0
           """,
           {environment_id}
         ) do
      {:ok, []} -> {:ok, false}
      {:ok, _} -> {:ok, true}
    end
  end

  # TODO: change to 'get_active_environment_by_id'?
  defp get_environment_by_id(db, environment_id) do
    case query_one(
           db,
           """
           SELECT name, base_id, version, status
           FROM environment_versions
           WHERE environment_id = ?1
           ORDER BY version DESC
           LIMIT 1
           """,
           {environment_id}
         ) do
      {:ok, {name, base_id, version, status}} ->
        {:ok, %{name: name, base_id: base_id, status: status, version: version}}

      {:ok, nil} ->
        {:ok, nil}
    end
  end

  def create_environment(db, name, base_id) do
    with_transaction(db, fn ->
      environment = %{
        name: name,
        base_id: base_id,
        status: 0,
        version: 1
      }

      errors =
        validate(
          environment,
          name: &validate_name(&1, db),
          base_id: &validate_base_id(&1, db)
        )

      if Enum.any?(errors) do
        {:error, errors}
      else
        case insert_one(db, :environments, %{}) do
          {:ok, environment_id} ->
            case insert_environment_version(db, environment_id, environment) do
              {:ok, _} ->
                {:ok, environment_id, environment}
            end
        end
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
          changes = extract_changes(environment, updates, [:name, :base_id])

          errors =
            validate(
              changes,
              name: &validate_name(&1, db),
              base_id: &validate_base_id(&1, db, environment_id)
            )

          if Enum.any?(errors) do
            {:error, errors}
          else
            if Enum.any?(changes) do
              environment =
                environment
                |> Map.merge(changes)
                |> Map.update!(:version, &(&1 + 1))

              case insert_environment_version(db, environment_id, environment) do
                {:ok, _} ->
                  {:ok, environment}
              end
            end
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
              environment =
                environment
                |> Map.update!(:version, &(&1 + 1))
                |> Map.put(:status, 1)

              case insert_environment_version(db, environment_id, environment) do
                {:ok, _} ->
                  {:ok, environment}
              end
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
    name && Regex.match?(~r/^[a-z0-9_-]+(\/[a-z0-9_-]+)*$/i, name)
  end

  defp validate_name(name, db) do
    if is_valid_name?(name) do
      case get_active_environment_by_name(db, name) do
        {:ok, nil} -> :ok
        {:ok, _} -> {:error, :exists}
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

  defp validate(changes, validators) do
    Enum.reduce(validators, %{}, fn {field, validator}, errors ->
      if Map.has_key?(changes, field) do
        case validator.(Map.fetch!(changes, field)) do
          :ok ->
            errors

          {:error, error} ->
            Map.put(errors, field, error)
        end
      else
        errors
      end
    end)
  end

  defp insert_environment_version(db, environment_id, environment) do
    insert_one(db, :environment_versions, %{
      environment_id: environment_id,
      version: environment.version,
      name: environment.name,
      base_id: environment.base_id,
      status: environment.status,
      created_at: current_timestamp()
    })
  end

  defp current_timestamp() do
    System.os_time(:millisecond)
  end
end
