defmodule Coflux.MapUtilsTest do
  use ExUnit.Case, async: true

  import Coflux.MapUtils

  describe "delete_in/2" do
    test "empty path" do
      assert delete_in(%{a: 1}, []) == %{a: 1}
    end

    test "deletes top-level entry" do
      assert delete_in(%{a: 1, b: 2}, [:a]) == %{b: 2}
    end

    test "deletes nested entry" do
      assert delete_in(%{a: %{b: 1, c: 2}, d: 3}, [:a, :b]) == %{a: %{c: 2}, d: 3}
    end

    test "deletes nested entry and removes empty map" do
      assert delete_in(%{a: %{b: 1}, c: 2}, [:a, :b]) == %{c: 2}
    end

    test "ignores non-existent top-level entry" do
      assert delete_in(%{}, [:a]) == %{}
    end

    test "ignores non-existent nested entry" do
      assert delete_in(%{a: %{b: 1}}, [:a, :c]) == %{a: %{b: 1}}
    end

    test "deletes last remaining item" do
      assert delete_in(%{a: %{b: 1}}, [:a, :b]) == %{}
    end

    test "retains existing empty maps" do
      assert delete_in(%{a: %{}, b: %{}}, [:a]) == %{b: %{}}
    end

    test "deletes from mapset" do
      assert delete_in(%{a: %{b: MapSet.new([1, 2])}}, [:a, :b, 1]) == %{a: %{b: MapSet.new([2])}}
    end

    test "deletes empty mapset" do
      assert delete_in(%{a: %{b: MapSet.new([1])}}, [:a, :b, 1]) == %{}
    end

    test "missing path" do
      assert delete_in(%{}, [:a, :b]) == %{}
    end
  end
end
