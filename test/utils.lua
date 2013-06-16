local lunit    = require "lunit"
local skip     = function (msg) return function() lunit.fail("#SKIP: " .. msg) end end
local IS_LUA52 = _VERSION >= 'Lua 5.2'
local IS_WINDOWS = package.config:sub(1,1) == '\\'

local TEST_CASE = function (name)
  if not IS_LUA52 then
    module(name, package.seeall, lunit.testcase)
    setfenv(2, _M)
  else
    return lunit.module(name, 'seeall')
  end
end

local function str_replace(str, pos, sub)
  assert((pos > 0) and (pos <= (#str + 1)))
  return string.sub(str, 1, pos-1) .. sub .. string.sub(str, pos+#sub)
end

assert ("abc456789"    == str_replace("123456789", 1,  'abc'))
assert ("123456abc"    == str_replace("123456789", 7,  'abc'))
assert ("123456789abc" == str_replace("123456789", 10, 'abc'))

local Stream = {}
Stream.__index = Stream

function Stream:new()
  return setmetatable({
    _pos  = 0;
    _data = "";
  }, self)
end

function Stream:_validate()
  assert((self._pos >= 0) and (self._pos <= (#self._data)))
end

function Stream:write(str)
  self:_validate()
  self._data = str_replace(self._data, self._pos+1, str)
  self._pos = self._pos + #str
  self:_validate()
  return #str
end

function Stream:seek(whence, offset)
  self:_validate()

  offset = offset or 0
  whence = whence or "cur"

  if     whence == "set" then self._pos = offset
  elseif whence == "cur" then self._pos = self._pos + offset
  elseif whence == "end" then self._pos = #self._data + offset
  else error("Unknow parametr whence: " .. tostring(whence)) end

  if self._pos < 0 then self._pos = 0 
  elseif self._pos >= #self._data then 
    self._data = self._data .. ('\0'):rep(#self._data - self._pos)
  end
  
  self:_validate()
  return self._pos
end

function Stream:close()
  
end

function Stream:__tostring()
  return self._data
end

local out = Stream:new()

assert(0 == out:seek())
assert(9 == out:write("123456789"))
assert(0 == out:seek("set", 0))
assert(3 == out:write("abc"))
assert(3 == out:seek())
assert("abc456789" == tostring(out))

-- execute implementation from https://github.com/stevedonovan/Lake
local function execute (cmd,quiet)
  if quiet then
    local null = " > "..(IS_WINDOWS and 'NUL' or '/dev/null').." 2>&1"
    cmd = cmd .. null
  end
  local res1,res2,res2 = os.execute(cmd)
  if not IS_LUA52 then
    return res1==0, res1
  else
    return not not res1, res2
  end
end

local function write_file(fname, data)
  local h, e = io.open(fname, 'w+b')
  if not h then return nil, e end
  h:write(data)
  h:close()
  return true
end

local function test_zip(fname, pwd)
  local cmd = "7z t "
  if pwd then cmd = cmd .. " -p" .. pwd .. " " end
  return execute(cmd .. fname, true)
end

return {
  TEST_CASE = TEST_CASE;
  skip      = skip;
  Stream    = Stream;
  test_zip  = test_zip;
  write_file = write_file;
}