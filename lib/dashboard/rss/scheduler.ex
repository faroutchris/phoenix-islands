defmodule Dashboard.RSS.Scheduler do
  use GenServer

  alias Dashboard.RSS.IngestService

  # 60 seconds
  @interval 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_next_update()

    {:ok, state}
  end

  def schedule_next_update do
    IO.puts("Scheduled next work update in #{@interval} ms")
    Process.send_after(self(), :update, @interval)
  end

  def handle_info(:update, state) do
    IngestService.update_feeds()

    schedule_next_update()

    {:noreply, state}
  end
end
