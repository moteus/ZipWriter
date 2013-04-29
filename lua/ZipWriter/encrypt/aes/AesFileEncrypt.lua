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
}

--- Internal type to encrypt data stream
-- 
local AesFileEncrypt = {}
AesFileEncrypt.__index = AesFileEncrypt

---
-- @tparam ?number block_size for zip files need 16
function AesFileEncrypt:new(block_size)
  local o = setmetatable({
    private_ = {
      block_size = block_size or BLOCK_SIZE;
      encrypt    = true;
    }
  }, self)
  return o
end

---
-- @tparam number mode 1/2/3
-- @tparam string pwd up to 128 bytes
-- @tparam string salt depend on AES encrypt mode
-- @treturt string salt
-- @treturt string passert verification code
function AesFileEncrypt:open(mode, pwd, salt)
  self.private_.mode = assert(AES_MODES[mode], 'unknown mode: ' .. mode)

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

local function ichunks(len, chunk_size)
  return function(_, b)
    b = b + chunk_size
    if b > len then return nil end
    local e = b + chunk_size - 1
    if e > len then e = len end
    return b, e
  end, nil, -chunk_size + 1
end

local function chunks(msg, chunk_size, len)
  len = len or #msg
  return function(_, b)
    b = b + chunk_size
    if b > len then return nil end
    local e = b + chunk_size - 1
    if e > len then e = len end
    return b, (string.sub(msg, b, e))
  end, nil, -chunk_size + 1
end

function AesFileEncrypt:update_impl(encrypt, msg, len)
  local chunk_size = assert(self.private_.block_size)
  local nonce      = assert(self.private_.nonce)
  local aes_key    = assert(self.private_.aes_key)
  local mac        = assert(self.private_.mac)
  local writer     = self.private_.writer
  local data if not writer then data = {} end

  local buf        = {}
  local sbyte      = string.byte
  local aes_name   = self.private_.mode.name .. '-cbc'

  for b, chunk in chunks(msg, chunk_size, len) do
    if not encrypt then mac:update(chunk) end
    inc_nonce(nonce)
    local tmp = crypto.encrypt(aes_name, H(nonce), aes_key)
    assert(#tmp >= chunk_size)
    for i = 1, #chunk do buf[i] = bit.bxor( sbyte(chunk, i), sbyte(tmp, i) ) end
    local enc = H(buf)
    if encrypt then mac:update(enc) end
    if writer then writer(enc) else table.insert(data, enc) end
  end
  if not writer then return table.concat(data) end
end

--- Write new portion of data
-- @tparam string msg
-- @return nothing
function AesFileEncrypt:update_(msg)
  if self.private_.tail then
    msg = self.private_.tail .. msg
    self.private_.tail = nil
  end

  local len = math.floor(#msg / self.private_.block_size) * self.private_.block_size

  if len < #msg then self.private_.tail = string.sub(msg, len + 1) end

  return self:update_impl(self.private_.encrypt, msg, len)
end

function AesFileEncrypt:encrypt(msg)
  self.private_.encrypt = true
  return self:update_(msg)
end

function AesFileEncrypt:decrypt(msg)
  self.private_.encrypt = false
  return self:update_(msg)
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

  if msg then msg = self:update_impl(self.private_.encrypt, msg, #msg) end

  local mac  = self.private_.mac:final(nil, true)

  self.private_.salt    = nil
  self.private_.mac     = nil
  self.private_.nonce   = nil
  self.private_.aes_key = nil
  self.private_.mac_key = nil
  self.private_.pwd_ver = nil

  return mac:sub(1, self.private_.mode.mac), msg
end

function AesFileEncrypt:destroy()
  self.private_.block_size = nil
end

function AesFileEncrypt:opened()
  return not not self.private_.aes_key
end

function AesFileEncrypt:destroyed()
  return not not self.private_.block_size
end

---
--
function AesFileEncrypt:set_writer(writer, ctx)
  if writer == nil then
    self.private_.writer = nil
  elseif type(writer) == 'function' then
    if ctx ~= nil then
      self.private_.writer = function(...)
        return writer(ctx, ...)
      end
    else
      self.private_.writer = writer
    end
  else
    local write = assert(writer.write)
    self.private_.writer = function(...)
      return write(writer, ...)
    end
  end
  return self
end

---
--
function AesFileEncrypt:get_writer()
  return self.private_.writer
end

function AesFileEncrypt:iv()
  return H(self.private_.nonce)
end

function AesFileEncrypt:key()
  return self.private_.aes_key
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

  local fenc = AesFileEncrypt:new()

  local edata = {}
  fenc:set_writer(table.insert, edata)

  local salt, pwd_ver = fenc:open(3, pwd, salt)
  fenc:encrypt(data)
  local mac_ = fenc:close()
  edata = table.concat(edata)
  assert(mac == crypto.hex(mac_), 'Expected: `' .. mac ..'` got: `' .. crypto.hex(mac_) .. '`')
  assert(etalon == crypto.hex(edata), 'Expected: `' .. etalon ..'` got: `' .. crypto.hex(edata) .. '`')
end

function AesFileEncrypt.self_test()
  test_derive_key()
  test_AesFileEncrypt()
end

-- AesFileEncrypt.self_test()

return {
  new = function()
    return AesFileEncrypt:new()
  end
}