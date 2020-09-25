-- A pure combat meter for the Sophisticated, the High Class, the Extraordinairy

local time = time
local date = date
local bit = bit
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local C_ClassColor = C_ClassColor
local COMBATLOG_DEFAULT_COLORS = COMBATLOG_DEFAULT_COLORS
local COMBATLOG_OBJECT_AFFILIATION_MASK = COMBATLOG_OBJECT_AFFILIATION_MASK
local UnitGUID = UnitGUID
local COMBATLOG_OBJECT_AFFILIATION_RAID = COMBATLOG_OBJECT_AFFILIATION_RAID
local COMBATLOG_OBJECT_SPECIAL_MASK = COMBATLOG_OBJECT_SPECIAL_MASK
local COMBATLOG_OBJECT_NONE = COMBATLOG_OBJECT_NONE
local COMBATLOG_OBJECT_TYPE_GUARDIAN = COMBATLOG_OBJECT_TYPE_GUARDIAN
local COMBATLOG_OBJECT_TYPE_PET = COMBATLOG_OBJECT_TYPE_PET

local MAX_BARS = 10
local BAR_HEIGHT = 22
local WINDOW_WIDTH = 500
local UPDATE_INTERVAL = 1
local COMBAT_END_TIMER = 5

local LEVEL_HISTORY = "history"
local LEVEL_METRIC = "metric"
local LEVEL_ACTORS = "actors"
local LEVEL_ACTIONS = "actions"
local LEVEL_DETAILS = "details"

-- local METRIC_DMG_IN = "Damage Taken"
-- local METRIC_HEAL_OUT = "Healing"
-- local METRIC_HEAL_IN = "Healing Taken"

-- metric handlers

-- {
	-- label: string that represents the metric on the metric list
	-- filter: array of combat log event strings mapped to true that this metric handles
	-- value: a function that returns a value that the actor owning the metric should be sorted based on
		-- params
			-- metric = an actor's metric specific data
	-- handle_combatlog_event: handles a combat log event that matched the metric filter
		-- params
			-- self
			-- event
			-- source_metric = metric specific container for the event's source actor
			-- source_guid
			-- source_flags
			-- target_metric = metric specific container for the event's target actor
			-- target_guid
			-- target_flags
			-- ... = the event specific payload from the combat log event
		-- return
			-- true if the event would start a new combat segment if none are active, false otherwise
-- }


local METRIC_DMG_OUT = {
	new_action = function(self, id, name, school)
		return {
			id = id,
			name = name,
			school = school,
			owner = nil,
			total = 0,
			higher = nil,
			lower = nil,
			hits = {
				-- tick
				[true] = {
					-- crit
					[true] = {
						count = 0,
						highest = nil,
						lowest = nil,
						average = 0,
						total = 0,
					},
					-- hit
					[false] = {
						count = 0,
						highest = nil,
						lowest = nil,
						average = 0,
						total = 0,
					}
				},
				-- direct
				[false] = {
					-- crit
					[true] = {
						count = 0,
						highest = nil,
						lowest = nil,
						average = 0,
						total = 0,
					},
					-- hit
					[false] = {
						count = 0,
						highest = nil,
						lowest = nil,
						average = 0,
						total = 0,
					}
				},
			},
		}
	end,
	label = "Damage",
	filter = {
		["SWING_DAMAGE"] = true,
		["RANGE_DAMAGE"] = true,
		["SPELL_DAMAGE"] = true,
		["SPELL_PERIODIC_DAMAGE"] = true,
	},
	value = function(metric)
		return metric.total or 0
	end,
	new = function()
		return {
			total = 0,
			actions = {}
		}
	end,
	handle_combatlog_event = function(self, event, source_metric, source_guid, source_flags, target_metric, target_guid, target_flags, ...)

		if not source_guid then
			return false
		end

		local tick, environmental_type, spell_id, spell_name, spell_school, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, is_oh
		if string.find(event, "SWING_") then
			amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, is_oh = ...
			-- TODO
			spell_id, spell_name, spell_school = 0, "Auto Attack", school
		elseif string.find(event, "ENVIRONMENTAL_") then
			environmental_type, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, is_oh = ...
			-- TODO
			spell_id, spell_name, spell_school = -1, "Environment", school
		else
			spell_id, spell_name, spell_school, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, is_oh = ...
			--TODO spell, spell_periodic, spell_building
		end
		--print(source.name.." damage "..amount.." to "..target.name)

		-- TODO stuff like aoe eye corruption, don't count as dmg done but count dmg taken
		if source_guid == target_guid then
			return
		end

		if string.find(event, "SPELL_PERIODIC") then
			tick = true
		else
			tick = false
		end

		local action = source_metric.actions[spell_id]
		if not action then
			action = self:new_action(spell_id, spell_name, school)
			source_metric.actions[spell_id] = action
		end

		local instance = action.hits[tick][critical]
		instance.count = instance.count + 1
		instance.total = instance.total + amount
		instance.average = instance.total / instance.count

		if instance.highest == nil or instance.highest < amount then
			instance.highest = amount
		end
		if instance.lowest == nil or instance.lowest > amount then
			instance.lowest = amount
		end

		action.total = action.total + amount
		source_metric.total = (source_metric.total or 0) + amount

		return true
	end
}

local pretty_time = function(time)
	if not time then return "" end
	if (time > 60) then
		return ("%dm %ds"):format(math.floor(time / 60), time % 60)
	else
		return ("%ds"):format(time)
	end
end

local pretty_number = function(number)
	if not number then return "" end
	if (number >= 1e9) then
		return ("%.2fb"):format(number / 1e9)
	elseif (number >= 1e6) then
		return ("%.2fm"):format(number / 1e6)
	elseif (number >= 1e3) then
		return ("%.2fk"):format(number / 1e3)
	else
		return ("%d"):format(number)
	end
end

local backdrop = {
	bgFile = [[Interface\Buttons\WHITE8x8]],
	edgeFile = [[Interface\Buttons\WHITE8x8]],
	tile = false,
	tileSize = 0,
	edgeSize = 1,
	insets = {
		left = 0,
		right = 0,
		top = 0,
		bottom = 0
	},
}

local gen_backdrop = function(frame, ...)
	if not frame.SetBackdrop then
		Mixin(frame, BackdropTemplateMixin)
	end
	frame:SetBackdrop(backdrop)
	frame:SetBackdropBorderColor(0, 0, 0, 1)
	if (...) then
		frame:SetBackdropColor(...)
	else
		frame:SetBackdropColor(.15, .15, .15, 1)
	end
end

local gen_string = function(parent, size, flags, font, h_justify, v_justify, name)
	local string = parent:CreateFontString(name, "OVERLAY")
	string:SetFont(font or [[Interface\Addons\Parse\fonts\gotham_ultra.ttf]], size or 15, flags or "THINOUTLINE")
	if h_justify then
		if h_justify == "MIDDLE" then h_justify = "CENTER" end
		string:SetJustifyH(h_justify)
	end
	if v_justify then
		if v_justify == "CENTER" then v_justify = "MIDDLE" end
		string:SetJustifyV(v_justify)
	end
	return string
end

local gen_statusbar = function(parent, w, h, fg_color, bg_color)
	local bar = CreateFrame("StatusBar", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
	bar:SetSize(w, h)
	bar:SetStatusBarTexture([[Interface\Buttons\WHITE8x8]])
	bar:SetBackdrop(backdrop)
	bar:GetStatusBarTexture():SetDrawLayer("BORDER", -1);
	bar:SetBackdropBorderColor(0, 0, 0, 1)

	if fg_color then
		bar:SetStatusBarColor(unpack(fg_color))
	end

	if bg_color then
		bar:SetBackdropColor(unpack(bg_color))
	else
		bar:SetBackdropColor(.15, .15, .15, 1)
	end

	return bar
end

local update_history = function(current, state, parse)
	local count = parse.data_history.count
	for i = 1, MAX_BARS do
		local first_entry = 1
		if count > MAX_BARS then
			first_entry = math.max(math.min(count - MAX_BARS + 1, parse.scroll), 1)
			parse.scroll = first_entry
			parse.count:SetText(string.format("%d / %d", first_entry, count))
		else
			parse.count:SetText("")
		end

		local bar = parse.bars[i]
		local segment = parse.data_history.segments[i + first_entry - 1]
		if segment then
			bar.name_text:SetText(segment.timestamp)
			local desc = ""
			if segment.name then
				desc = segment.name.." "
			end
			if segment.combat_end then
				desc = desc..pretty_time(segment.combat_end - segment.combat_start)
			end
			bar.description:SetText(desc)
			bar.context = segment
			bar:SetValue(1)
			bar:SetStatusBarColor(.5, .5, .5)
			bar:Show()
		else
			bar:Hide()
		end
	end
end

local update_metric = function(current, state, parse)
	local count = #parse.metrics
	for i = 1, MAX_BARS do
		local first_entry = 1
		if count > MAX_BARS then
			first_entry = math.max(math.min(count - MAX_BARS + 1, parse.scroll), 1)
			parse.scroll = first_entry
			parse.count:SetText(string.format("%d / %d", first_entry, count))
		else
			parse.count:SetText("")
		end

		local bar = parse.bars[i]
		local metric = parse.metrics[i + first_entry - 1]
		if metric then
			bar.name_text:SetText(metric.label)
			bar.description:SetText("")
			bar.context = metric
			bar:SetValue(1)
			bar:SetStatusBarColor(.5, .5, .5)
			bar:Show()
		else
			bar:Hide()
		end
	end
end

local update_sorted = function(parse, entries, get_value, segment_start, segment_end, get_color)
	local highest_entry, highest_metric = nil, 0
	local count = 0
	for key, entry in pairs(entries) do
		entry.higher = nil
		entry.lower = nil

		if entry.owner then
			entry = nil
		else
			if get_value(entry) > 0 then
				count = count + 1
			else
				entry = nil
			end
		end

		if entry then
			if not highest_entry then
				highest_entry = entry
			else
				local current = highest_entry

				while get_value(current) > get_value(entry) and current.lower do
					current = current.lower
				end

				if get_value(current) > get_value(entry) then
					entry.upper = current
					entry.lower = current.lower
					current.lower = entry
				else
					if current == highest_entry then
						highest_entry = entry
						entry.upper = nil
					else
						entry.upper = current.upper
						current.upper.lower = entry
					end
					current.upper = entry
					entry.lower = current
				end
			end
		end
	end

	local first_entry = 1
	if count > MAX_BARS then
		first_entry = math.max(math.min(count - MAX_BARS + 1, parse.scroll), 1)
		parse.scroll = first_entry
		parse.count:SetText(string.format("%d / %d", first_entry, count))
	else
		parse.count:SetText("")
	end

	if highest_entry then
		highest_metric = get_value(highest_entry)
	end
	local current_entry, current_metric = highest_entry, highest_metric
	if current_entry then
		local i = 1
		while i < first_entry do
			current_entry = current_entry.lower
			i = i + 1
		end

		current_metric = get_value(current_entry)
	end

	local segment_length = (segment_end or time()) - segment_start
	if segment_length < 1 then segment_length = 1 end

	for i = 1, MAX_BARS do
		local bar = parse.bars[i]
		if not current_entry or current_metric == 0 then
			bar:Hide()
		else
			bar:Show()
			bar:SetValue(current_metric / highest_metric)
			local metric_per_second
			metric_per_second = current_metric / segment_length
			bar.name_text:SetText(current_entry.name)
			bar.description:SetText(pretty_number(current_metric).." - "..pretty_number(metric_per_second))
			local color = get_color(current_entry)
			if not color then
				color = {r = .5, g = .5, b = .5}
			end
			bar:SetStatusBarColor(color.r * .75, color.g * .75, color.b * .75)
			bar.context = current_entry
			current_entry = current_entry.lower
			if current_entry then
				current_metric = get_value(current_entry)
			end
		end
	end
end

local update_details = function(current, state, parse)
	local action = state[LEVEL_ACTIONS].context

	local i = 1
	if action.hits[false][false].count + action.hits[false][true].count > 0 then
		parse.bars[i].name_text:SetText((action.hits[false][false].count + action.hits[false][true].count).." hits")
		parse.bars[i].description:SetText(pretty_number(action.hits[false][false].total + action.hits[false][true].total))
		parse.bars[i]:SetValue(1)
		parse.bars[i]:SetStatusBarColor(.75, .75, .75)
		parse.bars[i]:Show()
		i = i + 1

		parse.bars[i].name_text:SetText(string.format("  %d normal", action.hits[false][false].count))
		parse.bars[i].description:SetText(string.format("%s / %s / %s", pretty_number(action.hits[false][false].lowest), pretty_number(action.hits[false][false].average), pretty_number(action.hits[false][false].highest)))
		parse.bars[i]:SetValue(1)
		parse.bars[i]:SetStatusBarColor(.5, .5, .5)
		parse.bars[i]:Show()
		i = i + 1

		parse.bars[i].name_text:SetText(string.format("  %d crit", action.hits[false][true].count))
		parse.bars[i].description:SetText(string.format("%s / %s / %s", pretty_number(action.hits[false][true].lowest), pretty_number(action.hits[false][true].average), pretty_number(action.hits[false][true].highest)))
		parse.bars[i]:SetValue(1)
		parse.bars[i]:SetStatusBarColor(.5, .5, .5)
		parse.bars[i]:Show()
		i = i + 1
	end

	if action.hits[true][false].count + action.hits[true][true].count > 0 then
		parse.bars[i].name_text:SetText((action.hits[true][false].count + action.hits[true][true].count).." ticks")
		parse.bars[i].description:SetText(pretty_number(action.hits[true][false].total + action.hits[true][true].total))
		parse.bars[i]:SetValue(1)
		parse.bars[i]:SetStatusBarColor(.75, .75, .75)
		parse.bars[i]:Show()
		i = i + 1

		parse.bars[i].name_text:SetText(string.format("  %d normal", action.hits[true][false].count))
		parse.bars[i].description:SetText(string.format("%s / %s / %s", pretty_number(action.hits[true][false].lowest), pretty_number(action.hits[true][false].average), pretty_number(action.hits[true][false].highest)))
		parse.bars[i]:SetValue(1)
		parse.bars[i]:SetStatusBarColor(.5, .5, .5)
		parse.bars[i]:Show()
		i = i + 1

		parse.bars[i].name_text:SetText(string.format("  %d crit", action.hits[true][true].count))
		parse.bars[i].description:SetText(string.format("%s / %s / %s", pretty_number(action.hits[true][true].lowest), pretty_number(action.hits[true][true].average), pretty_number(action.hits[true][true].highest)))
		parse.bars[i]:SetValue(1)
		parse.bars[i]:SetStatusBarColor(.5, .5, .5)
		parse.bars[i]:Show()
		i = i + 1
	end

	for b = i, MAX_BARS do
		parse.bars[b]:Hide()
	end
end

local parse = CreateFrame("Frame", "ParseFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
gen_backdrop(parse, .15, .15, .15, .6)
parse:SetSize(WINDOW_WIDTH, BAR_HEIGHT)
parse:SetPoint("RIGHT", UIParent, "RIGHT", -5, 0)

parse:SetScript("OnMouseDown", function(self, click)
	if click == "RightButton" then
		self.data_history:clear()
		self.display_state:clear()

		self.scroll = 1
		self:update_label()
		self.display_state:update(self)
	end
end)

parse.bg = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate")
gen_backdrop(parse.bg, .15, .15, .15, .6)
parse.bg:SetSize(WINDOW_WIDTH, BAR_HEIGHT * MAX_BARS)
parse.bg:SetPoint("TOPLEFT", parse, "BOTTOMLEFT", 0, 1)

parse.label = gen_string(parse, nil, nil, nil, "LEFT")
parse.label:SetPoint("LEFT", parse, "LEFT", 3, 0)
parse.label:SetPoint("RIGHT", parse, "RIGHT", -3, 0)

parse.count = gen_string(parse, nil, nil, nil, "RIGHT")
parse.count:SetPoint("RIGHT", parse, "RIGHT", -3, 0)

parse.scroll = 1
parse.bars = {}
parse.event_filter = {
	-- ["SPELL_HEAL"] = 1,
	-- ["SPELL_PERIODIC_HEAL"] = 1,
	-- ["SPELL_ABSORBED"] = 1,
}
parse.metrics = {}

parse.add_metric = function(self, metric)
	table.insert(self.metrics, metric)
	for event in pairs(metric.filter) do
		self.event_filter[event] = true
	end
end

parse.data_history = {
	active = nil,
	count = 0,
	segments = {},
	get = function(self, start)
		if self.count > 0 then
			for i = 1, self.count do
				if self.segments[i].combat_start == start then
					return self.segments[i]
				end
			end
		end
		return nil
	end,
	add = function(self, data)
		self.count = self.count + 1
		self.segments[self.count] = data
	end,
	clear = function(self)
		self.segments = {}
		self.active = nil
		self.count = 0
	end
}

parse.display_state = {
	current = nil,
	[LEVEL_HISTORY] = {
		state = LEVEL_HISTORY,
		up = nil,
		down = LEVEL_METRIC,
		-- data segment
		context = nil,
		update = update_history,
		get_label = function(self)
			return self.context.timestamp
		end,
	},
	[LEVEL_METRIC] = {
		state = LEVEL_METRIC,
		up = LEVEL_HISTORY,
		down = LEVEL_ACTORS,
		-- metric
		context = nil,
		update = update_metric,
		get_label = function(self)
			return self.context.label
		end,
	},
	[LEVEL_ACTORS] = {
		state = LEVEL_ACTORS,
		up = LEVEL_METRIC,
		down = LEVEL_ACTIONS,
		-- actor
		context = nil,
		update = function(self, state, parse)
			local segment = state[LEVEL_HISTORY].context
			-- TODO group vs outside
			update_sorted(
				parse,
				segment.group,
				function(actor)
					return state[LEVEL_METRIC].context.value(actor.metrics[state[LEVEL_METRIC].context.label])
				end,
				segment.combat_start,
				segment.combat_end,
				function(actor)
					if actor.guid and string.len(actor.guid) > 0 then
						local _, class = GetPlayerInfoByGUID(actor.guid)
						if class then
							return C_ClassColor.GetClassColor(class)
						else
							return {r = .5, g = .5, b = .5}
						end
					else
						return {r = .5, g = .5, b = .5}
					end
				end
			)
		end,
		get_label = function(self)
			return self.context.name
		end,
	},
	[LEVEL_ACTIONS] = {
		state = LEVEL_ACTIONS,
		up = LEVEL_ACTORS,
		down = LEVEL_DETAILS,
		context = nil,
		update = function(self, state, parse)
			local segment = state[LEVEL_HISTORY].context
			update_sorted(
				parse,
				state[LEVEL_ACTORS].context.metrics[state[LEVEL_METRIC].context.label].actions,
				function(action)
					return action.total
				end,
				segment.combat_start,
				segment.combat_end,
				function(action)
					return COMBATLOG_DEFAULT_COLORS.schoolColoring[action.school]
				end
			)
		end,
		get_label = function(self)
			return self.context.name
		end,
	},
	[LEVEL_DETAILS] = {
		state = LEVEL_DETAILS,
		up = LEVEL_ACTIONS,
		down = nil,
		context = nil,
		update = update_details,
	},
	clear = function(self)
		self.current = self[LEVEL_HISTORY]
		self[LEVEL_HISTORY].context = nil
		self[LEVEL_METRIC].context = nil
		self[LEVEL_ACTORS].context = nil
		self[LEVEL_ACTIONS].context = nil
		self[LEVEL_DETAILS].context = nil
	end,
	update = function(self, parse)
		self.current:update(self, parse)
	end
}
parse.display_state.current = parse.display_state[LEVEL_HISTORY]

local pet_scanner = CreateFrame("GameTooltip", "ParsePetScanner", nil, "GameTooltipTemplate")
pet_scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
parse.pet_scanner = pet_scanner

local unitname_summon_titles = {}
local added_count, found_count = 1, 1
local title_string = _G["UNITNAME_SUMMON_TITLE"..found_count]
while title_string do
	if title_string ~= "%s" then
		unitname_summon_titles[added_count] = title_string
		added_count = added_count + 1
	end
	found_count = found_count + 1
	title_string = _G["UNITNAME_SUMMON_TITLE"..found_count]
end

pet_scanner.parse_owner = function(self, guid)
	self:ClearLines()
	self:SetHyperlink('unit:'..guid)
	if self.TextLeft1 and self.TextLeft1:GetText() and self.TextLeft2 and self.TextLeft2:GetText() then
		--print(PetScannerTooltipTextLeft1:GetText().." =============== "..PetScannerTooltipTextLeft2:GetText())
	end
	local i = 1
	while _G["UNITNAME_SUMMON_TITLE"..i] do
		local owner = string.match(self.TextLeft2 and self.TextLeft2:GetText() or '', "^"..string.gsub(_G["UNITNAME_SUMMON_TITLE"..i], "%%s", "(%%D+)").."$")
		if owner then
			--print("owner for "..PetScannerTooltipTextLeft1:GetText().." is "..owner)
			if not UnitGUID(owner) then
				--print("owner GUID is nil")
			else
				--print("GUID: "..UnitGUID(owner))
			end
			--print("using: ".._G["UNITNAME_SUMMON_TITLE"..i])
			return UnitGUID(owner), owner
		end
		i = i + 1
	end
	if self.TextLeft1 and self.TextLeft1:GetText() then
		--print("no owner found for "..PetScannerTooltipTextLeft1:GetText())
	end
	return nil, nil
end

parse.update_label = function(self)
	if self.display_state.current.up then
		local up_level = self.display_state[self.display_state.current.up]
		local state_string = up_level:get_label()
		while up_level.up do
			up_level = self.display_state[up_level.up]
			state_string = up_level:get_label().." > "..state_string
		end
		self.label:SetText(state_string)
	else
		self.label:SetText("Parse")
	end
end
parse:update_label()

for i = 1, MAX_BARS do
	local bar = gen_statusbar(parse, 1, BAR_HEIGHT, {i / 10, i / 10, i / 10}, {0, 0, 0, 0})
	bar:SetScript("OnMouseDown", function(self, click)
		if click == "LeftButton" then
			if parse.display_state.current.down then
				parse.display_state.current.context = self.context
				parse.display_state.current = parse.display_state[parse.display_state.current.down]
				parse.scroll = 1
			end
		elseif click == "RightButton" then
			if parse.display_state.current.up then
				parse.display_state.current = parse.display_state[parse.display_state.current.up]
				parse.display_state.current.context = nil
				parse.scroll = 1
			end
		end
		parse:update_label()
		parse.display_state:update(parse)
	end)

	bar:SetMinMaxValues(0, 1)
	bar.name_text = gen_string(bar)
	bar.name_text:SetPoint("LEFT", bar, "LEFT", 3, 0)
	bar.description = gen_string(bar)
	bar.description:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
	if i == 1 then
		bar:SetPoint("TOPLEFT", parse, "BOTTOMLEFT", 0, 1)
		bar:SetPoint("TOPRIGHT", parse, "BOTTOMRIGHT", 0, 1)
	else
		bar:SetPoint("TOPLEFT", parse.bars[i - 1], "BOTTOMLEFT", 0, 1)
		bar:SetPoint("TOPRIGHT", parse.bars[i - 1], "BOTTOMRIGHT", 0, 1)
	end
	bar:Hide()
	parse.bars[i] = bar
end

local handle_spell_summon = function(self, hide_caster, source_guid, source_name, source_flags, source_raid_flags, dest_guid, dest_name, dest_flags, dest_raid_flags, ...)
	-- catch summon events and set them up to merge with the owner
	-- usually spawned with npc/neutral dest_flags but future events from them come with group/pet/friendly source_flags
	if bit.band(source_flags, COMBATLOG_OBJECT_AFFILIATION_MASK) <= COMBATLOG_OBJECT_AFFILIATION_RAID then
		local sources = self.data_history.active.group
		-- TODO merge same name pets (dire beast etc.)
		--print(string.format(dest_name.." flags: 0X%8.8X", dest_flags))
		sources[dest_guid] = self:new_actor(dest_guid, dest_name)
		if not sources[source_guid] then
			sources[source_guid] = self:new_actor(source_guid, source_name)
		end
		sources[dest_guid].owner = sources[source_guid]
		local print_str = ""
		if source_name then
			print_str = source_name.." "
		end
		print_str = print_str.."summoned"
		if dest_name then
			print_str = print_str..": "..dest_name
		end
		print(print_str)
	end
end

local handle_unit_died = function(self, hide_caster, source_guid, source_name, source_flags, source_raid_flags, dest_guid, dest_name)
	--print(dest_name.." died")
end

parse.event_overrides = {
	["SPELL_SUMMON"] = handle_spell_summon,
	["UNIT_DIED"] = handle_unit_died,
}

parse.new_actor = function(self, guid, name)
	local metrics = {}
	for _, metric in ipairs(self.metrics) do
		metrics[metric.label] = metric:new()
	end
	return {
		guid = guid,
		name = name,
		owner = nil,
		metrics = metrics,
		higher = nil,
		lower = nil,
	}
end

parse.new_segment = function(self, start, name, event)
	return {
		name = name,
		event = event,
		last_combat_event = nil,
		combat_start = start,
		combat_end = nil,
		timestamp = date("%X"),
		group = {},
		outside = {},
	}
end

parse.on_combatlog_event = function(self, timestamp, event, hide_caster, source_guid, source_name, source_flags, source_raid_flags, dest_guid, dest_name, dest_flags, dest_raid_flags, ...)

	if self.event_overrides[event] and self.data_history.active then
		self.event_overrides[event](self, hide_caster, source_guid, source_name, source_flags, source_raid_flags, dest_guid, dest_name, dest_flags, dest_raid_flags, ...)
		return
	end

	if not self.event_filter[event] then
		return
	end
	
	-- TODO same same
	-- print("timestamp: "..timestamp)
	-- print("time(): "..time())

	local data = self.data_history.active
	if not data then
		data = self:new_segment(time())
	end

	local sources, targets
	
	if bit.band(source_flags, COMBATLOG_OBJECT_SPECIAL_MASK) == COMBATLOG_OBJECT_NONE then
		print(string.format("event %s empty source for dest: %s %s flags: 0X%8.8X", event, dest_guid, dest_name, dest_flags))
		return
	end

	if bit.band(source_flags, COMBATLOG_OBJECT_AFFILIATION_MASK) > COMBATLOG_OBJECT_AFFILIATION_RAID then
		-- source is outside group
		if bit.band(dest_flags, COMBATLOG_OBJECT_AFFILIATION_MASK) > COMBATLOG_OBJECT_AFFILIATION_RAID then
			-- source and target not in group, drop this event
			return
		else
			-- target is in group
			sources = data.outside
		end
	else
		sources = data.group
	end
	--sources = data.group

	if bit.band(dest_flags, COMBATLOG_OBJECT_AFFILIATION_MASK) > COMBATLOG_OBJECT_AFFILIATION_RAID then
		-- destination is outside group
		targets = data.outside
	else
		-- destination is in group
		targets = data.group
	end

	local source = sources[source_guid]
	if not source and source_name then
		
		-- self summon pet
		-- SPELL_SUMMON,Player-105-0A15268E,"Jayeasy-Thunderhorn",0x511,0x0,Pet-0-3133-1861-18439-15651-0102CA93DD,"ThomasOMaley",0x1228,0x0,83244,"Call Pet 4",0x1
		-- 511: COMBATLOG_OBJECT_TYPE_PLAYER, COMBATLOG_OBJECT_CONTROL_PLAYER, COMBATLOG_OBJECT_REACTION_FRIENDLY, COMBATLOG_OBJECT_AFFILIATION_MINE
		-- 1228: COMBATLOG_OBJECT_TYPE_PET, COMBATLOG_OBJECT_CONTROL_NPC, COMBATLOG_OBJECT_REACTION_NEUTRAL, COMBATLOG_OBJECT_AFFILIATION_OUTSIDER

		-- SPELL_DAMAGE,Pet-0-3133-1861-18439-15651-0202CA93DD,"ThomasOMaley",0x1111,0x0,Creature-0-3133-1861-18439-137119-00003E7F0F,"Taloc",0x10a48,0x0,201754,"Stomp",0x1,Creature-0-3133-1861-18439-137119-00003E7F0F,0000000000000000,44177844,74812000,0,0,2700,3,10,100,0,-262.70,-254.94,1148,0.1745,123,8139,5536,-1,1,0,0,0,1,nil,nil
		-- 1111: COMBATLOG_OBJECT_TYPE_PET, COMBATLOG_OBJECT_CONTROL_PLAYER, COMBATLOG_OBJECT_REACTION_FRIENDLY, COMBATLOG_OBJECT_AFFILIATION_MINE

		-- raid summon pet
		-- SPELL_SUMMON,Player-105-0A1C7F38,"Kaeve-Thunderhorn",0x514,0x0,Pet-0-3133-1861-18439-103326-0102CCE6A4,"Spirit Beast",0x1228,0x0,883,"Call Pet 1",0x1
		-- 1228

		-- SPELL_DAMAGE,Pet-0-3133-1861-18439-103326-0202CCE6A4,"Spirit Beast",0x1114,0x0,Creature-0-3133-1861-18439-137119-00003E7F0F,"Taloc",0x10a48,0x0,201754,"Stomp",0x1,Creature-0-3133-1861-18439-137119-00003E7F0F,0000000000000000,44121935,74812000,0,0,2700,3,10,100,0,-262.70,-254.94,1148,0.1745,123,3874,5270,-1,1,0,0,0,nil,nil,nil
		-- 1114: COMBATLOG_OBJECT_TYPE_PET, COMBATLOG_OBJECT_CONTROL_PLAYER, COMBATLOG_OBJECT_REACTION_FRIENDLY, COMBATLOG_OBJECT_AFFILIATION_RAID

		-- raid summon guardian
		-- SPELL_SUMMON,Player-105-0960C409,"Bruldan-Thunderhorn",0x514,0x0,Creature-0-3133-1861-18439-135816-00003E816D,"Vilefiend",0xa28,0x0,264119,"Summon Vilefiend",0x4
		-- a28: COMBATLOG_OBJECT_TYPE_NPC, COMBATLOG_OBJECT_CONTROL_NPC, COMBATLOG_OBJECT_REACTION_NEUTRAL, COMBATLOG_OBJECT_AFFILIATION_OUTSIDER

		-- SPELL_DAMAGE,Creature-0-3133-1861-18439-135816-00003E816D,"Vilefiend",0x2114,0x0,Creature-0-3133-1861-18439-140393-00003E7F0F,"Tendril of Gore",0x10a48,0x0,267997,"Bile Spit",0x8,Creature-0-3133-1861-18439-140393-00003E7F0F,0000000000000000,1730130,2244360,0,0,2700,1,0,0,0,-276.81,-240.14,1148,3.6988,122,17041,8114,-1,8,0,0,0,1,nil,nil
		-- 2114: COMBATLOG_OBJECT_TYPE_GUARDIAN, COMBATLOG_OBJECT_CONTROL_PLAYER, COMBATLOG_OBJECT_REACTION_FRIENDLY, COMBATLOG_OBJECT_AFFILIATION_RAID

		-- if summon event was missed we might need to find the owner and merge a pet here
		if (bit.band(source_flags, COMBATLOG_OBJECT_TYPE_GUARDIAN) == COMBATLOG_OBJECT_TYPE_GUARDIAN
				or bit.band(source_flags, COMBATLOG_OBJECT_TYPE_PET) == COMBATLOG_OBJECT_TYPE_PET)
				and bit.band(source_flags, COMBATLOG_OBJECT_AFFILIATION_MASK) <= COMBATLOG_OBJECT_AFFILIATION_RAID then
				
			-- if guid is nil but name isn't, try to look up the owner by name
			local owner_guid, owner_name = self.pet_scanner:parse_owner(source_guid)
			if owner_name then
				if not owner_guid then
					for guid, actor in pairs(sources) do
						if actor.name == owner_name then
							if actor.guid then
								print("found owner by name, guid is: "..actor.guid)
								owner_guid = actor.guid
							else
								print("found owner by name, but guid is nil")
								--owner_guid = actor.name
							end
						end
					end
				end
				if owner_guid then
					if not sources[owner_guid] then
						print("owner: "..owner_name.." not found, creating")
						sources[owner_guid] = self:new_actor(owner_guid, owner_name)
					end
					source = self:new_actor(source_guid, source_name)
					sources[source_guid] = source
					source.owner = sources[owner_guid]
				end
			else
				-- didn't find owner (thing from beyond), keep seperate
			end
		else
			source = self:new_actor(source_guid, source_name)
			sources[source_guid] = source
		end
	end
	if not source then
		source = self:new_actor(nil, "")
	elseif source.owner then
		source = source.owner
	end

	local target = targets[dest_guid]

	if not target and dest_name then

		-- if summon event was missed we might need to find the owner and merge a pet here
		if (bit.band(dest_flags, COMBATLOG_OBJECT_TYPE_GUARDIAN) == COMBATLOG_OBJECT_TYPE_GUARDIAN
				or bit.band(dest_flags, COMBATLOG_OBJECT_TYPE_PET) == COMBATLOG_OBJECT_TYPE_PET)
				and bit.band(dest_flags, COMBATLOG_OBJECT_AFFILIATION_MASK) <= COMBATLOG_OBJECT_AFFILIATION_RAID then

			local owner_guid, owner_name = self.pet_scanner:parse_owner(dest_guid)
			if owner_guid then
				if not targets[owner_guid] then
					targets[owner_guid] = self:new_actor(owner_guid, owner_name)
				end
				target = self:new_actor(dest_guid, dest_name)
				target.owner = targets[owner_guid]
			end
			-- didn't find owner (thing from beyond), keep seperate
		else
			target = self:new_actor(dest_guid, dest_name)
			targets[dest_guid] = target
		end
	end

	if not target then
		target = self:new_actor(nil, "")
	end

	local start_combat
	for _, handler in ipairs(self.metrics) do
		if handler.filter[event] then
			start_combat = start_combat or handler:handle_combatlog_event(event, source.metrics[handler.label], source_guid, source_flags, target.metrics[handler.label], dest_guid, dest_flags, ...)
		end
	end

	if start_combat then
		-- so it can end the segment based on a timer if no actual combat/encounter event started it
		data.last_combat_event = timestamp

		if not self.data_history.active then
			-- starting combat based off a combat log event happening before any actual combat/encounter event
			print(event.." started combat: "..source_name.." -> "..dest_name)
			self:enter_combat(data)
		end
		if not data.name then
			-- give it a name based on a hostile actor if combat started from an event that didn't give a name
			data.name = bit.band(source_flags, COMBATLOG_OBJECT_AFFILIATION_MASK) > COMBATLOG_OBJECT_AFFILIATION_RAID and source_name or dest_name
		end
	end
end

parse.on_update = function(self, elapsed)
	if self.last_update then
		self.last_update = self.last_update + elapsed
		if (self.last_update > UPDATE_INTERVAL) then
			self.last_update = 0

			self.display_state:update(self)
			if not self.data_history.active.event and time() - self.data_history.active.last_combat_event > COMBAT_END_TIMER then
				self:exit_combat()
			end
		end
	end
end

parse.enter_combat = function(self, data, start, name, event)
	self:SetScript("OnUpdate", self.on_update)

	-- TODO optional change
	self.display_state[LEVEL_METRIC].context = METRIC_DMG_OUT
	self.display_state.current = self.display_state[LEVEL_ACTORS]

	if not data then
		data = self:new_segment(start, name, event)
	end

	self.data_history:add(data)
	self.data_history.active = data
	print("combat start from event: "..(event or "combatlog"))

	self.display_state[LEVEL_HISTORY].context = data

	self.last_update = 0
	self:update_label()
end

parse.exit_combat = function(self)
	self:SetScript("OnUpdate", nil)

	self.data_history.active.combat_end = time()
	self.data_history.active = nil
	print("combat end")
end

parse.bg:SetScript("OnMouseDown", function(self, click)
	if click == "RightButton" then
		if parse.display_state.current.up then
			parse.display_state.current = parse.display_state[parse.display_state.current.up]
			parse.display_state.current.context = nil
		end
	end
	parse:update_label()
	parse.display_state:update(parse)
end)

parse.bg:SetScript("OnMouseWheel", function(self, direction)
	if direction > 0 then
		parse.scroll = math.max(parse.scroll - 1, 0)
	else
		parse.scroll = parse.scroll + 1
	end
	parse.display_state:update(parse)
end)
parse.bg:EnableMouseWheel(1)

parse:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
parse:RegisterEvent("PLAYER_REGEN_ENABLED")
parse:RegisterEvent("PLAYER_REGEN_DISABLED")
parse:RegisterEvent("ENCOUNTER_START")
parse:RegisterEvent("ENCOUNTER_END")
parse:SetScript("OnEvent", function(self, event, ...)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		self:on_combatlog_event(CombatLogGetCurrentEventInfo())
	elseif event == "PLAYER_REGEN_ENABLED" then
		if self.data_history.active.event == "PLAYER_REGEN_DISABLED" then
			self:exit_combat()
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		if self.data_history.active then
			if not self.data_history.active.event then
				self.data_history.active.event = event
			end
		else
			self:enter_combat(nil, time(), nil, event)
		end
	elseif event == "ENCOUNTER_START" then
		local _, name = ...
		if self.data_history.active then
			self.data_history.active.event = event
		else
			self:enter_combat(nil, time(), name, event)
		end
	elseif event == "ENCOUNTER_END" then
		if self.data_history.active.event == "ENCOUNTER_START" then
			self:exit_combat()
		end
	end
end)

parse:add_metric(METRIC_DMG_OUT)
