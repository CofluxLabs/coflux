defmodule Coflux.Orchestration.Manifests do
  import Coflux.Store

  alias Coflux.Orchestration.TagSets

  def register_manifests(db, environment_id, manifests) do
    with_transaction(db, fn ->
      manifest_ids =
        Map.new(manifests, fn {repository, manifest} ->
          {:ok, manifest_id} =
            if manifest do
              hash = hash_manifest(manifest)

              case query_one(db, "SELECT id FROM manifests WHERE hash = ?1", {hash}) do
                {:ok, nil} ->
                  {:ok, manifest_id} = insert_one(db, :manifests, %{hash: hash})

                  {:ok, _} =
                    insert_many(
                      db,
                      :workflows,
                      {:manifest_id, :name, :parameter_set_id, :wait_for, :cache_params,
                       :cache_max_age, :cache_namespace, :cache_version, :defer_params, :delay,
                       :retry_limit, :retry_delay_min, :retry_delay_max, :requires_tag_set_id},
                      Enum.map(manifest.workflows, fn {name, workflow} ->
                        {:ok, requires_tag_set_id} =
                          if workflow.requires do
                            TagSets.get_or_create_tag_set_id(db, workflow.requires)
                          else
                            {:ok, nil}
                          end

                        case get_or_create_parameter_set_id(db, workflow.parameters) do
                          {:ok, parameter_set_id} ->
                            {
                              manifest_id,
                              name,
                              parameter_set_id,
                              encode_params_set(workflow.wait_for),
                              if(workflow.cache, do: encode_params_list(workflow.cache.params)),
                              if(workflow.cache, do: workflow.cache.max_age),
                              if(workflow.cache, do: workflow.cache.namespace),
                              if(workflow.cache, do: workflow.cache.version),
                              if(workflow.defer, do: encode_params_list(workflow.defer.params)),
                              workflow.delay,
                              if(workflow.retries, do: workflow.retries.limit, else: 0),
                              if(workflow.retries, do: workflow.retries.delay_min, else: 0),
                              if(workflow.retries, do: workflow.retries.delay_max, else: 0),
                              requires_tag_set_id
                            }
                        end
                      end)
                    )

                  {:ok, _} =
                    insert_many(
                      db,
                      :sensors,
                      {:manifest_id, :name, :parameter_set_id, :requires_tag_set_id},
                      Enum.map(manifest.sensors, fn {name, sensor} ->
                        {:ok, requires_tag_set_id} =
                          if sensor.requires do
                            TagSets.get_or_create_tag_set_id(db, sensor.requires)
                          else
                            {:ok, nil}
                          end

                        case get_or_create_parameter_set_id(db, sensor.parameters) do
                          {:ok, parameter_set_id} ->
                            {manifest_id, name, parameter_set_id, requires_tag_set_id}
                        end
                      end)
                    )

                  {:ok, manifest_id}

                {:ok, {manifest_id}} ->
                  {:ok, manifest_id}
              end
            else
              {:ok, nil}
            end

          {repository, manifest_id}
        end)

      {:ok, current_manifest_ids} = get_latest_manifest_ids(db, environment_id)

      now = current_timestamp()

      {:ok, _} =
        insert_many(
          db,
          :environment_manifests,
          {:environment_id, :repository, :manifest_id, :created_at},
          Enum.reduce(manifest_ids, [], fn {repository, manifest_id}, result ->
            if manifest_id != Map.get(current_manifest_ids, repository) do
              [{environment_id, repository, manifest_id, now} | result]
            else
              result
            end
          end)
        )

      :ok
    end)
  end

  defp get_latest_manifest_ids(db, environment_id) do
    case query(
           db,
           """
           SELECT em.repository, em.manifest_id
           FROM environment_manifests em
           JOIN (
               SELECT repository, MAX(created_at) AS latest_created_at
               FROM environment_manifests
               WHERE environment_id = ?1
               GROUP BY repository
           ) AS latest
           ON em.repository = latest.repository AND em.created_at = latest.latest_created_at
           WHERE em.environment_id = ?1
           """,
           {environment_id}
         ) do
      {:ok, rows} ->
        {:ok, Map.new(rows)}
    end
  end

  def get_latest_manifests(db, environment_id) do
    case get_latest_manifest_ids(db, environment_id) do
      {:ok, manifest_ids} ->
        manifests =
          Enum.reduce(manifest_ids, %{}, fn {repository, manifest_id}, result ->
            if manifest_id do
              {:ok, workflows} = get_manifest_workflows(db, manifest_id)
              {:ok, sensors} = get_manifest_sensors(db, manifest_id)
              Map.put(result, repository, %{workflows: workflows, sensors: sensors})
            else
              result
            end
          end)

        {:ok, manifests}
    end
  end

  def get_latest_workflow(db, environment_id, repository, target_name) do
    case query_one(
           db,
           """
           SELECT w.parameter_set_id, w.wait_for, w.cache_params, w.cache_max_age, w.cache_namespace, w.cache_version, w.defer_params, w.delay, w.retry_limit, w.retry_delay_min, w.retry_delay_max, w.requires_tag_set_id
           FROM workflows AS w
           INNER JOIN environment_manifests AS em ON em.manifest_id = w.manifest_id
           WHERE em.environment_id = ?1 AND em.repository = ?2 AND w.name = ?3
           ORDER BY em.created_at DESC
           LIMIT 1
           """,
           {environment_id, repository, target_name}
         ) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok,
       {parameter_set_id, wait_for, cache_params, cache_max_age, cache_namespace, cache_version,
        defer_params, delay, retry_limit, retry_delay_min, retry_delay_max,
        requires_tag_set_id}} ->
        build_workflow(
          db,
          parameter_set_id,
          wait_for,
          cache_params,
          cache_max_age,
          cache_namespace,
          cache_version,
          defer_params,
          delay,
          retry_limit,
          retry_delay_min,
          retry_delay_max,
          requires_tag_set_id
        )
    end
  end

  def get_latest_sensor(db, environment_id, repository, target_name) do
    case query_one(
           db,
           """
           SELECT s.parameter_set_id, s.requires_tag_set_id
           FROM sensors AS s
           INNER JOIN environment_manifests AS em ON em.manifest_id = s.manifest_id
           WHERE em.environment_id = ?1 AND em.repository = ?2 AND s.name = ?3
           ORDER BY em.created_at DESC
           LIMIT 1
           """,
           {environment_id, repository, target_name}
         ) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, {parameter_set_id, requires_tag_set_id}} ->
        build_sensor(db, parameter_set_id, requires_tag_set_id)
    end
  end

  defp get_manifest_workflows(db, manifest_id) do
    case query(
           db,
           """
           SELECT name, parameter_set_id, wait_for, cache_params, cache_max_age, cache_namespace, cache_version, defer_params, delay, retry_limit, retry_delay_min, retry_delay_max, requires_tag_set_id
           FROM workflows
           WHERE manifest_id = ?1
           """,
           {manifest_id}
         ) do
      {:ok, rows} ->
        workflows =
          Map.new(rows, fn {name, parameter_set_id, wait_for, cache_params, cache_max_age,
                            cache_namespace, cache_version, defer_params, delay, retry_limit,
                            retry_delay_min, retry_delay_max, requires_tag_set_id} ->
            {:ok, workflow} =
              build_workflow(
                db,
                parameter_set_id,
                wait_for,
                cache_params,
                cache_max_age,
                cache_namespace,
                cache_version,
                defer_params,
                delay,
                retry_limit,
                retry_delay_min,
                retry_delay_max,
                requires_tag_set_id
              )

            {name, workflow}
          end)

        {:ok, workflows}
    end
  end

  defp get_manifest_sensors(db, manifest_id) do
    case query(
           db,
           """
           SELECT name, parameter_set_id, requires_tag_set_id
           FROM sensors
           WHERE manifest_id = ?1
           """,
           {manifest_id}
         ) do
      {:ok, rows} ->
        sensors =
          Map.new(rows, fn {name, parameter_set_id, requires_tag_set_id} ->
            {:ok, sensor} = build_sensor(db, parameter_set_id, requires_tag_set_id)
            {name, sensor}
          end)

        {:ok, sensors}
    end
  end

  defp hash_manifest(manifest) do
    workflows_hash = hash_manifest_workflows(manifest.workflows)
    sensors_hash = hash_manifest_sensors(manifest.sensors)
    :crypto.hash(:sha256, [workflows_hash, 0, sensors_hash])
  end

  defp hash_manifest_workflows(workflows) do
    data =
      Enum.map(workflows, fn {name, workflow} ->
        [
          name,
          hash_parameter_set(workflow.parameters),
          Integer.to_string(encode_params_set(workflow.wait_for)),
          if(workflow.cache, do: encode_params_list(workflow.cache.params), else: ""),
          if(workflow.cache[:max_age], do: Integer.to_string(workflow.cache.max_age), else: ""),
          if(workflow.cache[:namespace], do: workflow.cache.namespace, else: ""),
          if(workflow.cache[:version], do: workflow.cache.version, else: ""),
          if(workflow.defer, do: encode_params_list(workflow.defer.params), else: ""),
          Integer.to_string(workflow.delay),
          if(workflow.retries, do: Integer.to_string(workflow.retries.limit), else: ""),
          if(workflow.retries, do: Integer.to_string(workflow.retries.delay_min), else: ""),
          if(workflow.retries, do: Integer.to_string(workflow.retries.delay_max), else: ""),
          workflow.requires
          |> Enum.sort()
          |> Enum.map_join(";", fn {key, values} ->
            "#{key}=#{values |> Enum.sort() |> Enum.join(",")}"
          end)
        ]
      end)

    :crypto.hash(:sha256, Enum.intersperse(data, 0))
  end

  defp hash_manifest_sensors(sensors) do
    data =
      Enum.map(sensors, fn {name, sensor} ->
        [name, hash_parameter_set(sensor.parameters)]
      end)

    :crypto.hash(:sha256, Enum.intersperse(data, 0))
  end

  defp build_workflow(
         db,
         parameter_set_id,
         wait_for,
         cache_params,
         cache_max_age,
         cache_namespace,
         cache_version,
         defer_params,
         delay,
         retry_limit,
         retry_delay_min,
         retry_delay_max,
         requires_tag_set_id
       ) do
    {:ok, parameters} = get_parameter_set(db, parameter_set_id)

    {:ok, requires} =
      if requires_tag_set_id do
        TagSets.get_tag_set(db, requires_tag_set_id)
      else
        {:ok, nil}
      end

    cache =
      if cache_params do
        %{
          params: decode_params_list(cache_params),
          max_age: cache_max_age,
          namespace: cache_namespace,
          version: cache_version
        }
      end

    defer =
      if defer_params do
        %{
          params: decode_params_list(defer_params)
        }
      end

    retries =
      if retry_limit do
        %{
          limit: retry_limit,
          delay_min: retry_delay_min,
          delay_max: retry_delay_max
        }
      end

    {:ok,
     %{
       parameters: parameters,
       wait_for: decode_params_set(wait_for),
       cache: cache,
       defer: defer,
       delay: delay,
       retries: retries,
       requires: requires
     }}
  end

  defp build_sensor(db, parameter_set_id, requires_tag_set_id) do
    {:ok, parameters} = get_parameter_set(db, parameter_set_id)

    {:ok, requires} =
      if requires_tag_set_id do
        TagSets.get_tag_set(db, requires_tag_set_id)
      else
        {:ok, nil}
      end

    {:ok,
     %{
       parameters: parameters,
       requires: requires
     }}
  end

  defp get_or_create_parameter_set_id(db, parameters) do
    hash = hash_parameter_set(parameters)

    case query_one(db, "SELECT id FROM parameter_sets WHERE hash = ?1", {hash}) do
      {:ok, {parameter_set_id}} ->
        {:ok, parameter_set_id}

      {:ok, nil} ->
        case insert_one(db, :parameter_sets, %{hash: hash}) do
          {:ok, parameter_set_id} ->
            {:ok, _} =
              insert_many(
                db,
                :parameter_set_items,
                {:parameter_set_id, :position, :name, :default_, :annotation},
                parameters
                |> Enum.with_index()
                |> Enum.map(fn {{name, default, annotation}, index} ->
                  {parameter_set_id, index, name, default, annotation}
                end)
              )

            {:ok, parameter_set_id}
        end
    end
  end

  defp get_parameter_set(db, parameter_set_id) do
    case query(
           db,
           """
           SELECT name, default_, annotation
           FROM parameter_set_items
           WHERE parameter_set_id = ?1
           ORDER BY position
           """,
           {parameter_set_id}
         ) do
      {:ok, rows} ->
        {:ok, rows}
    end
  end

  defp hash_parameter_set(parameters) do
    data =
      parameters
      |> Enum.map(fn {name, default, annotation} ->
        "#{name}:#{default}:#{annotation}"
      end)
      |> Enum.intersperse(0)

    :crypto.hash(:sha256, data)
  end

  defp encode_params_list(params) do
    case params do
      true -> ""
      false -> nil
      nil -> nil
      params -> Enum.map_join(params, ",", &Integer.to_string/1)
    end
  end

  defp decode_params_list(value) do
    case value do
      nil -> false
      "" -> true
      value -> value |> String.split(",") |> Enum.map(&String.to_integer/1)
    end
  end

  defp encode_params_set(indexes) do
    Enum.reduce(indexes, 0, &Bitwise.bor(&2, Bitwise.bsl(1, &1)))
  end

  defp decode_params_set(value) do
    value
    |> Integer.digits(2)
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.filter(fn {v, _} -> v == 1 end)
    |> Enum.map(fn {_, i} -> i end)
  end

  defp current_timestamp() do
    System.os_time(:millisecond)
  end
end
