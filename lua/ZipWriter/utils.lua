local bit = require "ZipWriter.bit"

local lua_version do

local lua_version_t
lua_version = function()
  if not lua_version_t then 
    local version = assert(_VERSION)
    local maj, min = version:match("^Lua (%d+)%.(%d+)$")
    if maj then                         lua_version_t = {tonumber(maj),tonumber(min)}
    elseif math.type    then            lua_version_t = {5,3}
    elseif not math.mod then            lua_version_t = {5,2}
    elseif table.pack and not pack then lua_version_t = {5,2}
    else                                lua_version_t = {5,2} end
  end
  return lua_version_t[1], lua_version_t[2]
end

end

local LUA_MAJOR, LUA_MINOR = lua_version()

local LUA_VER_NUM = LUA_MAJOR * 100 + LUA_MINOR

local IS_WINDOWS = (package.config:sub(1,1) == '\\')

local DEFAULT_LOCAL_CP = 'utf-8'
if IS_WINDOWS then DEFAULT_LOCAL_CP = require("ZipWriter.win.cp").GetLocalCPName() end
local DEFAULT_CP_CONV = require "ZipWriter.charset" .convert

local function lshift(v, n)
  return math.floor(v * (2 ^ n))
end

local function rshift(v, n)
  return math.floor(v / (2 ^ n))
end

local function locale2dos(str)
  return DEFAULT_CP_CONV('cp866', DEFAULT_LOCAL_CP, str)
end

local function locale2utf8(str)
  return DEFAULT_CP_CONV('utf-8', DEFAULT_LOCAL_CP, str)
end

local function time2dos(file_ts)
  local t = os.date("*t", file_ts)

  return bit.bor(
    bit.lshift(t.year-1980, 25),
    bit.lshift(t.month,     21),
    bit.lshift(t.day,       16),
    bit.lshift(t.hour,      11),
    bit.lshift(t.min,        5),
    bit.rshift(t.sec+2,      1) -- 7z 
  )
end

local function time2filetime(file_ts)
  file_ts = 10000000 * (file_ts + 11644473600)
  local high = rshift(file_ts,32)
  local low  = file_ts - lshift(high, 32)
  return {low, high}
end

local M = {}

M.loc2utf8       = locale2utf8
M.loc2dos        = locale2dos
M.time2dos       = time2dos
M.time2filetime  = time2filetime
M.bit            = bit
M.IS_WINDOWS     = IS_WINDOWS
M.LUA_VER_NUM    = LUA_VER_NUM

return M