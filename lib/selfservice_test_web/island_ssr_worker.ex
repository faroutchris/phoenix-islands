defmodule SelfServiceWeb.IslandSsrWorker do
  use GenServer
  require Logger

  @initial_state %{
    id: nil,
    port: nil,
    next_id: 1,
    buffer: "",
    pending: %{},
    worker_path: nil,
    runtime: nil
  }

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def render(module, props) do
    GenServer.call(__MODULE__, {:render, %{module: module, props: props}})
  end

  # --- Callbacks ---

  @impl true
  def init(_opts) do
    config = Application.get_env(:selfservice_test, __MODULE__, nil)

    state = %{
      @initial_state
      | worker_path: Keyword.fetch!(config, :worker_path),
        runtime: Keyword.fetch!(config, :runtime)
    }

    {:ok, start_port!(state)}
  end

  # Handle node buffer
  @impl true
  def handle_info({port, {:data, chunk}}, %{port: port} = state) do
    # Append the new chunk to the current state.buffer
    buffer = state.buffer <> chunk
    # Process all complete lines (\n), save incomplete lines in `rest` to be passed in to buffer
    {lines, rest_buffer} = split_buffer(buffer)

    state =
      Enum.reduce(lines, %{state | buffer: rest_buffer}, fn line, acc ->
        case String.trim(line) do
          "" -> acc
          trimmed -> handle_response(trimmed, acc)
        end
      end)

    {:noreply, state}
  end

  # Exit
  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("External exit: :exit_status: #{status}")

    # Reply with error to all pending callers
    for {_id, %{from: from}} <- state.pending do
      GenServer.reply(from, {:error, :worker_crashed})
    end

    {:noreply, %{state | port: nil, pending: %{}, buffer: ""}}
  end

  # Render call
  @impl true
  def handle_info({:request_timeout, id}, state) do
    case Map.pop(state.pending, id) do
      {nil, _} ->
        {:noreply, state}

      {entry, pending} ->
        GenServer.reply(entry.from, {:error, :timeout})
        {:noreply, %{state | pending: pending}}
    end
  end

  # Unhandled message
  @impl true
  def handle_info(msg, state) do
    Logger.debug("[IslandsSSRWorker] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Render call
  @impl true
  def handle_call({:render, %{module: module, props: props}}, from, state) do
    state = ensure_port_running(state)
    id = state.next_id
    msg = Jason.encode!(%{id: id, module: module, props: props})
    Port.command(state.port, msg <> "\n")

    timer_ref = Process.send_after(self(), {:request_timeout, id}, 10_000)
    pending = Map.put(state.pending, id, %{from: from, timer_ref: timer_ref})
    {:noreply, %{state | next_id: id + 1, pending: pending}}
  end

  # --- Helpers ---

  defp ensure_port_running(%{port: nil} = state), do: start_port!(state)
  defp ensure_port_running(state), do: state

  defp start_port!(state) do
    port =
      Port.open({:spawn_executable, System.find_executable(state.runtime)}, [
        :binary,
        :exit_status,
        :hide,
        :use_stdio,
        args: [state.worker_path]
      ])

    Logger.info("Started Node worker on port #{inspect(port)}")
    %{state | port: port}
  end

  defp split_buffer(buffer) do
    case String.split(buffer, "\n") do
      [single] ->
        {[], single}

      parts ->
        {lines, [rest]} = Enum.split(parts, -1)
        {lines, rest}
    end
  end

  defp handle_response(line, state) do
    case Jason.decode(line) do
      {:ok, %{"id" => id, "ok" => true, "data" => data}} ->
        reply(state, id, {:ok, data})

      {:ok, %{"id" => id, "ok" => false, "error" => error}} ->
        reply(state, id, {:error, error})

      other ->
        Logger.warning("Unexpected worker output: #{inspect(other)}")
        state
    end
  end

  defp reply(state, id, result) do
    {entry, pending} = Map.pop(state.pending, id)

    if entry do
      Process.cancel_timer(entry.timer_ref)
      GenServer.reply(entry.from, result)
    end

    %{state | pending: pending}
  end
end
