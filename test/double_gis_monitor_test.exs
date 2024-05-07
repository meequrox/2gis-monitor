defmodule DoubleGisMonitorTest do
  use ExUnit.Case
  doctest DoubleGisMonitor

  test "Dummy event building" do
    e = %DoubleGisMonitor.Db.Event{}
    assert(e.uuid == nil)
  end
end
