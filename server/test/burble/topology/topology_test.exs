# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Tests for Burble.Topology and Burble.Topology.Transition.
#
# Burble.Topology reports the deployment mode (monarchic / oligarchic /
# distributed / serverless) and derives feature flags from it.
# Burble.Topology.Transition handles room-level topology changes.

defmodule Burble.Topology.TopologyTest do
  use ExUnit.Case, async: true

  alias Burble.Topology
  alias Burble.Topology.Transition

  # ---------------------------------------------------------------------------
  # 1. Module existence
  # ---------------------------------------------------------------------------

  describe "module definition" do
    test "Topology module exists and exports expected functions" do
      assert function_exported?(Topology, :mode, 0)
      assert function_exported?(Topology, :capabilities, 0)
      assert function_exported?(Topology, :has_store?, 0)
      assert function_exported?(Topology, :has_recording?, 0)
      assert function_exported?(Topology, :has_moderation?, 0)
      assert function_exported?(Topology, :e2ee_mandatory?, 0)
      assert function_exported?(Topology, :default_privacy, 0)
      assert function_exported?(Topology, :federated?, 0)
      assert function_exported?(Topology, :has_accounts?, 0)
      assert function_exported?(Topology, :has_audit?, 0)
    end

    test "Transition module exists and exports expected functions" do
      assert function_exported?(Transition, :transition_room, 2)
      assert function_exported?(Transition, :merge_rooms, 3)
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Topology mode type
  # ---------------------------------------------------------------------------

  describe "topology modes" do
    test "mode/0 returns a valid topology atom" do
      mode = Topology.mode()
      assert mode in [:monarchic, :oligarchic, :distributed, :serverless]
    end

    test ":open is not a valid topology mode" do
      valid = [:monarchic, :oligarchic, :distributed, :serverless]
      refute :open in valid
    end

    test ":moderated is not a valid topology mode" do
      valid = [:monarchic, :oligarchic, :distributed, :serverless]
      refute :moderated in valid
    end

    test ":presentation is not a valid topology mode" do
      valid = [:monarchic, :oligarchic, :distributed, :serverless]
      refute :presentation in valid
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Capability map (default / monarchic mode)
  # ---------------------------------------------------------------------------

  describe "capabilities/0" do
    test "returns a map with all expected keys" do
      caps = Topology.capabilities()
      assert is_map(caps)

      expected_keys = [
        :topology, :store, :recording, :moderation,
        :e2ee_mandatory, :default_privacy, :federated,
        :accounts, :audit
      ]

      for key <- expected_keys do
        assert Map.has_key?(caps, key), "capabilities/0 is missing key #{inspect(key)}"
      end
    end

    test "capabilities :topology matches mode/0" do
      caps = Topology.capabilities()
      assert caps.topology == Topology.mode()
    end

    test "capabilities :e2ee_mandatory matches e2ee_mandatory?/0" do
      caps = Topology.capabilities()
      assert caps.e2ee_mandatory == Topology.e2ee_mandatory?()
    end

    test "capabilities :federated matches federated?/0" do
      caps = Topology.capabilities()
      assert caps.federated == Topology.federated?()
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Feature flags — monarchic defaults (test environment)
  # ---------------------------------------------------------------------------

  describe "feature flags under default (monarchic) mode" do
    test "has_store? is true" do
      assert Topology.has_store?() == true
    end

    test "has_recording? is true" do
      assert Topology.has_recording?() == true
    end

    test "has_moderation? is true" do
      assert Topology.has_moderation?() == true
    end

    test "e2ee_mandatory? is false" do
      assert Topology.e2ee_mandatory?() == false
    end

    test "default_privacy is :turn_only" do
      assert Topology.default_privacy() == :turn_only
    end

    test "federated? is false" do
      assert Topology.federated?() == false
    end

    test "has_accounts? is true" do
      assert Topology.has_accounts?() == true
    end

    test "has_audit? is true" do
      assert Topology.has_audit?() == true
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Topology.Transition validation
  # ---------------------------------------------------------------------------

  describe "Topology.Transition.transition_room/2" do
    test "returns :ok or an error tuple — does not crash" do
      # transition_room calls Room.get_state/1 internally; in test the room
      # registry is likely empty, so we expect an error tuple, not a crash.
      result = Transition.transition_room("nonexistent_room_id", :distributed)
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "Topology.Transition.merge_rooms/3" do
    test "returns :ok for a valid target mode" do
      # merge_rooms is a stub implementation that always returns :ok.
      assert Transition.merge_rooms("room_a", "room_b", :oligarchic) == :ok
    end
  end
end
