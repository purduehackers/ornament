defmodule BotConsumer do
  use Nostrum.Consumer

  alias Nostrum.Api
  alias Nostrum.Struct.Interaction
  alias Nostrum.Struct.Guild.Member

  def start_link do
    :ets.new(:channels, [:named_table, :public])
    :ets.new(:users, [:named_table, :public])
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:READY, ev, _ws_state}) do
    for g <- ev.guilds do
      Api.create_guild_application_command(g.id, %{
        name: "set_channel",
        description: "Starts bot on the channel",
        options: [
          %{
            type: 5, 
            name: "enable", 
            description: "Whether it is enabled or disabled for this channel", 
            required: true
          },
          %{
            type: 7, 
            name: "channel", 
            description: "The channel to enable/disable", 
            required: true
          },
        ]
      })
    end
  end

  def handle_event({:INTERACTION_CREATE, %Interaction{data: %{name: "set_channel"}} = ev, _ws_state}) do
    {:ok, guild} = Nostrum.Cache.GuildCache.get(ev.guild_id)
    user_perms = Member.guild_permissions(ev.member, guild)

    if user_perms |> Enum.member?(:manage_channels) do
      [%{name: "enable", value: enable}, %{name: "channel", value: channel_id}] = ev.data.options
      :ets.insert(:channels, {channel_id, enable})
      Api.create_interaction_response(ev, %{
        type: 4,
        data: %{ content: (if enable, do: "Enabled", else: "Disabled") }
      })
    else
      Api.create_interaction_response(ev, %{
        type: 4,
        data: %{ content: "Insufficient Permissions" }
      })
    end
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    if !msg.author.bot && (msg.embeds != [] || msg.attachments != []) do
      case :ets.lookup(:channels, msg.channel_id) do
        [{_, true}] ->
          start_time = ~N[2022-12-21 11:00:00.000000Z]
          current_time = NaiveDateTime.utc_now()
          diff = NaiveDateTime.diff(current_time, start_time) 
                 |> IO.inspect()
                 |> NaiveDateTime.from_gregorian_seconds
                 |> IO.inspect()

          name = case msg.member.nick do
            nil -> msg.author.username
            nick -> nick
          end
          thread_name = "#{name} - Day #{diff.day}"
          {:ok, thread} = Api.start_thread_with_message(msg.channel_id, msg.id, %{name: thread_name})
          Api.create_message(thread.id, "Congrats on sharing your progress!")

        _ -> 
          :ignore
      end
    end
  end

  # Default event handler, if you don't include this, your consumer WILL crash if
  # you don't have a method definition for each event type.
  def handle_event(_event) do
    :noop
  end
end

defmodule BotApplication do
  use Application

  @impl true
  def start(_type, _args) do
    children = [BotConsumer]
    IO.puts("Starting bot")
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
