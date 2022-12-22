defmodule BotConsumer do
  use Nostrum.Consumer

  alias Nostrum.Api
  alias Nostrum.Struct.Interaction
  alias Nostrum.Struct.Guild.Member
  alias Nostrum.Struct.Message

  def start_link do
    :ets.new(:channels, [:named_table, :public])
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

      Api.create_guild_application_command(g.id, %{
        name: "set_timeoffset",
        description: "Sets time offset",
        options: [
          %{
            type: 4, 
            name: "offset", 
            description: "The time offset in hours after EST", 
            required: true
          },
        ]
      })

      Api.create_guild_application_command(g.id, %{
        name: "list_commits",
        description: "Lists a user's commits",
        options: [
          %{
            type: 6, 
            name: "user", 
            description: "The user whose commits to list", 
            required: true
          },
        ]
      })
    end
  end

  def handle_event({:INTERACTION_CREATE, %Interaction{data: %{name: "list_commits"}} = ev, _ws_state}) do
    [%{name: "user", value: user}] = ev.data.options
    {:ok, guild} = Nostrum.Cache.GuildCache.get(ev.guild_id)

    member = guild.members[user]
    hacker = Hacker.find_by_member(member)

    name = case member.nick do
      nil -> member.user.username
      nick -> nick
    end
    message = "Commits by #{name}:\n#{Hacker.format_commits(hacker)}"
    Api.create_interaction_response(ev, %{
      type: 4,
      data: %{ content: message }
    })
  end

  def handle_event({:INTERACTION_CREATE, %Interaction{data: %{name: "set_timeoffset"}} = ev, _ws_state}) do
    hacker = case :ets.lookup(:users, ev.member.user.id) do
      [{_, hacker}] -> hacker
      _ -> %Hacker{member: ev.member}
    end

    [%{name: "offset", value: offset}] = ev.data.options
    :ets.insert(:users, {ev.member.user.id, %{hacker | time_offset: offset}})

    Api.create_interaction_response(ev, %{
      type: 4,
      data: %{ content: "Set offset to #{offset}" }
    })
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
    {:ok, guild} = Nostrum.Cache.GuildCache.get(msg.guild_id)
    member = guild.members[msg.author.id]

    url_regex = ~r/https?:\/\/[a-zA-Z0-9@:%._\+~#=]{2,256}\.[a-z]{2,10}\b([a-zA-Z0-9@:%-_\+.~#!?&]*)/
    message_has_project = (msg.embeds != []) || (msg.attachments != []) || String.match?(msg.content, url_regex)

    if !msg.author.bot && message_has_project do
      hacker = Hacker.find_by_member(member)
      offset = hacker.time_offset

      case :ets.lookup(:channels, msg.channel_id) do
        [{_, true}] ->
          start_time = NaiveDateTime.add(~N[2022-12-21 05:00:00.000000Z], offset * 60 * 60, :second)
          current_time = NaiveDateTime.utc_now()
          diff = NaiveDateTime.diff(current_time, start_time) 
                 |> NaiveDateTime.from_gregorian_seconds
          day = diff.day

          updated_commits = %{hacker.commits | day => Message.to_url(msg)}
          updated_hacker = %{hacker | commits: updated_commits}
          :ets.insert(:users, {msg.author.id, updated_hacker})

          name = case msg.member.nick do
            nil -> msg.author.username
            nick -> nick
          end
          thread_name = "#{name} - Day #{day}"

          {:ok, thread} = Api.start_thread_with_message(msg.channel_id, msg.id, %{name: thread_name})
          Api.create_message(thread.id, "Congrats on sharing your progress!")
          Api.create_message(thread.id, "Previous Commits:\n#{Hacker.format_commits(updated_hacker)}")

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
    children = [
      BotConsumer,
      HackerStore
    ]

    IO.puts("Starting bot")
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
