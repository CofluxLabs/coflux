defmodule Coflux.Handlers.Api do
  import Coflux.Handlers.Utils

  alias Coflux.{Orchestration, Projects, MapUtils}

  @projects_server Coflux.ProjectsServer
  @max_parameters 20

  def init(req, opts) do
    req = handle(req, :cowboy_req.method(req), :cowboy_req.path_info(req))
    {:ok, req, opts}
  end

  defp handle(req, "POST", ["create_project"]) do
    {:ok, arguments, errors, req} =
      read_arguments(req, %{project_name: "projectName"})

    if Enum.empty?(errors) do
      case Projects.create_project(@projects_server, arguments.project_name) do
        {:ok, project_id} ->
          json_response(req, %{"projectId" => project_id})

        {:error, errors} ->
          errors =
            MapUtils.translate_keys(errors, %{
              project_name: "projectName"
            })

          json_error_response(req, "bad_request", details: errors)
      end
    else
      json_error_response(req, "bad_request", details: errors)
    end
  end

  defp handle(req, "GET", ["get_environments"]) do
    qs = :cowboy_req.parse_qs(req)
    project_id = get_query_param(qs, "project")

    case Projects.get_project_by_id(Coflux.ProjectsServer, project_id) do
      {:ok, _} ->
        case Orchestration.get_environments(project_id) do
          {:ok, environments} ->
            json_response(
              req,
              Map.new(environments, fn {environment_id, environment} ->
                base_id =
                  if environment.base_id,
                    do: Integer.to_string(environment.base_id)

                {environment_id,
                 %{
                   "name" => environment.name,
                   "baseId" => base_id
                 }}
              end)
            )
        end

      :error ->
        json_error_response(req, "not_found", status: 404)
    end
  end

  defp handle(req, "POST", ["create_environment"]) do
    {:ok, arguments, errors, req} =
      read_arguments(
        req,
        %{
          project_id: "projectId",
          name: "name"
        },
        %{
          base_id: {"baseId", &parse_environment_id(&1, false)},
          pools: {"pools", &parse_pools/1}
        }
      )

    if Enum.empty?(errors) do
      case Orchestration.create_environment(
             arguments.project_id,
             arguments.name,
             arguments[:base_id],
             arguments[:pools]
           ) do
        {:ok, environment_id} ->
          json_response(req, %{id: environment_id})

        {:error, errors} ->
          errors =
            MapUtils.translate_keys(errors, %{
              name: "name",
              base_id: "baseId"
            })

          json_error_response(req, "bad_request", details: errors)
      end
    else
      json_error_response(req, "bad_request", details: errors)
    end
  end

  defp handle(req, "POST", ["update_environment"]) do
    {:ok, arguments, errors, req} =
      read_arguments(
        req,
        %{
          project_id: "projectId",
          environment_id: {"environmentId", &parse_environment_id/1}
        },
        %{
          name: "name",
          base_id: {"baseId", &parse_environment_id(&1, false)},
          pools: {"pools", &parse_pools/1}
        }
      )

    if Enum.empty?(errors) do
      case Orchestration.update_environment(
             arguments.project_id,
             arguments.environment_id,
             Map.take(arguments, [:name, :base_id, :pools])
           ) do
        :ok ->
          :cowboy_req.reply(204, req)

        {:error, :not_found} ->
          json_error_response(req, "not_found", status: 404)

        {:error, errors} ->
          errors =
            MapUtils.translate_keys(errors, %{
              name: "name",
              base_id: "baseId"
            })

          json_error_response(req, "bad_request", details: errors)
      end
    else
      json_error_response(req, "bad_request", details: errors)
    end
  end

  defp handle(req, "POST", ["pause_environment"]) do
    {:ok, arguments, errors, req} =
      read_arguments(req, %{
        project_id: "projectId",
        environment_id: {"environmentId", &parse_environment_id/1}
      })

    if Enum.empty?(errors) do
      case Orchestration.pause_environment(
             arguments.project_id,
             arguments.environment_id
           ) do
        :ok ->
          :cowboy_req.reply(204, req)

        {:error, :not_found} ->
          json_error_response(req, "not_found", code: 404)
      end
    else
      json_error_response(req, "bad_request", details: errors)
    end
  end

  defp handle(req, "POST", ["resume_environment"]) do
    {:ok, arguments, errors, req} =
      read_arguments(req, %{
        project_id: "projectId",
        environment_id: {"environmentId", &parse_environment_id/1}
      })

    if Enum.empty?(errors) do
      case Orchestration.resume_environment(
             arguments.project_id,
             arguments.environment_id
           ) do
        :ok ->
          :cowboy_req.reply(204, req)

        {:error, :not_found} ->
          json_error_response(req, "not_found", code: 404)
      end
    else
      json_error_response(req, "bad_request", details: errors)
    end
  end

  defp handle(req, "POST", ["archive_environment"]) do
    {:ok, arguments, errors, req} =
      read_arguments(req, %{
        project_id: "projectId",
        environment_id: {"environmentId", &parse_environment_id/1}
      })

    if Enum.empty?(errors) do
      case Orchestration.archive_environment(
             arguments.project_id,
             arguments.environment_id
           ) do
        :ok ->
          :cowboy_req.reply(204, req)

        {:error, :descendants} ->
          json_error_response(req, "bad_request",
            details: %{"environmentId" => "has_dependencies"}
          )

        {:error, :not_found} ->
          json_error_response(req, "not_found", code: 404)
      end
    else
      json_error_response(req, "bad_request", details: errors)
    end
  end

  defp handle(req, "POST", ["register_manifests"]) do
    {:ok, arguments, errors, req} =
      read_arguments(req, %{
        project_id: "projectId",
        environment_name: "environmentName",
        manifests: {"manifests", &parse_manifests/1}
      })

    if Enum.empty?(errors) do
      case Orchestration.register_manifests(
             arguments.project_id,
             arguments.environment_name,
             arguments.manifests
           ) do
        :ok ->
          :cowboy_req.reply(204, req)
      end
    else
      json_error_response(req, "bad_request", details: errors)
    end
  end

  defp handle(req, "GET", ["get_workflow"]) do
    qs = :cowboy_req.parse_qs(req)
    project_id = get_query_param(qs, "project")
    environment_name = get_query_param(qs, "environment")
    repository = get_query_param(qs, "repository")
    target_name = get_query_param(qs, "target")

    case Orchestration.get_workflow(project_id, environment_name, repository, target_name) do
      {:ok, nil} ->
        json_error_response(req, "not_found", status: 404)

      {:ok, workflow} ->
        json_response(req, compose_workflow(workflow))
    end
  end

  defp handle(req, "POST", ["submit_workflow"]) do
    {:ok, arguments, errors, req} =
      read_arguments(
        req,
        %{
          project_id: "projectId",
          repository: "repository",
          target: "target",
          environment_name: "environmentName",
          arguments: {"arguments", &parse_arguments/1}
        },
        %{
          wait_for: {"waitFor", &parse_indexes/1},
          cache: {"cache", &parse_cache/1},
          defer: {"defer", &parse_defer/1},
          execute_after: {"executeAfter", &parse_integer(&1, optional: true)},
          retries: {"retries", &parse_retries/1},
          requires: {"requires", &parse_tag_set/1}
        }
      )

    if Enum.empty?(errors) do
      case Orchestration.submit_workflow(
             arguments.project_id,
             arguments.repository,
             arguments.target,
             arguments.arguments,
             environment: arguments.environment_name,
             execute_after: arguments[:execute_after],
             wait_for: arguments[:wait_for],
             cache: arguments[:cache],
             defer: arguments[:defer],
             delay: arguments[:delay],
             retries: arguments[:retries],
             requires: arguments[:requires]
           ) do
        {:ok, run_id, step_id, execution_id} ->
          json_response(req, %{
            "runId" => run_id,
            "stepId" => step_id,
            "executionId" => execution_id
          })
      end
    else
      json_error_response(req, "bad_request", details: errors)
    end
  end

  defp handle(req, "POST", ["start_sensor"]) do
    {:ok, arguments, errors, req} =
      read_arguments(
        req,
        %{
          project_id: "projectId",
          repository: "repository",
          target: "target",
          environment_name: "environmentName",
          arguments: {"arguments", &parse_arguments/1}
        },
        %{
          requires: {"requires", &parse_tag_set/1}
        }
      )

    if Enum.empty?(errors) do
      case Orchestration.start_sensor(
             arguments.project_id,
             arguments.repository,
             arguments.target,
             arguments.arguments,
             environment: arguments.environment_name,
             requires: arguments[:requires]
           ) do
        {:ok, run_id, step_id, execution_id} ->
          json_response(req, %{
            "runId" => run_id,
            "stepId" => step_id,
            "executionId" => execution_id
          })
      end
    else
      json_error_response(req, "bad_request", details: errors)
    end
  end

  defp handle(req, "POST", ["cancel_run"]) do
    {:ok, arguments, errors, req} =
      read_arguments(req, %{
        project_id: "projectId",
        run_id: "runId"
      })

    if Enum.empty?(errors) do
      case Orchestration.cancel_run(
             arguments.project_id,
             arguments.run_id
           ) do
        :ok ->
          json_response(req, %{})
      end
    else
      json_error_response(req, "bad_request", details: errors)
    end
  end

  defp handle(req, "POST", ["rerun_step"]) do
    {:ok, arguments, errors, req} =
      read_arguments(req, %{
        project_id: "projectId",
        environment_name: "environmentName",
        step_id: "stepId"
      })

    if Enum.empty?(errors) do
      case Orchestration.rerun_step(
             arguments.project_id,
             arguments.step_id,
             arguments.environment_name
           ) do
        {:ok, execution_id, attempt} ->
          json_response(req, %{"executionId" => execution_id, "attempt" => attempt})

        {:error, :environment_invalid} ->
          json_error_response(req, "bad_request", details: %{"environment" => "invalid"})
      end
    else
      json_error_response(req, "bad_request", details: errors)
    end
  end

  defp handle(req, _method, _path) do
    json_error_response(req, "not_found", status: 404)
  end

  defp is_valid_json?(value) do
    if value do
      case Jason.decode(value) do
        {:ok, _} -> true
        {:error, _} -> false
      end
    else
      false
    end
  end

  defp parse_environment_id(value, required \\ true) do
    if not required and is_nil(value) do
      {:ok, nil}
    else
      case Integer.parse(value) do
        {id, ""} -> {:ok, id}
        _ -> {:error, :invalid}
      end
    end
  end

  def is_valid_string?(value, opts) do
    cond do
      not is_binary(value) -> false
      opts[:max_length] && String.length(value) > opts[:max_length] -> false
      opts[:regex] && !Regex.match?(opts[:regex], value) -> false
      true -> true
    end
  end

  defp is_valid_repository_pattern?(pattern) do
    cond do
      not is_binary(pattern) ->
        false

      String.length(pattern) > 100 ->
        false

      true ->
        parts = String.split(pattern, ".")
        Enum.all?(parts, &(&1 == "*" || Regex.match?(~r/^[a-z_][a-z0-9_]*$/i, &1)))
    end
  end

  defp is_valid_tag_key?(key) do
    is_valid_string?(key, regex: ~r/^[a-z0-9_-]{1,20}$/i)
  end

  defp is_valid_tag_value?(value) do
    is_valid_string?(value, regex: ~r/^[a-z0-9_-]{1,30}$/i)
  end

  defp is_valid_pool_name?(name) do
    is_valid_string?(name, regex: ~r/^[a-z][a-z0-9_-]{0,19}$/i)
  end

  defp parse_repositories(value) do
    value = List.wrap(value)

    if Enum.all?(value, &is_valid_repository_pattern?/1) do
      {:ok, value}
    else
      {:error, :invalid}
    end
  end

  defp parse_tag_set_item(key, value) do
    value =
      value
      |> List.wrap()
      |> Enum.map(fn
        true -> "true"
        false -> "false"
        other -> other
      end)

    if is_valid_tag_key?(key) &&
         Enum.all?(value, &is_valid_tag_value?/1) &&
         length(value) <= 10 do
      {:ok, key, value}
    else
      {:error, :invalid}
    end
  end

  defp parse_tag_set(value) do
    cond do
      is_nil(value) ->
        {:ok, %{}}

      is_map(value) && map_size(value) <= 10 ->
        Enum.reduce_while(value, {:ok, %{}}, fn {key, value}, {:ok, result} ->
          case parse_tag_set_item(key, value) do
            {:ok, key, value} ->
              {:cont, {:ok, Map.put(result, key, value)}}

            {:error, error} ->
              {:halt, {:error, error}}
          end
        end)

      true ->
        {:error, :invalid}
    end
  end

  defp parse_docker_launcher(value) do
    image = Map.get(value, "image")

    if is_binary(image) && String.length(image) <= 200 do
      {:ok, %{type: :docker, image: image}}
    else
      {:error, :invalid}
    end
  end

  defp parse_launcher(value) do
    if is_map(value) do
      case Map.fetch(value, "type") do
        {:ok, "docker"} -> parse_docker_launcher(value)
        {:ok, _other} -> {:error, :invalid}
        :error -> {:error, :invalid}
      end
    else
      {:error, :invalid}
    end
  end

  defp parse_pool(value) do
    if is_map(value) do
      Enum.reduce_while(
        [
          {"repositories", &parse_repositories/1, :repositories, []},
          {"provides", &parse_tag_set/1, :provides, %{}},
          {"launcher", &parse_launcher/1, :launcher, nil}
        ],
        {:ok, %{}},
        fn {source, parser, target, default}, {:ok, result} ->
          case Map.fetch(value, source) do
            {:ok, value} ->
              case parser.(value) do
                {:ok, parsed} ->
                  {:cont, {:ok, Map.put(result, target, parsed)}}

                {:error, error} ->
                  {:halt, {:error, error}}
              end

            :error ->
              {:cont, {:ok, Map.put(result, target, default)}}
          end
        end
      )
    else
      {:error, :invalid}
    end
  end

  # TODO: return specific errors (use validation library?)
  defp parse_pools(value) do
    cond do
      is_nil(value) ->
        {:ok, %{}}

      is_map(value) ->
        Enum.reduce_while(value, {:ok, %{}}, fn {name, pool}, {:ok, result} ->
          if is_valid_pool_name?(name) do
            case parse_pool(pool) do
              {:ok, parsed} ->
                {:cont, {:ok, Map.put(result, name, parsed)}}

              {:error, error} ->
                {:halt, {:error, error}}
            end
          else
            {:halt, {:error, :invalid}}
          end
        end)

      true ->
        {:error, :invalid}
    end
  end

  defp transform_json(value) do
    cond do
      is_number(value) || is_boolean(value) || is_nil(value) || is_binary(value) ->
        value

      is_list(value) ->
        Enum.map(value, &transform_json/1)

      is_map(value) ->
        %{
          "type" => "dict",
          "items" =>
            Enum.flat_map(value, fn {key, value} ->
              [key, transform_json(value)]
            end)
        }
    end
  end

  defp parse_arguments(arguments) do
    if arguments do
      errors =
        arguments
        |> Enum.with_index()
        |> Enum.reduce(%{}, fn {argument, index}, errors ->
          case argument do
            ["json", value] ->
              if is_valid_json?(value) do
                errors
              else
                Map.put(errors, index, :not_json)
              end
          end
        end)

      if Enum.any?(errors) do
        {:error, errors}
      else
        result =
          Enum.map(arguments, fn argument ->
            case argument do
              ["json", json] ->
                value =
                  json
                  |> Jason.decode!()
                  |> transform_json()

                {:raw, value, []}
            end
          end)

        {:ok, result}
      end
    else
      {:ok, []}
    end
  end

  def is_valid_repository_name?(value) do
    is_valid_string?(value, max_length: 100, regex: ~r/^[a-z_][a-z0-9_]*(\.[a-z_][a-z0-9_]*)*$/i)
  end

  def is_valid_target_name?(value) do
    is_valid_string?(value, max_length: 100, regex: ~r/^[a-z_][a-z0-9_]*$/i)
  end

  defp parse_parameter(value) do
    # TODO: validate
    name = Map.fetch!(value, "name")
    default = Map.get(value, "default")
    annotation = Map.get(value, "annotation")
    {:ok, {name, default, annotation}}
  end

  defp parse_parameters(value) do
    if is_list(value) && length(value) <= @max_parameters do
      with {:ok, backwards} <-
             Enum.reduce_while(value, {:ok, []}, fn parameter, {:ok, result} ->
               case parse_parameter(parameter) do
                 {:ok, parsed} -> {:cont, {:ok, [parsed | result]}}
                 {:error, error} -> {:halt, {:error, error}}
               end
             end) do
        {:ok, Enum.reverse(backwards)}
      end
    else
      {:error, :invalid}
    end
  end

  defp parse_indexes(value, opts \\ []) do
    cond do
      opts[:allow_boolean] && !value ->
        {:ok, false}

      opts[:allow_boolean] && value == true ->
        {:ok, true}

      is_list(value) && length(value) <= @max_parameters ->
        with {:ok, backwards} <-
               Enum.reduce_while(value, {:ok, []}, fn item, {:ok, result} ->
                 case parse_integer(item) do
                   {:ok, value} -> {:cont, {:ok, [value | result]}}
                   {:error, error} -> {:halt, {:error, error}}
                 end
               end) do
          {:ok, Enum.reverse(backwards)}
        end

      true ->
        {:error, :invalid}
    end
  end

  defp parse_integer(value, opts \\ []) do
    cond do
      opts[:optional] && is_nil(value) -> {:ok, nil}
      is_integer(value) -> {:ok, value}
      true -> {:error, :invalid}
    end
  end

  defp parse_string(value, opts) do
    cond do
      opts[:optional] && is_nil(value) -> {:ok, nil}
      is_valid_string?(value, opts) -> {:ok, value}
      true -> {:error, :invalid}
    end
  end

  defp parse_cache(value) do
    cond do
      is_nil(value) ->
        {:ok, nil}

      is_map(value) ->
        with {:ok, params} <- parse_indexes(Map.get(value, "params"), allow_boolean: true),
             {:ok, max_age} <- parse_integer(Map.get(value, "maxAge"), optional: true),
             # TODO: regex
             {:ok, namespace} <- parse_string(Map.get(value, "namespace"), optional: true),
             # TODO: regex
             {:ok, version} <- parse_string(Map.get(value, "version"), optional: true) do
          {:ok,
           %{
             params: params,
             max_age: max_age,
             namespace: namespace,
             version: version
           }}
        end

      true ->
        {:error, :invalid}
    end
  end

  defp parse_defer(value) do
    cond do
      is_nil(value) ->
        {:ok, nil}

      is_map(value) ->
        with {:ok, params} <- parse_indexes(Map.get(value, "params"), allow_boolean: true) do
          {:ok, %{params: params}}
        end

      true ->
        {:error, :invalid}
    end
  end

  defp parse_retries(value) do
    cond do
      is_nil(value) ->
        {:ok, nil}

      is_map(value) ->
        with {:ok, limit} <- parse_integer(Map.get(value, "limit")),
             {:ok, delay_min} <- parse_integer(Map.get(value, "delayMin"), optional: true),
             {:ok, delay_max} <- parse_integer(Map.get(value, "delayMax"), optional: true) do
          {:ok, %{limit: limit, delay_min: delay_min, delay_max: delay_max}}
        end

      true ->
        {:error, :invalid}
    end
  end

  defp parse_workflow(value) do
    if is_map(value) do
      with {:ok, parameters} <- parse_parameters(Map.get(value, "parameters")),
           {:ok, wait_for} <- parse_indexes(Map.get(value, "waitFor")),
           {:ok, cache} <- parse_cache(Map.get(value, "cache")),
           {:ok, defer} <- parse_defer(Map.get(value, "defer")),
           {:ok, delay} <- parse_integer(Map.get(value, "delay")),
           {:ok, retries} <- parse_retries(Map.get(value, "retries")),
           {:ok, requires} <- parse_tag_set(Map.get(value, "requires")) do
        {:ok,
         %{
           parameters: parameters,
           wait_for: wait_for,
           cache: cache,
           defer: defer,
           delay: delay,
           retries: retries,
           requires: requires
         }}
      else
        {:error, error} ->
          {:error, error}
      end
    else
      {:error, :invalid}
    end
  end

  defp parse_sensor(value) do
    if is_map(value) do
      with {:ok, parameters} <- parse_parameters(Map.get(value, "parameters")),
           {:ok, requires} <- parse_tag_set(Map.get(value, "requires")) do
        {:ok,
         %{
           parameters: parameters,
           requires: requires
         }}
      end
    else
      {:error, :invalid}
    end
  end

  defp parse_workflows(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {workflow_name, workflow}, {:ok, result} ->
      if is_valid_target_name?(workflow_name) do
        case parse_workflow(workflow) do
          {:ok, parsed} ->
            {:cont, {:ok, Map.put(result, workflow_name, parsed)}}

          {:error, error} ->
            {:halt, {:error, error}}
        end
      else
        {:halt, {:error, :invalid}}
      end
    end)
  end

  defp parse_sensors(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {sensor_name, sensor}, {:ok, result} ->
      if is_valid_target_name?(sensor_name) do
        case parse_sensor(sensor) do
          {:ok, parsed} ->
            {:cont, {:ok, Map.put(result, sensor_name, parsed)}}

          {:error, error} ->
            {:halt, {:error, error}}
        end
      else
        {:halt, {:error, :invalid}}
      end
    end)
  end

  defp parse_manifest(value) do
    if is_map(value) do
      with {:ok, workflows} <- parse_workflows(Map.get(value, "workflows", %{})),
           {:ok, sensors} <- parse_sensors(Map.get(value, "sensors", %{})) do
        {:ok, %{workflows: workflows, sensors: sensors}}
      end
    else
      {:error, :invalid}
    end
  end

  defp parse_manifests(value) do
    if is_map(value) do
      Enum.reduce_while(value, {:ok, %{}}, fn {repository, manifest}, {:ok, result} ->
        if is_valid_repository_name?(repository) do
          case parse_manifest(manifest) do
            {:ok, parsed} ->
              {:cont, {:ok, Map.put(result, repository, parsed)}}

            {:error, error} ->
              {:halt, {:error, error}}
          end
        else
          {:halt, {:error, :invalid}}
        end
      end)
    else
      {:error, :invalid}
    end
  end

  defp compose_workflow_cache(cache) do
    if cache do
      %{
        "params" => cache.params,
        "maxAge" => cache.max_age,
        "namespace" => cache.namespace,
        "version" => cache.version
      }
    end
  end

  defp compose_workflow_defer(defer) do
    if defer do
      %{"params" => defer.params}
    end
  end

  defp compose_workflow_retries(retries) do
    if retries do
      %{
        "limit" => retries.limit,
        "delayMin" => retries.delay_min,
        "delayMax" => retries.delay_max
      }
    end
  end

  defp compose_workflow(workflow) do
    %{
      "parameters" =>
        Enum.map(workflow.parameters, fn {name, default, annotation} ->
          %{"name" => name, "default" => default, "annotation" => annotation}
        end),
      "waitFor" => workflow.wait_for,
      "cache" => compose_workflow_cache(workflow.cache),
      "defer" => compose_workflow_defer(workflow.defer),
      "delay" => workflow.delay,
      "retries" => compose_workflow_retries(workflow.retries),
      "requires" => workflow.requires
    }
  end
end
