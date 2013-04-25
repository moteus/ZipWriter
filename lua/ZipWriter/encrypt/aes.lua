-- This implementaion use for testing needs
-- It can be very slow
-- To provide your own implementation you need implement AesEncrypt interface.

-- AesEncrypt interface
-- AesEncrypt:type()    -> return 'aes'
-- AesEncrypt:mode()    -> return 1/2/3 for aes-128/aes-192/aes-256
-- AesEncrypt:version() -> return 1/2 for AE-1/AE-2
-- AesEncrypt:stream(stream, fileDesc)  return stream that convert data stream to stream like:
--               <SALT><Password verification value><Encrypted data><Authentication code>

-- stream interface
-- stream:seekable()  - if return true then you need implement get_pos/set_pos methods
-- stream:write(data) - write new chunk
-- stream:close()     - close lowlevel stream (return number of written bytes) and return number of written bytes

local function prequire(m) 
  local ok, err = pcall(require, m) 
  if not ok then return nil, err end
  return err
end

local AesFileEncrypt = assert(prequire "AesFileEncrypt" or prequire "ZipWriter.encrypt.aes.AesFileEncrypt")

local rand_bytes

if not rand_bytes then
  local crypto = prequire "crypto"
  if crypto then rand_bytes = crypto.rand.bytes end
end

if not rand_bytes then
  local random = prequire"random"
  if random then
    rand_bytes = function (n)
      local t = {}
      local r = random.new(os.time())
      for i = 1, n do table.insert(t, string.char(r(255))) end
      return table.concat(t)
    end
  end
end

if not rand_bytes then
  math.randomseed(os.time())
  local random = math.random
  rand_bytes = function (n)
    local t = {}
    for i = 1, n do table.insert(t, string.char(random(256)-1)) end
    return table.concat(t)
  end
end

local AES_VERSION = {
  AE1 = 0x0001;
  AE2 = 0x0002;
}

local AES_MODE = {
  AES128 = 0x01,
  AES192 = 0x02,
  AES256 = 0x03,
}

local SLAT_LENGTH = {8;12;16;}

local function slat_length(mode)
  return assert(SLAT_LENGTH[mode])
end

--- Implement encryption interface
-- 
local AesEncrypt = {}
AesEncrypt.__index = AesEncrypt

function AesEncrypt:new()
  local o = setmetatable({}, self)
  return o
end

local ZIP_AES_MODES = {
  [AES_MODE.AES128] = 128,
  [AES_MODE.AES192] = 192,
  [AES_MODE.AES256] = 256,
}

function AesEncrypt:new(password, mode)
  local salt, version
  if type(password) == 'table' then
    version  = password.version
    salt     = password.salt
    mode     = password.mode
    password = password.password
  end

  local o = setmetatable({}, self)
  o._mode     = mode    or AES_MODE.AES256
  o._version  = version or AES_VERSION.AE2
  o._password = password
  o._salt     = salt

  assert( ZIP_AES_MODES[o._mode] )
  assert( (o._version == AES_VERSION.AE1) or (o._version == AES_VERSION.AE2) )
  return o
end

--- 
-- @treturn string encryption algorithm name
function AesEncrypt:type()
  return 'aes'
end

--- Return aes version for zip
-- AES specfic method
function AesEncrypt:version()
  return self._version
end

--- Return aes mode for zip
-- AES specfic method
function AesEncrypt:mode()
  return self._mode
end

-- wrap lowlevel stream to encrypted stream
-- @tparam stream
-- @tparam FILE_DESCRIPTOR fileDesc
-- @treturn stream
function AesEncrypt:stream(stream, fileDesc)
  -- output stream format:
  -- <SALT><Password verification value><Encrypted data><Authentication code>

  local mode = self:mode()
  local pwd  = assert(self._password or fileDesc.password, 'no password')
  local salt = fileDesc.salt or self._salt or rand_bytes(slat_length(mode))

  local fenc  = AesFileEncrypt.new()
  fenc:set_writer(stream)
  local pwd_ver salt, pwd_ver = fenc:open(mode, pwd, salt)

  stream:write(salt) stream:write(pwd_ver)
  return {
    seekable = function() return false end;

    write    = function(self, chunk) fenc:encrypt(chunk) end;

    close    = function(self)
      local mac = fenc:close()
      stream:write(mac)
      fenc:destroy()
      return stream:close()
    end;
  }
end

local _M = {}

function _M.new(...)
  return AesEncrypt:new(...)
end

function _M.self_test()
  AesFileEncrypt.self_test()
end

_M.VERSION = AES_VERSION

_M.MODE    = AES_MODE

return _M