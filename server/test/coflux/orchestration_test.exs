defmodule Coflux.OrchestrationTest do
  use ExUnit.Case, async: true

  import Coflux.Orchestration

  setup do
    project_id = "test_#{Enum.random(0..10000)}"
    on_exit(fn -> File.rm_rf!("data/#{project_id}") end)
    %{project_id: project_id}
  end

  test "run task after registering target", %{project_id: project_id} do
    {:ok, session_id} = start_session(project_id, "test", self())

    :ok =
      register_targets(project_id, "test", session_id, "myrepo", %{
        "foo" => %{type: :task, parameters: []}
      })

    {:ok, _run_id, _step_id, execution_id} =
      schedule_task(project_id, "test", "myrepo", "foo", [])

    assert_receive({:execute, ^execution_id, "myrepo", "foo", []})
  end

  test "run task before registering target", %{project_id: project_id} do
    {:ok, _run_id, _step_id, execution_id} =
      schedule_task(project_id, "test", "myrepo", "foo", [])

    {:ok, session_id} = start_session(project_id, "test", self())

    :ok =
      register_targets(project_id, "test", session_id, "myrepo", %{
        "foo" => %{type: :task, parameters: []}
      })

    assert_receive({:execute, ^execution_id, "myrepo", "foo", []})
  end

  test "subscribe to repositories", %{project_id: project_id} do
    {:ok, session_id} = start_session(project_id, "test", self())

    :ok =
      register_targets(project_id, "test", session_id, "myrepo", %{
        "foo" => %{type: :task, parameters: []}
      })

    :ok =
      register_targets(project_id, "test", session_id, "myrepo", %{
        "bar" => %{type: :task, parameters: []},
        "baz" => %{type: :task, parameters: []}
      })

    :ok =
      register_targets(project_id, "test", session_id, "anotherrepo", %{
        "qux" => %{type: :task, parameters: []}
      })

    {:ok, repositories, ref} = subscribe_repositories(project_id, "test", self())

    assert repositories == %{
             "anotherrepo" => %{"qux" => %{type: :task, parameters: []}},
             "myrepo" => %{
               "bar" => %{type: :task, parameters: []},
               "baz" => %{type: :task, parameters: []}
             }
           }

    {:ok, session_id} = start_session(project_id, "test", self())

    :ok =
      register_targets(project_id, "test", session_id, "myrepo", %{
        "quux" => %{type: :task, parameters: []}
      })

    assert_receive(
      {:topic, ^ref, {:targets, "myrepo", %{"quux" => %{type: :task, parameters: []}}}}
    )

    unsubscribe(project_id, "test", ref)

    {:ok, repositories, ref} = subscribe_repositories(project_id, "test", self())
    unsubscribe(project_id, "test", ref)

    assert repositories == %{
             "anotherrepo" => %{"qux" => %{type: :task, parameters: []}},
             "myrepo" => %{"quux" => %{type: :task, parameters: []}}
           }
  end

  test "subscribe to task", %{project_id: project_id} do
    {:ok, session_id} = start_session(project_id, "test", self())

    :ok =
      register_targets(project_id, "test", session_id, "myrepo", %{
        "foo" => %{type: :task, parameters: []}
      })

    {:ok, %{type: task, parameters: []}, task_runs, ref} =
      subscribe_task(project_id, "test", "myrepo", "foo", self())

    assert task_runs == []

    {:ok, run_id, _step_id, _execution_id} =
      schedule_task(project_id, "test", "myrepo", "foo", [])

    assert_receive({:topic, ^ref, {:run, ^run_id, _created_at}})
    unsubscribe(project_id, "test", ref)

    {:ok, _target, task_runs, ref} = subscribe_task(project_id, "test", "myrepo", "foo", self())
    assert match?([{^run_id, _created_at}], task_runs)
    unsubscribe(project_id, "test", ref)
  end

  test "subscribe to run", %{project_id: project_id} do
    {:ok, run_id, _step_id, execution_id} = schedule_task(project_id, "test", "myrepo", "foo", [])
    {:ok, run, steps, ref} = subscribe_run(project_id, "test", run_id, self())

    assert match?({nil, _}, run)

    assert match?(
             %{
               1 => %{
                 arguments: [],
                 cached_execution_id: nil,
                 executions: %{
                   1 => %{
                     assigned_at: nil,
                     completed_at: nil,
                     dependencies: [],
                     result: nil,
                     sequence: 1
                   }
                 },
                 parent_id: nil,
                 repository: "myrepo",
                 target: "foo"
               }
             },
             steps
           )

    {:ok, session_id} = start_session(project_id, "test", self())

    :ok =
      register_targets(project_id, "test", session_id, "myrepo", %{
        "foo" => %{type: :task, parameters: []},
        "bar" => %{type: :step, parameters: []}
      })

    assert_receive({:execute, ^execution_id, "myrepo", "foo", []})
    assert_receive({:topic, ^ref, {:assignment, ^execution_id, _assigned_at}})

    {:ok, _step_id, execution_id_2} =
      schedule_step(project_id, "test", "myrepo", "bar", [], execution_id)

    assert_receive({:execute, ^execution_id_2, "myrepo", "bar", []})

    record_result(project_id, "test", execution_id, {:reference, execution_id_2})

    assert_receive(
      {:topic, ^ref, {:result, ^execution_id, 0, {:reference, execution_id_2}, _created_at}}
    )

    {:wait, _ref} = get_result(project_id, "test", execution_id_2, execution_id, self())
    assert_receive({:topic, ^ref, {:dependency, ^execution_id, ^execution_id_2}})

    record_result(project_id, "test", execution_id_2, {:raw, "json", "{\"a\":1}"})

    assert_receive(
      {:topic, ^ref, {:result, ^execution_id_2, 0, {:raw, "json", "{\"a\":1}"}, _created_at}}
    )

    unsubscribe(project_id, "test", ref)
  end

  test "get result", %{project_id: project_id} do
    {:ok, session_id} = start_session(project_id, "test", self())

    :ok =
      register_targets(project_id, "test", session_id, "myrepo", %{
        "foo" => %{type: :task, parameters: []}
      })

    {:ok, _run_id, _step_id, execution_id} =
      schedule_task(project_id, "test", "myrepo", "foo", [])

    assert_receive({:execute, ^execution_id, "myrepo", "foo", []})
    record_result(project_id, "test", execution_id, {:raw, "json", "{\"a\":1}"})

    assert get_result(project_id, "test", execution_id, self()) ==
             {:ok, {:raw, "json", "{\"a\":1}"}}
  end

  test "wait for result", %{project_id: project_id} do
    {:ok, session_id} = start_session(project_id, "test", self())

    :ok =
      register_targets(project_id, "test", session_id, "myrepo", %{
        "foo" => %{type: :task, parameters: []}
      })

    {:ok, _run_id, _step_id, execution_id} =
      schedule_task(project_id, "test", "myrepo", "foo", [])

    assert_receive({:execute, ^execution_id, "myrepo", "foo", []})
    {:wait, ref} = get_result(project_id, "test", execution_id, self())
    # assert match?({:wait, ref}, result)
    record_result(project_id, "test", execution_id, {:raw, "json", "{\"a\":1}"})
    assert_receive({:result, ^ref, {:raw, "json", "{\"a\":1}"}})
  end

  test "get referenced result", %{project_id: project_id} do
    {:ok, session_id} = start_session(project_id, "test", self())

    :ok =
      register_targets(project_id, "test", session_id, "myrepo", %{
        "foo" => %{type: :task, parameters: []},
        "bar" => %{type: :task, parameters: []}
      })

    {:ok, _run_id, _step_id, execution_id_1} =
      schedule_task(project_id, "test", "myrepo", "foo", [])

    assert_receive({:execute, ^execution_id_1, "myrepo", "foo", []})

    {:ok, _step_id, execution_id_2} =
      schedule_step(project_id, "test", "myrepo", "bar", [], execution_id_1)

    assert_receive({:execute, ^execution_id_2, "myrepo", "bar", []})
    record_result(project_id, "test", execution_id_1, {:reference, execution_id_2})
    record_result(project_id, "test", execution_id_2, {:raw, "json", "{\"a\":2}"})

    assert get_result(project_id, "test", execution_id_1, self()) ==
             {:ok, {:raw, "json", "{\"a\":2}"}}
  end

  test "wait for referenced result", %{project_id: project_id} do
    {:ok, session_id} = start_session(project_id, "test", self())

    :ok =
      register_targets(project_id, "test", session_id, "myrepo", %{
        "foo" => %{type: :task, parameters: []},
        "bar" => %{type: :task, parameters: []}
      })

    {:ok, _run_id, _step_id, execution_id_1} =
      schedule_task(project_id, "test", "myrepo", "foo", [])

    assert_receive({:execute, ^execution_id_1, "myrepo", "foo", []})

    {:ok, _step_id, execution_id_2} =
      schedule_step(project_id, "test", "myrepo", "bar", [], execution_id_1)

    assert_receive({:execute, ^execution_id_2, "myrepo", "bar", []})
    {:wait, ref_1} = get_result(project_id, "test", execution_id_1, self())
    {:wait, ref_2} = get_result(project_id, "test", execution_id_2, self())
    record_result(project_id, "test", execution_id_1, {:reference, execution_id_2})
    record_result(project_id, "test", execution_id_2, {:raw, "json", "{\"a\":2}"})
    assert_receive({:result, ^ref_1, {:raw, "json", "{\"a\":2}"}})
    assert_receive({:result, ^ref_2, {:raw, "json", "{\"a\":2}"}})
  end

  test "use cached execution", %{project_id: project_id} do
    {:ok, session_id} = start_session(project_id, "test", self())

    :ok =
      register_targets(project_id, "test", session_id, "myrepo", %{
        "foo" => %{type: :task, parameters: []},
        "bar" => %{type: :task, parameters: []}
      })

    {:ok, _run_id, _step_id, execution_id_1} =
      schedule_task(project_id, "test", "myrepo", "foo", [])

    assert_receive({:execute, ^execution_id_1, "myrepo", "foo", []})

    {:ok, _step_id, execution_id_2} =
      schedule_step(project_id, "test", "myrepo", "bar", [], execution_id_1, "cache_key")

    assert_receive({:execute, ^execution_id_2, "myrepo", "bar", []})

    {:ok, _step_id, execution_id_3} =
      schedule_step(project_id, "test", "myrepo", "bar", [], execution_id_1, "cache_key")

    assert execution_id_2 == execution_id_3

    record_result(project_id, "test", execution_id_1, {:raw, "json", "1"})
    record_result(project_id, "test", execution_id_2, {:raw, "json", "2"})
  end
end
