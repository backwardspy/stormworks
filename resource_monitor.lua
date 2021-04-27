local W,H = 160,96

local LINE_HEIGHT = 10

local TYPE_DIESEL = 1

local TYPE_COLOURS = {
	{46, 25, 63}
}

local TYPE_NAMES = {
	"DIESEL"
}

function pump(from, to)
	output.setBool(1, true)
	output.setNumber(1, from)
	output.setNumber(2, to)
end

local tanks = {}
local selFrom, selTo = 0, 0	-- 0 = no selection

local renderQ = {}

local STATE_READY, STATE_SET_JOB, STATE_BALANCE, STATE_FILL = 0, 1, 2, 3

function stateReady()
	return {
		id = STATE_READY,
	}
end

function stateSetJob(from, to)
	return {
		id = STATE_SET_JOB,
		from = from,
		to = to,
	}
end

function stateBalance(a, b)
	local from, to
	if tanks[a].amount > tanks[b].amount then
		from, to = a, b
	else
		from, to = b, a
	end
	return {
		id = STATE_BALANCE,
		from = from,
		to = to,
		dir = balanceDir(from, to)
	}
end

function stateFill(from, to)
	return {
		id = STATE_FILL,
		from = from,
		to = to,
	}
end

local state = stateReady()

local touch = {
	{pressed=false, x=0, y=0},
	{pressed=false, x=0, y=0},
}

function onTick()
	-- protocol:
	-- 7 = the highest tank ID (1-indexed) N
	-- ... the below repeats N-1 times
	-- 8 = resource type (diesel = 1, more to come)
	-- 9 = resource amount
	-- 10 = resource capacity
	local lastTankID = input.getNumber(7)
	tanks = {}
	for i = 1, lastTankID do
		idx = (i - 1) * 3
		table.insert(tanks, {
			res_type=input.getNumber(8 + idx),
			amount=input.getNumber(9 + idx),
			capacity=input.getNumber(10 + idx),
		})
	end
	
	W,H = input.getNumber(1), input.getNumber(2)
	
	touch[1].pressed = input.getBool(1)
	touch[1].x, touch[1].y = input.getNumber(3), input.getNumber(4)
	touch[2].pressed = input.getBool(2)
	touch[2].x, touch[2].y = input.getNumber(5), input.getNumber(6)
	
	output.setBool(1, false)	-- disable pumps by default
	
	if state.id == STATE_READY then	-- allow selecting of tanks to operate on
		if touch[1].pressed then
			local selIdx = math.floor(touch[1].y / LINE_HEIGHT)
			if selIdx < #tanks then
				selFrom = selIdx + 1
			end
		else
			selFrom, selTo = 0, 0
		end
		
		if touch[2].pressed and selFrom > 0 then
			local selIdx = math.floor(touch[2].y / LINE_HEIGHT)
			if selIdx < #tanks and selIdx + 1 ~= selFrom then
				selTo = selIdx + 1
				
				state = stateSetJob(selFrom, selTo)
			end
		end
	elseif state.id == STATE_SET_JOB then	-- let the user choose between balance/fill/cancel
		if button(W-60, H-LINE_HEIGHT, 19, LINE_HEIGHT-1, "BAL") then
			state = stateBalance(state.from, state.to)
		elseif button(W-40, H-LINE_HEIGHT, 19, LINE_HEIGHT-1, "FIL") then
			state = stateFill(state.from, state.to)
		end
	elseif state.id == STATE_BALANCE then	-- attempt to match tank percentages
		local dir = balanceDir(state.from, state.to)
		if dir == state.dir then
			pump(state.from, state.to)
		else
			state = stateReady()
		end
	elseif state.id == STATE_FILL then		-- attempt to fill `to` or empty `from`
		local from, to = tanks[state.from], tanks[state.to]
		if from.amount == 0 then
			state = stateReady()
		elseif to.amount == to.capacity then
			state = stateReady()
		else
			pump(state.from, state.to)
		end
	end

	-- all non-ready states can be cancelled
	if state.id ~= STATE_READY then
		if button(W-20, H-LINE_HEIGHT, 19, LINE_HEIGHT-1, " X ") then
			selFrom, selTo = 0, 0
			state = stateReady()
		end
	end
end

function onDraw()
	local w, h = screen.getWidth(), screen.getHeight()
	
	-- screen border
	screen.setColor(255, 255, 255)
	screen.drawRect(1, 1, w-2, h-2)
	
	for i, tank in ipairs(tanks) do
		local y = 1 + (i - 1) * LINE_HEIGHT
		local percentage = tank.amount / tank.capacity
		
		-- level indicator
		screen.setColor(table.unpack(TYPE_COLOURS[tank.res_type]))
		screen.drawRectF(1, y+1, (w-2) * percentage, 8)
		
		-- border
		if selFrom == i then
			screen.setColor(30, 255, 30)	-- green = transferring from
		elseif selTo == i then
			screen.setColor(50, 50, 255)	-- blue = transferring to
		elseif percentage <= 0.2 then
			screen.setColor(255, 30, 30)	-- red = level warning
		else
			screen.setColor(255, 255, 255)
		end
		screen.drawRect(1, y, w-2, 8)
		
		-- text
		local capStr = tostring(math.floor(tank.capacity))
		local fill = string.len(capStr)
		borderedText(
			3,
			y+2,
			i .. "." ..
			string.format("%6s", TYPE_NAMES[tank.res_type]) ..
			" ... " ..
			string.format("%"..fill..".0f", tank.amount) .. "/" .. capStr .. " " ..
			string.format("%3.0f", percentage * 100) .. "%")
	end
	
	-- status bar
	screen.drawLine(1, h-LINE_HEIGHT, w-1, h-LINE_HEIGHT)
	local stateText = "READY"
	if state.id == STATE_SET_JOB then
		stateText = "#" .. state.from .. " -> #" .. state.to
	elseif state.id == STATE_BALANCE then
		stateText = "BALANCE " .. "#" .. state.from .. " AND #" .. state.to
	elseif state.id == STATE_FILL then
		stateText = "FILL " .. "#" .. state.from .. " -> #" .. state.to
	end
	screen.drawText(3, h-LINE_HEIGHT+3, stateText)
	
	-- render queue
	for _, job in ipairs(renderQ) do
		if job.shape == "rect" then
			screen.drawRect(job.x, job.y, job.w, job.h)
		elseif job.shape == "rectf" then
			screen.drawRectF(job.x, job.y, job.w, job.h)
		elseif job.shape == "text" then
			screen.drawText(job.x, job.y, job.text)
		end
	end
	renderQ = {}
end

function button(x, y, w, h, text)
	local t = touch[1]
	local pressed = t.pressed and t.x >= x and t.y >= y and t.x < x+w and t.y < y+h
	
	table.insert(renderQ, {
		shape=pressed and "rectf" or "rect",
		x=x, y=y,
		w=w, h=h,
	})

	table.insert(renderQ, {
		shape="text",
		x=x+2, y=y+3,
		text=text,
	})

	return pressed
end

function borderedText(x, y, text)
	screen.setColor(0, 0, 0)
	screen.drawText(x+1, y+1, text)
	screen.setColor(255, 255, 255)
	screen.drawText(x, y, text)
end

function balanceDir(from, to)
	local tf, tt = tanks[from], tanks[to]
	return sgn(tt.amount / tt.capacity - tf.amount / tf.capacity)
end

function sgn(v)
	return (v > 0 and 1) or (v == 0 and 0) or -1
end
