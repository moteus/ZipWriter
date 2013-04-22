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

local crypto = require "crypto"
local bit    = assert(prequire("bit32") or prequire("bit"))
local string = require "string"
local math   = require "math"
local table  = require "table"

local PWD_VER_LENGTH    = 2
local SHA1_DIGEST_SIZE  = 20
local MAX_PWD_LENGTH    = 128
local KEYING_ITERATIONS = 1000
local BLOCK_SIZE        = 16 -- zip compatable

local function H(t, b, e)
  local str = ''
  for i = b or 1, e or #t do
    str = str .. (string.char(t[i]))
  end
  return str
end

local function derive_key(pwd, salt, iter, key_len)
  local sbyte   = string.byte
  local schar   = string.char
  local bxor    = bit.bxor

  local key = {}
  local uu, u2, ux = {}, {}, {}
  local n_blk = math.floor(1 + (key_len - 1) / SHA1_DIGEST_SIZE)
  local c3 = crypto.hmac.new('sha1', pwd)

  for i = 1, n_blk do
    for j = 1, SHA1_DIGEST_SIZE do ux[j], uu[j] = 0 end
    uu[1], uu[2], uu[3], uu[4] = bit.rshift(i, 24), bit.rshift(i, 16), bit.rshift(i,  8), i

    c3:update(salt)
    for j = 1, iter do 
      for _, b in ipairs(uu) do c3:update(schar(b)) end
      local str = c3:final(nil, true)

      -- assert(#str == 20)
      uu[1],  uu[2],  uu[3],  uu[4], uu[5],  uu[6],  uu[7],  uu[8], uu[9],  uu[10],
      uu[11], uu[12], uu[13], uu[14], uu[15], uu[16], uu[17], uu[18], uu[19], uu[20]
      = sbyte(str, 1, SHA1_DIGEST_SIZE)

      for k = 1, #uu do ux[k] = bxor( ux[k], uu[k] ) end
      c3:reset()
    end

    for _, b in ipairs(ux) do
      table.insert(key, b)
      if #key >= key_len then
        return key
      end
    end
  end
  return key
end

local AES_MODES = {
  [1]   = { key  = 16; salt =  8; mac  = 10; name = 'aes-128'};
  [2]   = { key  = 24; salt = 12; mac  = 10; name = 'aes-192'};
  [3]   = { key  = 32; salt = 16; mac  = 10; name = 'aes-256'};

  [128] = { key  = 16; salt =  8; mac  = 10; name = 'aes-128'};
  [192] = { key  = 24; salt = 12; mac  = 10; name = 'aes-192'};
  [256] = { key  = 32; salt = 16; mac  = 10; name = 'aes-256'};
}

--- Internal type to encrypt data stream
-- 
local AesFileEncrypt = {}
AesFileEncrypt.__index = AesFileEncrypt

---
-- @tparam number mode 128/192/256
-- @tparam number block_size for zip files need 16
function AesFileEncrypt:new(mode, block_size)
  local o = setmetatable({
    private_ = {
      mode = assert(AES_MODES[mode or 256]);
      block_size = block_size or BLOCK_SIZE;
    }
  }, self)
  return o
end

---
-- @tparam string pwd up to 128 bytes
-- @tparam ?string salt depend on AES encrypt mode
-- @treturt string salt
-- @treturt string passert verification code
function AesFileEncrypt:open(pwd, salt)
  assert(not self.private_.salt, "alrady opened")
  salt = salt or crypto.rand.bytes(self.private_.mode.salt)
  assert(#salt == self.private_.mode.salt, 'Expected: ' .. self.private_.mode.salt .. ' got: ' .. #salt )
  self.private_.salt = salt
  local key_len = self.private_.mode.key

  local key = derive_key(pwd, salt, KEYING_ITERATIONS, 2 * key_len + PWD_VER_LENGTH)

  local aes_key = H(key, 1, key_len)
  local mac_key = H(key, 1 + key_len,  2 * key_len)
  local pwd_ver = H(key, 1 + 2 * key_len, 2 * key_len + PWD_VER_LENGTH)

  local mac     = crypto.hmac.new('sha1', mac_key)
  local nonce   = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
  
  self.private_.mac     = mac
  self.private_.nonce   = nonce
  self.private_.aes_key = aes_key
  self.private_.mac_key = mac_key
  self.private_.pwd_ver = pwd_ver

  return salt, pwd_ver
end

local function inc_nonce(nonce)
  for k, v in ipairs(nonce) do
    if v == 255 then nonce[k] = 0
    else nonce[k] = v + 1 return end
  end
end

function AesFileEncrypt:update_impl(msg, len)
  local chunk_size = assert(self.private_.block_size)
  local nonce      = assert(self.private_.nonce)
  local aes_key    = assert(self.private_.aes_key)
  local mac        = assert(self.private_.mac)
  local writer     = assert(self.private_.writer)

  local buf        = {}
  local sbyte      = string.byte
  local aes_name   = self.private_.mode.name .. '-cbc'

  for b = 1, len, chunk_size do
    local e = b + chunk_size - 1
    local chunk = string.sub(msg, b, e)
    if #chunk == 0 then break end

    inc_nonce(nonce)
    local tmp = crypto.encrypt(aes_name, H(nonce), aes_key)
    assert(#tmp >= chunk_size)
    for i = 1, #chunk do buf[i] = bit.bxor( sbyte(chunk, i), sbyte(tmp, i) ) end
    local enc = H(buf)
    mac:update(enc)
    writer(enc)
  end
end

--- Write new portion of data
-- @tparam string msg
-- @return nothing
function AesFileEncrypt:write(msg)
  if self.private_.tail then
    msg = self.private_.tail .. msg
    self.private_.tail = nil
  end

  local len = math.floor(#msg / self.private_.block_size) * self.private_.block_size

  if len < #msg then self.private_.tail = string.sub(msg, len + 1) end

  return self:update_impl(msg, len)
end

--- Write last portion of data
-- @tparam string msg
-- @treturt string message authentication code
function AesFileEncrypt:close(msg)
  if msg then
    if self.private_.tail then 
      msg = self.private_.tail .. msg
    end
  else
    msg = self.private_.tail
  end
  self.private_.tail = nil

  if msg then self:update_impl(msg, #msg) end

  local mac  = self.private_.mac:final(nil, true)

  self.private_.salt    = nil
  self.private_.mac     = nil
  self.private_.nonce   = nil
  self.private_.aes_key = nil
  self.private_.mac_key = nil
  self.private_.pwd_ver = nil
  self.private_.writer(nil)

  return mac:sub(1, self.private_.mode.mac)
end

---
--
function AesFileEncrypt:open_writer(writer)
  self.private_.writer = writer
end

local function test_derive_key()
  local pwd  = string.rep("1234567890", 5)
  local salt = H{0xbe,0xda,0x8e,0x77,0x4b,0x16,0x8f,0xfb,0xa8,0xaf,0xf3,0x4f,0x2d,0x4e,0xfe,0xd0}
  local iter = KEYING_ITERATIONS
  local key_len = 2 * 32 + PWD_VER_LENGTH
  local etalon = {55, 74, 210, 155, 79, 239, 111, 112, 82, 186, 90, 155, 
    224, 195, 16, 86, 32, 162, 64, 248, 69, 143, 236, 80, 91, 243, 244,
    23, 63, 102, 65, 87, 33, 19, 240, 36, 236, 133, 57, 18, 60, 126, 75,
    201, 248, 211, 41, 218, 97, 17, 122, 236, 162, 141, 80, 207, 168, 15,
    148, 170, 132, 145, 126, 11, 153, 63
  }

  local key = derive_key(pwd, salt, iter, key_len)
  assert(H(key) == H(etalon))
end

local function test_AesFileEncrypt()
  local pwd    = "123456"
  local salt   = H{0x5D,0x9F,0xF9,0xAE,0xE6,0xC5,0xC9,0x19,0x42,0x46,0x88,0x3E,0x06,0x9D,0x1A,0xA6}
  local pver   = "9aa9"
  local data   = "11111111111111111111\r\n22222222222222222222"
  local mac    = "eb048021e72f5e2a7db3"
  local etalon = "91aa63f0cb2b92479f89c32eb6b875b8c7d487aa7a8cb3705a5d8d276d6a2e8fc7cad94cc28ed0ad123e"

  local fenc = AesFileEncrypt:new(256)

  local edata = {}
  fenc:open_writer(function(chunk)
    if chunk == nil then
      edata = table.concat(edata)
    else
      table.insert(edata, chunk)
    end
  end)

  local salt, pwd_ver = fenc:open(pwd,salt)
  fenc:write(data)
  local mac_ = fenc:close()
  assert(mac == crypto.hex(mac_), 'Expected: `' .. mac ..'` got: `' .. crypto.hex(mac_) .. '`')
  assert(etalon == crypto.hex(edata), 'Expected: `' .. etalon ..'` got: `' .. crypto.hex(edata) .. '`')
end

function AesFileEncrypt.self_test()
  test_derive_key()
  test_AesFileEncrypt()
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

  local pwd = assert(self._password or fileDesc.password, 'no password')
  local salt = fileDesc.salt or self._salt

  local fenc  = AesFileEncrypt:new(ZIP_AES_MODES[self:mode()])

  fenc:open_writer(function(chunk) return chunk and stream:write(chunk) end)

  local pwd_ver salt, pwd_ver = fenc:open(pwd, salt)
  stream:write(salt) stream:write(pwd_ver)
  return {
    seekable = function() return false end;

    write    = function(self, chunk) fenc:write(chunk) end;

    close    = function(self)
      local mac = fenc:close()
      stream:write(mac)
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