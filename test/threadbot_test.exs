defmodule ThreadbotTest do
  use ExUnit.Case
  doctest Threadbot

  test "greets the world" do
    assert Threadbot.hello() == :world
  end
end
