local global_update = 0.5

--wieldview
local time = 0

wieldview = {
	wielded_item = {},
	transform = {},
}

dofile(minetest.get_modpath(minetest.get_current_modname()).."/transform.lua")

wieldview.get_item_texture = function(self, item)
	local texture = "blank.png"
	if item ~= "" then
		if minetest.registered_items[item] then
			if minetest.registered_items[item].inventory_image ~= "" then
				texture = minetest.registered_items[item].inventory_image
			end
		end
		-- Get item image transformation, first from group, then from transform.lua
		local transform = minetest.get_item_group(item, "wieldview_transform")
		if transform == 0 then
			transform = wieldview.transform[item]
		end
		if transform then
			-- This actually works with groups ratings because transform1, transform2, etc.
			-- have meaning and transform0 is used for identidy, so it can be ignored
			texture = texture.."^[transform"..tostring(transform)
		end
	end
	return texture
end

wieldview.update_wielded_item = function(self, player)
	if not player then
		return
	end
	local name = player:get_player_name()
	local stack = player:get_wielded_item()
	local item = stack:get_name()
	if not item then
		return
	end
	if self.wielded_item[name] then
		if player:get_meta():get_int("show_wielded_item") == 2 then
			item = ""
		end
		if self.wielded_item[name] == item then
			return
		end
		armor.textures[name].wielditem = self:get_item_texture(item)
		armor:update_player_visuals(player)
	end
	self.wielded_item[name] = item
end

minetest.register_globalstep(function(dtime)
	time = time + dtime
	if time > global_update then
		for _,player in ipairs(minetest.get_connected_players()) do
			wieldview:update_wielded_item(player)
		end
		time = 0
	end
end)

--wieldview3d

wieldview3d = {}

dofile(minetest.get_modpath(minetest.get_current_modname()).."/location.lua")

local player_wielding = {}
local verify_time = minetest.settings:get("wieldview3d_verify_time")
local wield_scale = minetest.settings:get("wieldview3d_scale")

verify_time = verify_time and tonumber(verify_time) or 10
wield_scale = wield_scale and tonumber(wield_scale) or 0.25 -- default scale

local location = {
	"Arm_Right",          -- default bone
	{x=0, y=5.5, z=3},    -- default position
	{x=-90, y=225, z=90}, -- default rotation
	{x=wield_scale, y=wield_scale},
}

local function add_wield_entity(player)
	if not player or not player:is_player() then
		return
	end
	local name = player:get_player_name()
	local pos = player:get_pos()
	if name and pos and not player_wielding[name] then
		pos.y = pos.y + 0.5
		local object = minetest.add_entity(pos, "wieldview3d:wield_entity", name)
		if object then
			object:set_attach(player, location[1], location[2], location[3])
			object:set_properties({
				textures = {"wieldview3d:hand"},
				visual_size = location[4],
			})
			player_wielding[name] = {item="", location=location}
		end
	end
end

local function sq_dist(a, b)
	local x = a.x - b.x
	local y = a.y - b.y
	local z = a.z - b.z
	return x * x + y * y + z * z
end

local wield_entity = {
	physical = false,
	collisionbox = {-0.125,-0.125,-0.125, 0.125,0.125,0.125},
	visual = "wielditem",
	textures = {"wieldview3d:hand"},
	wielder = nil,
	timer = 0,
	static_save = false,
	pointable = false,
}

function wield_entity:on_activate(staticdata)
	if staticdata and staticdata ~= "" then
		self.wielder = staticdata
		return
	end
	self.object:remove()
end

function wield_entity:on_step(dtime)
	if self.wielder == nil then
		return
	end
	self.timer = self.timer + dtime
	if self.timer < global_update then
		return
	end
	local player = minetest.get_player_by_name(self.wielder)
	if player == nil or not player:is_player() or
			sq_dist(player:get_pos(), self.object:get_pos()) > 3 then
		self.object:remove()
		return
	end
	local wield = player_wielding[self.wielder]
	local stack = player:get_wielded_item()
	local item = stack:get_name() or ""
	if wield and item ~= wield.item then
		local def = minetest.registered_items[item] or {}
		if def.inventory_image ~= "" then
			item = ""
		end
		wield.item = item
		if item == "" then
			item = "wieldview3d:hand"
		end
		local loc = wieldview3d.location[item] or location
		if loc[1] ~= wield.location[1] or
				not vector.equals(loc[2], wield.location[2]) or
				not vector.equals(loc[3], wield.location[3]) then
			self.object:set_attach(player, loc[1], loc[2], loc[3])
			wield.location = {loc[1], loc[2], loc[3]}
		end
		self.object:set_properties({
			textures = {item},
			visual_size = loc[4],
		})
	end
	self.timer = 0
end

local function table_iter(t)
	local i = 0
	local n = table.getn(t)
	return function ()
		i = i + 1
		if i <= n then
			return t[i]
		end
	end
end

local player_iter = nil

local function verify_wielditems()
	if player_iter == nil then
		local names = {}
		local tmp = {}
		for player in table_iter(minetest.get_connected_players()) do
			local name = player:get_player_name()
			if name then
				tmp[name] = true;
				table.insert(names, name)
			end
		end
		player_iter = table_iter(names)
		-- clean-up player_wielding table
		for name, wield in pairs(player_wielding) do
			player_wielding[name] = tmp[name] and wield
		end
	end
	 -- only deal with one player per server step
	local name = player_iter()
	if name then
		local player = minetest.get_player_by_name(name)
		if player and player:is_player() then
			local pos = player:get_pos()
			pos.y = pos.y + 0.5
			local wielding = false
			local objects = minetest.get_objects_inside_radius(pos, 1)
			for _, object in pairs(objects) do
				local entity = object:get_luaentity()
				if entity and entity.wielder == name then
					if wielding then
						-- remove duplicates
						object:remove()
					end
					wielding = true
				end
			end
			if not wielding then
				player_wielding[name] = nil
				add_wield_entity(player)
			end
		end
		return minetest.after(0, verify_wielditems)
	end
	player_iter = nil
	minetest.after(verify_time, verify_wielditems)
end

minetest.after(verify_time, verify_wielditems)

minetest.register_entity("wieldview3d:wield_entity", wield_entity)

minetest.register_item("wieldview3d:hand", {
	type = "none",
	wield_image = "blank.png",
})

minetest.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	wieldview.wielded_item[name] = ""
	minetest.after(0.1, function(pname)
		local pplayer = minetest.get_player_by_name(pname)
		if pplayer then
			wieldview:update_wielded_item(player)
		end
	end, name)
	minetest.after(2, add_wield_entity, player)
end)
