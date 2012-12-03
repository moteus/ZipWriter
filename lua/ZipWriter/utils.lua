local IS_LUA52 = not rawget(_G, 'setfenv')

local function prequire(m) 
  local ok, err = pcall(require, m) 
  if not ok then return nil, err end
  return err
end

local bit   = require( IS_LUA52 and "bit32" or "bit" )
local date  = prequire "ZipWriter.date"

local IS_WINDOWS = (package.config:sub(1,1) == '\\')

local DEFAULT_LOCAL_CP = 'utf-8'
if IS_WINDOWS then DEFAULT_LOCAL_CP = require("ZipWriter.win.cp").GetLocalCPName() end
local DEFAULT_CP_CONV = require "ZipWriter.charset" .convert

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

local time2filetime
if date and date().asfiletime then 
  time2filetime = function(file_ts)
    return assert(date(file_ts)):asfiletime()
  end
end

local M = {}

M.loc2utf8       = locale2utf8
M.loc2dos        = locale2dos
M.time2dos       = time2dos
M.time2filetime  = time2filetime
M.bit            = bit

return M