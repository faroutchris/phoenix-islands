defmodule SelfServiceWeb.IslandSsrWorker do
  use GenServer
  require Logger

  @worker_path Application.app_dir(:selfservice_test, "priv/static/assets/ssr/worker.js")
  @initial_state %{
    id: nil,
    port: nil,
    next_id: 1,
    buffer: "",
    pending: %{}
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def render do
    GenServer.call(__MODULE__, {:render, %{module: "Some component", props: %{test: "Hello"}}})
  end

  @impl true
  def init(_args \\ []) do
    {:ok, start_port!(@initial_state)}
  end

  defp ensure_port_running(%{port: nil} = state), do: start_port!(state)
  defp ensure_port_running(state), do: state

  defp start_port!(state) do
    port =
      Port.open({:spawn_executable, System.find_executable("node")}, [
        :binary,
        :exit_status,
        :hide,
        :use_stdio,
        args: [@worker_path]
      ])

    %{state | port: port}
  end

  # Handle node buffer
  @impl true
  def handle_info({port, {:data, chunk}}, %{port: port} = state) do
    # Append the new chunk to the current state.buffer
    buffer = state.buffer <> chunk
    # Process all complete lines (\n), save incomplete lines in `rest`
    {lines, rest} = split_buffer(buffer)

    state =
      lines
      # Save the rest of the buffer in the next state
      |> Enum.reduce(%{state | buffer: rest}, fn line, acc ->
        line = String.trim(line)
        if line == "", do: acc, else: handle_response(line, acc)
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
        {entry, pending} = Map.pop(state.pending, id)
        if entry do
          Process.cancel_timer(entry.timer_ref)
          GenServer.reply(entry.from, {:ok, data})
        end
        %{state | pending: pending}

      {:ok, %{"id" => id, "ok" => false, "error" => error}} ->
        {entry, pending} = Map.pop(state.pending, id)
        if entry do
          Process.cancel_timer(entry.timer_ref)
          GenServer.reply(entry.from, {:error, error})
        end
        %{state | pending: pending}

      other ->
        Logger.warning("Unexpected worker output: #{IO.inspect(other)}")
        state
    end
  end
end
