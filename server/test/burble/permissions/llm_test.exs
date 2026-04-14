defmodule Burble.Permissions.LLMTest do
  use ExUnit.Case
  doctest Burble.Permissions

  describe "LLM permission validation" do
    test "LLM role has correct permissions" do
      llm_perms = Burble.Permissions.role_template(:llm)
      
      assert MapSet.member?(llm_perms, :join_room)
      assert MapSet.member?(llm_perms, :speak)
      assert MapSet.member?(llm_perms, :chat_send)
      
      # LLM should NOT have these human-facing controls
      refute MapSet.member?(llm_perms, :hand_raise)
      refute MapSet.member?(llm_perms, :mute_self)
      refute MapSet.member?(llm_perms, :mute_others)
    end

    test "validate_llm_permissions works correctly" do
      valid_llm_perms = MapSet.new([:join_room, :speak, :chat_send])
      assert Burble.Permissions.validate_llm_permissions(valid_llm_perms)
      
      # Test invalid permutations
      invalid_perms1 = MapSet.new([:join_room, :speak, :chat_send, :hand_raise])
      refute Burble.Permissions.validate_llm_permissions(invalid_perms1)
      
      invalid_perms2 = MapSet.new([:join_room, :speak])  # Missing chat_send
      refute Burble.Permissions.validate_llm_permissions(invalid_perms2)
    end

    test "is_llm? correctly identifies LLM participants" do
      llm_perms = MapSet.new([:join_room, :speak, :chat_send])
      assert Burble.Permissions.is_llm?(llm_perms)
      
      member_perms = MapSet.new([:join_room, :speak, :chat_send, :hand_raise, :mute_self])
      refute Burble.Permissions.is_llm?(member_perms)
    end

    test "LLM permissions are subset of member permissions" do
      llm_perms = Burble.Permissions.role_template(:llm)
      member_perms = Burble.Permissions.role_template(:member)
      
      # All LLM permissions should be in member permissions
      assert MapSet.subset?(llm_perms, member_perms)
      
      # But member has additional permissions LLM doesn't
      refute llm_perms == member_perms
    end
  end
end