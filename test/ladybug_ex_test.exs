defmodule LadybugExTest do
  use ExUnit.Case
  doctest LadybugEx

  test "greets the world" do
    assert LadybugEx.hello() == :world
  end
end
