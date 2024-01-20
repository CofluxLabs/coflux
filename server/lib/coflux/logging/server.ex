defmodule Coflux.Logging.Server do
  use GenServer, restart: :transient

  def start_link(opts) do
    {project_id, opts} = Keyword.pop!(opts, :project_id)
    {environment, opts} = Keyword.pop!(opts, :environment)
    {run_id, opts} = Keyword.pop!(opts, :run_id)
    GenServer.start_link(__MODULE__, {project_id, environment, run_id}, opts)
  end

  def init({project_id, environment, run_id}) do
    dir = "data/#{project_id}/#{environment}/logs"
    File.mkdir_p!(dir)
    path = Path.join(dir, "#{run_id}.jsonl")
    {:ok, %{path: path, subscribers: %{}}}
  end

  def handle_cast({:write, messages}, state) do
    content =
      Enum.map(messages, fn {execution_id, timestamp, level, template, labels} ->
        [Jason.encode!([execution_id, timestamp, encode_level(level), template, labels]), "\n"]
      end)

    File.write!(state.path, content, [:append])

    Enum.each(state.subscribers, fn {ref, pid} ->
      send(pid, {:messages, ref, messages})
    end)

    {:noreply, state}
  end

  def handle_cast({:unsubscribe, ref}, state) do
    {_, state} = pop_in(state.subscribers[ref])
    Process.demonitor(ref)
    {:noreply, state}
  end

  # TODO: support pagination?
  def handle_call({:subscribe, pid, execution_id}, _from, state) do
    messages =
      if File.exists?(state.path) do
        state.path
        |> File.stream!()
        |> Enum.map(fn line ->
          case Jason.decode!(line) do
            [execution_id_, timestamp, level, template, labels] ->
              {execution_id_, timestamp, decode_level(level), template, labels}
          end
        end)
        |> Enum.filter(fn {execution_id_, _, _, _, _} ->
          is_nil(execution_id) or execution_id_ == execution_id
        end)
      else
        []
      end

    ref = Process.monitor(pid)
    state = put_in(state.subscribers[ref], pid)

    {:reply, {:ok, ref, messages}, state}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case pop_in(state.subscribers[ref]) do
      {^pid, state} -> {:noreply, state}
      {nil, state} -> {:noreply, state}
    end
  end

  defp encode_level(level) do
    case level do
      :stdout -> 0
      :stderr -> 1
      :debug -> 2
      :info -> 3
      :warning -> 4
      :error -> 5
    end
  end

  defp decode_level(level) do
    case level do
      0 -> :stdout
      1 -> :stderr
      2 -> :debug
      3 -> :info
      4 -> :warning
      5 -> :error
    end
  end
end
