defmodule Hacker do
  @enforce_keys [:member]
  defstruct [:member, time_offset: 0, commits: (for i <- 1..10, do: {i, nil}, into: %{})]

  def find_by_member(member) do
    if :ets.whereis(:users) == :undefined, do: HackerStore.wait_loop(5)
    
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
    :ets.insert(:users, {hacker.member.user.id, updated_hacker})
    HackerStore.backup()
  end
end

defmodule HackerStore do
  use GenServer

  @file_location ~c[/store/hackers.bin]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def wait_loop(n) do
    if Enum.member?(:ets.all(), :users), do: :ets.delete(:users)

    if match?({:error, _}, :ets.file2tab(@file_location)) do
      if n == 0 do 
        IO.puts("Fellback to empty users table")
        :ets.new(:users, [:named_table, :public])
      else
        Process.sleep(1000)
        wait_loop(n - 1)
      end
    else
      IO.puts("Successfully loaded table")
    end
  end

  @impl true
  def init(:ok) do
    wait_loop(10)

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
