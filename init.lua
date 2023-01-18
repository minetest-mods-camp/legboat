--[[
  Legboat by ekl, licensed under the MIT license
]] --
-- Welcome to Spaghettiland
-- Function to find where to place the "knee" joint using a naive approach that may be very broken
local function knee_ik(bodyJoint, footPos)
  local uLen = 2
  local lLen = 3
  local result = footPos:offset(0, 3, 0) -- Initially position the knee directly above the foot

  -- Approximate where the joint should be through repeated clamping
  for _ = 1, 3 do
    -- Clamp result to lLen distance from foot
    result = result:subtract(footPos):normalize():multiply(lLen):add(footPos)
    -- Clamp result to uLen distance from body
    result = result:subtract(bodyJoint):normalize():multiply(uLen):add(bodyJoint)
  end
  return result
end

-- Inverse-kinematic the leg consisting of upper and lower
local function IK_leg(from, to, upper, lower)
  local knee = knee_ik(from, to)
  upper:move_to(from)
  upper:set_rotation(knee:subtract(from):dir_to_rotation(), true)
  lower:move_to(to)
  lower:set_rotation(to:subtract(knee):dir_to_rotation(), true)
end

local leg_target_offsets = {
  ["frontLeft"] = vector.new(3, -4, 3),
  ["frontRight"] = vector.new(-3, -4, 3),
  ["backLeft"] = vector.new(3, -4, -3),
  ["backRight"] = vector.new(-3, -4, -3)
}

local leg_offsets = {
  ["frontLeft"] = vector.new(0.75, 0, 0.75),
  ["frontRight"] = vector.new(-0.75, 0, 0.75),
  ["backLeft"] = vector.new(0.75, 0, -0.75),
  ["backRight"] = vector.new(-0.75, 0, -0.75)
}

-- See the abomination in globalstep for an idea of the structure
local function update_legboat(legboat, data)
  if not legboat.object:get_children() then -- Hacky fix for crash when destroyed
    return
  end

  local position = legboat.object:get_pos()
  local driver
  for _, child in pairs(legboat.object:get_children()) do
    if (not driver) and child:is_player() then
      driver = child
    else
      child:set_detach()
    end
  end

  local velocity = vector.new(0, 0, 0)
  if driver then
    local controls = driver:get_player_control()
    legboat.object:set_rotation(vector.new(0, driver:get_look_horizontal(), 0))
    if controls.sneak then
      driver:set_detach()
      driver:set_pos(legboat.object:get_pos():offset(0, 1, 0))
    end

    if controls.up then
      velocity.z = velocity.z + 5
    end
    if controls.down then
      velocity.z = velocity.z - 5
    end
    if controls.left then
      velocity.x = velocity.x - 5
    end
    if controls.right then
      velocity.x = velocity.x + 5
    end
  end

  local yPos = position.y
  local targetCount = 1
  for _, target in pairs(legboat._legboat_leg_targets) do
    yPos = yPos + target.y
    targetCount = targetCount + 1
  end

  velocity.y = ((yPos / targetCount) + 2 - position.y) * 10

  legboat.object:set_velocity(velocity:rotate(vector.new(0, legboat.object:get_yaw(), 0)))

  local stepSet = {}
  if not legboat._legboat_last_step_pos then
    legboat._legboat_last_step_pos = legboat.object:get_pos()
  elseif legboat._legboat_last_step_pos:distance(legboat.object:get_pos()) > 0.5 then
    -- Take a step
    stepSet[legboat._legboat_next_foot] = true
    legboat._legboat_next_foot = ({
      ["frontLeft"] = "backRight",
      ["backRight"] = "frontRight",
      ["frontRight"] = "backLeft"
    })[legboat._legboat_next_foot] or "frontLeft"
    legboat._legboat_leg_set = not legboat._legboat_leg_set
    legboat._legboat_last_step_pos = legboat.object:get_pos()
  end

  local rotation = legboat.object:get_rotation()
  for legSlot, leg in pairs(data.legs) do
    local leg = data.legs[legSlot]
    if not leg.upper then
      leg.upper = minetest.add_entity(legboat.object:get_pos(), "legboat:leg_upper")
      local entity = leg.upper:get_luaentity()
      entity._legboat_parent = legboat
      entity._legboat_leg = legSlot
    end
    if not leg.lower then
      leg.lower = minetest.add_entity(legboat.object:get_pos(), "legboat:leg_lower")
      local entity = leg.lower:get_luaentity()
      entity._legboat_parent = legboat
      entity._legboat_leg = legSlot
    end

    local resting = legboat.object:get_pos():add(leg_target_offsets[legSlot]:rotate(vector.new(0,
        legboat.object:get_yaw(), 0)))

    if not legboat._legboat_leg_targets[legSlot] or stepSet[legSlot] then
      local hit = Raycast(resting:offset(0, 6, 0), resting, false, false):next()
      if hit then
        legboat._legboat_leg_targets[legSlot] = hit.intersection_point
      else
        legboat._legboat_leg_targets[legSlot] = resting
      end
    end

    IK_leg(legboat.object:get_pos():add(leg_offsets[legSlot]:rotate(rotation)), legboat._legboat_leg_targets[legSlot],
        leg.upper, leg.lower)
  end
end

-- Globalstep that drives everything
minetest.register_globalstep(function(dtime)
  -- Parts to be matched to a legboat
  local legboats = {}
  local parts = {}
  for _, entity in pairs(minetest.luaentities) do
    if entity._legboat_entityType then
      if entity._legboat_entityType == "legboat" then
        legboats[entity] = {
          legs = {
            ["frontRight"] = {},
            ["frontLeft"] = {},
            ["backLeft"] = {},
            ["backRight"] = {}
          }
        }
      else
        parts[entity] = true
      end
    end
  end

  for part in pairs(parts) do
    local parent = legboats[part._legboat_parent]
    if parent then
      local leg = parent.legs[part._legboat_leg]
      if part._legboat_entityType == "upperLeg" then
        leg.upper = part.object
      elseif part._legboat_entityType == "lowerLeg" then
        leg.lower = part.object
      end
    else
      part.object:remove()
    end
  end

  -- Update all of the legboat legs
  for legboat, data in pairs(legboats) do
    update_legboat(legboat, data)
  end
end)

-- ENTITIES
--[[
  There are some custom properties used to keep track of vital data
  None of these entities have any on_step, because all of the updates are handled through the globalstep
]]

minetest.register_entity("legboat:legboat", {
  initial_properties = {
    visual = "mesh",
    mesh = "boats_boat.obj",
    textures = {"default_wood.png"}
  },
  physical = true,
  collisionbox = {-0.75, -0.1, -0.75, 0.75, 0.1, 0.1},
  _legboat_entityType = "legboat",
  _legboat_parent = false,
  _legboat_next_foot = "frontLeft",
  _legboat_last_step_pos = false, -- Stores the position it last stepped at
  _legboat_leg_targets = false, -- Will become a table
  on_activate = function(self)
    self._legboat_leg_targets = {}
  end,
  on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
    puncher:set_attach(self.object)
  end
})

minetest.register_entity("legboat:leg_upper", {
  initial_properties = {
    visual = "mesh",
    mesh = "legboat_leg_upper.obj",
    textures = {"default_wood.png"},
    pointable = false
  },
  _legboat_entityType = "upperLeg",
  _legboat_parent = false,
  _legboat_leg = "frontLeft"
})

minetest.register_entity("legboat:leg_lower", {
  initial_properties = {
    visual = "mesh",
    mesh = "legboat_leg_lower.obj",
    textures = {"default_wood.png"},
    pointable = false
  },
  _legboat_entityType = "lowerLeg",
  _legboat_parent = false,
  _legboat_leg = "frontLeft"
})

minetest.register_tool("legboat:legboat_egg", {
  description = "Legboat egg",
  inventory_image = "boats_inventory.png",
  on_use = function(itemstack, user, pointed_thing)
    minetest.add_entity(user:get_pos(), "legboat:legboat")
    return ItemStack()
  end
})

minetest.register_craft({
  output = "legboat:legboat_egg",
  recipe = {{"default:stick", "", "default:stick"}, {"", "boats:boat", ""}, {"default:stick", "", "default:stick"}}
})
