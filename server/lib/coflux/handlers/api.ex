defmodule Coflux.Handlers.Api do
  import Coflux.Handlers.Utils

  alias Coflux.{Orchestration, Projects, MapUtils}

  @projects_server Coflux.ProjectsServer

  def init(req, opts) do
    req = handle(req, :cowboy_req.method(req), :cowboy_req.path_info(req))
    {:ok, req, opts}
  end

  defp handle(req, "POST", ["create_project"]) do
    {:ok, arguments, errors, req} =
      read_arguments(req, %{
        project_name: "projectName",
        environment: "environment"
      })

    if Enum.empty?(errors) do
      case Projects.create_project(
             @projects_server,
             arguments.project_name,
             arguments.environment
           ) do
        {:ok, project_id} ->
          case Orchestration.Supervisor.get_server(project_id, arguments.environment) do
            {:ok, _server} ->
              json_response(req, %{
                "projectId" => project_id
              })
          end

        {:error, errors} ->
          errors =
            MapUtils.translate_keys(errors, %{
              environment_name: "environment",
              project_name: "projectName"
            })

          json_error_response(req, "bad_request", details: errors)
      end
    else
      json_error_response(req, "bad_request", details: errors)
    end
  end

  defp handle(req, "POST", ["add_environment"]) do
    {:ok, arguments, errors, req} =
      read_arguments(req, %{
        project_id: "projectId",
        environment: "environment"
      })

    if Enum.empty?(errors) do
      case Projects.add_environment(
             @projects_server,
             arguments.project_id,
             arguments.environment
           ) do
        :ok ->
          json_response(req, %{})

        {:error, errors} ->
          errors =
            MapUtils.translate_keys(errors, %{
              environment_name: "environment"
            })

          json_error_response(req, "bad_request", details: errors)
      end
    else
      json_error_response(req, "bad_request", details: errors)
    end
  end

  defp handle(req, "POST", ["schedule"]) do
    {:ok, arguments, errors, req} =
      read_arguments(req, %{
        project_id: "projectId",
        environment: "environment",
        repository: "repository",
        target: "target",
        arguments: {"arguments", &parse_arguments/1}
      })

    if Enum.empty?(errors) do
      case Orchestration.schedule(
             arguments.project_id,
             arguments.environment,
             arguments.repository,
             arguments.target,
             arguments.arguments
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
        environment: "environment",
        run_id: "runId"
      })

    if Enum.empty?(errors) do
      case Orchestration.cancel_run(
             arguments.project_id,
             arguments.environment,
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
        environment: "environment",
        step_id: "stepId"
      })

    if Enum.empty?(errors) do
      case Orchestration.rerun_step(
             arguments.project_id,
             arguments.environment,
             arguments.step_id
           ) do
        {:ok, execution_id, attempt} ->
          json_response(req, %{"executionId" => execution_id, "attempt" => attempt})
      end
    else
      json_error_response(req, "bad_request", details: errors)
    end
  end

  defp handle(req, _method, _path) do
    json_error_response(req, "not_found", status: 404)
  end

  defp is_valid_json(value) do
    case Jason.decode(value) do
      {:ok, _} -> true
      {:error, _} -> false
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
              if is_valid_json(value) do
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
              ["json", value] -> {:raw, "json", value, %{}, %{}, %{}}
            end
          end)

        {:ok, result}
      end
    else
      {:ok, []}
    end
  end
end
