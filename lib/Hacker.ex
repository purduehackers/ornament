defmodule Hacker do
  @enforce_keys [:member]
  defstruct [:member, time_offset: 0, commits: (for i <- 1..10, do: {i, nil}, into: %{})]

  def find_by_member(member) do
    case :ets.lookup(:users, member.user.id) do
      [{_, hacker}] -> hacker
      _ -> %Hacker{member: member}
    end
  end

  def format_commits(hacker) do
    for {day, commit} <- hacker.commits, commit != nil do
      "Day #{day}: #{commit}"
    end |> Enum.join("\n")
  end

  def manually_add_commits(id, commits) do
    hacker = find_by_member(id)
    updated_hacker = %{hacker | commits: Map.merge(hacker.commits, commits)}
    :ets.insert(:users, {id, updated_hacker})
    HackerStore.backup()
  end
end

defmodule HackerStore do
  use GenServer

  @file_location ~c[/store/hackers.bin]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    if match?({:error, _}, :ets.file2tab(@file_location)) do
      :ets.new(:users, [:named_table, :public])
    end

    :timer.send_interval(30 * 1000, :backup)

    {:ok, nil}
  end

  @impl true
  def handle_info(:backup, _) do
    backup()
    {:noreply, nil}
  end

  def backup() do
    IO.puts("Backing Up")
    :ets.tab2file(:users, @file_location)
  end
end