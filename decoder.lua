local mode_name = "decoder"
local M = {}
_G[mode_name] = M
_G.ival = 0

package.loaded[mode_name] = M
setmetatable(M, {__index = _G })
setfenv(1, M)


function process_struct(t, proto)
	for i, v in ipairs(t) do
		if type(v[1]) == "string" and type(v[2]) == "number" then
			process_item(v, proto)
		elseif v.case and v.case_ctrl then
			process_case(v, proto)
		elseif v.loop and v.loop_ctrl then
			process_loop(v, proto)
		else
			-- no such case
		end
	end
end



local decode_value = {}

function process_item(v, proto)
	local type_map = {
		[1] = "uint8",
		[2] = "uint16",
		[4] = "uint32",
	}

	v.name = v[1]
	v.length = v[2]
	
	local temp
	if type_map[v.length] then
		temp = ProtoField[type_map[v.length]](v.name, v.name, v.base, v.valuestring, v.mask)
	else
		temp = ProtoField.bytes(v.name)
	end
	table.insert(proto.fields, temp)
	v.t = temp
	if v.eval and type(v.eval) == "string" then
		v.eval_f = loadstring(" return " .. v.eval)
	end
	
	if v.loop then
		if not v.loop_ctrl then	v.loop_ctrl = v.name end
		process_loop(v, proto)
	elseif v.case then
		if not v.case_ctrl then v.case_ctrl = v.name end
		process_case(v, proto)
	end
end

function process_loop(v, proto)
	local temp = ProtoField.bytes(v.loop_name or "Loop-Element")
	table.insert(proto.fields, temp)
	v.loop_t = temp

	process_struct(v.loop, proto)
end

function process_case(v, proto)
	for i, c in pairs(v.case) do
		process_struct(c, proto)
	end
end

function transform(t, proto)
	process_struct(t, proto)
end

function d_item(v, tree, buffer, offset, func, func_ret)
	
	if v.length > 0 and v.length < 4 then
		ival = buffer(offset, v.length):uint()
	end
	
	local temp = tree:add(v.t, buffer(offset, v.length))
	
	if v.eval_f then
		v.value = v.eval_f()
	elseif v.length <= 4 and v.length > 0 then
		v.value = ival
	end
	
	decode_value[v.name] = v.value
	
	if func then func(func_ret, v, buffer, offset, temp) end
	
	if func_ret then func_ret[v.name] = v.value end
	
	if not v.sharenext then
		offset = offset + v.length
	end

	if v.loop then
		offset = d_loop(v, temp, buffer, offset, func, func_ret)
	elseif v.case then
		offset = d_case(v, tree, buffer, offset, func, func_ret)
	end
	return offset
end

function d_loop(v, tree, buffer, offset, func, func_ret)
	local temp
	if v.loop_ctrl then
		if type(v.loop_ctrl) == "number" then
			v.l_ctrl = v.loop_ctrl
		else
			v.l_ctrl = decode_value[v.loop_ctrl]
		end
		if v.l_ctrl and v.l_ctrl > 0 then
			for i = 1, v.l_ctrl do
				temp = tree:add(v.loop_t, buffer(offset, 0))
				temp:append_text(" " .. i)
				offset = decode_struct(v.loop, temp, buffer, offset, func, func_ret)
			end
		end
	end	

	return offset
end

function d_case(v, tree, buffer, offset, func, func_ret)
	v.c_ctrl = decode_value[v.case_ctrl]
	if v.c_ctrl then
		if v.case[v.c_ctrl] then
			offset = decode_struct(v.case[v.c_ctrl], tree, buffer, offset, func, func_ret)
		elseif v.case.default then
			offset = decode_struct(v.case.default, tree, buffer, offset, func, func_ret)
		end
	end
	return offset
end

function decode_struct(msgt, tree, buffer, off, func, func_ret)
	local offset = off
	for i, v in ipairs(msgt) do
		if v.length and v.name then
			offset = d_item(v, tree, buffer, offset, func, func_ret)
		elseif v.loop and v.loop_ctrl then
			offset = d_loop(v, tree, buffer, offset, func, func_ret)
		elseif v.case and v.case_ctrl then
			offset = d_case(v, tree, buffer, offset, func, func_ret)
		end
	end	
	return offset
end

--[[
local fmap = {}
fmap.check = function(name, t)
	if fmap[name] then
		return fmap[name]
	elseif t then
		fmap[name] = t
		table.insert(upos_pro.fields, t)
		return t
	else --error
		return t
	end
end

for i, v in ipairs(L3_fixpart) do
	local t = ProtoField[ v[2] ](v[1])
	fmap.check(v[1], t)
end
--]]

function get_strings(buffer, offset, num)
	local i = 0
	local cur = offset - 1
	return function ()
		while i < num do
			while true do
				cur = cur + 1
				if buffer(cur, 1):uint() == 0 then
					i = i + 1
					return cur + 1
				end
			end
		end
		return nil
	end
end



