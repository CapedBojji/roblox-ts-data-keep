--!nocheck
--!optimize 2

local MockStorePages = require(script.MockStorePages)

local MockStore = {}
MockStore.__index = MockStore

function MockStore.new()
	return setmetatable({
		_data = {},
		_dataVersions = {},
	}, MockStore)
end

function didyield(f, ...)
	local finished = false
	local data
	coroutine.wrap(function(...)
		data = f(...)
		finished = true
	end)(...)
	return not finished, data
end

local function deepCopy(t)
	local copy = {}

	if not t then
		return copy
	end

	for key, value in pairs(t) do
		if type(value) == "table" then
			copy[key] = deepCopy(value)
		else
			copy[key] = value
		end
	end

	return copy
end

local function createNewVersion(self, key, data)
	if self._dataVersions[key] == nil then
		self._dataVersions[key] = {}
	end

	local versionData = {
		Version = #self._dataVersions[key] + 1,
		CreatedTime = os.time(),
		Deleted = false,
	}

	table.insert(self._dataVersions[key], { versionData, deepCopy(data) })
end

function MockStore:GetAsync(key)
	return self._data[key]
end

function MockStore:SetAsync(key, value)
	self._data[key] = value

	return createNewVersion(self, key, value)
end

function MockStore:UpdateAsync(key, callback)
	local value = self._data[key]
	local yielded, newValue = didyield(callback, value)

	if yielded then
		error("UpdateAsync yielded!")
		return value
	end

	return self:SetAsync(key, newValue)
end

function MockStore:ListVersionsAsync(key, sortDirection, minDate, maxDate, limit)
	limit = limit or 1

	local versions = self._dataVersions[key]

	if not versions then
		return MockStorePages({}, sortDirection == Enum.SortDirection.Ascending, limit)
	end

	local filteredVersions = {}

	for _, versionData in ipairs(versions) do
		local createdTime = versionData[1].CreatedTime

		minDate = minDate or 0
		maxDate = maxDate or math.huge

		if createdTime >= minDate and createdTime <= maxDate then
			table.insert(filteredVersions, 1, versionData[1])
		end
	end

	table.sort(filteredVersions, function(a, b)
		return a.CreatedTime < b.CreatedTime
	end)

	return MockStorePages(filteredVersions, sortDirection == Enum.SortDirection.Ascending, limit)
end

function MockStore:GetVersionAsync(key, version)
	local versions = self._dataVersions[key]

	if not versions then
		return
	end

	for _, versionData in ipairs(versions) do
		if versionData[1].Version == version then
			return versionData[2]
		end
	end

	return
end

return MockStore