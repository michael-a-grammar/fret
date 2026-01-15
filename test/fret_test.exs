defmodule FretTest do
  use ExUnit.Case
  doctest Fret

  test "greets the world" do
    assert Fret.hello() == :world
  end
end
