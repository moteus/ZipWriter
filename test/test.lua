pcall(require, "luacov")

local HAS_RUNNER = not not lunit

local base64    = require "base64"

function DUMP(lvl, res)
  res = base64.decode(res)
  print(#res)
  local out = assert(io.open(lvl, "wb"))
  out:write(res)
  out:close()
end

function LOAD(fname)
  local f = assert(io.open(fname, "rb"))
  local res = f:read("*all")
  f:close()
  print( #res )
  local enc = base64.encode(res)
  assert(res == base64.decode(enc))
  return enc
end

local ZipWriter = require "ZipWriter"
local zutils    = require "ZipWriter.utils"
local lunit     = require "lunit"
local tutils    = require "utils"
local TEST_CASE = tutils.TEST_CASE
local skip      = tutils.skip
local Stream    = tutils.Stream
local write_file= tutils.write_file
local test_zip  = tutils.test_zip

local function prequire(m)
  local ok, err = pcall(require, m) 
  if not ok then return nil, err end
  return err
end

local function H(t, b, e)
  local str = ''
  for i = b or 1, e or #t do str = str .. (string.char(t[i])) end
  return str
end

local ETALON = { -- make by winrar 3.93
  NO      = "UEsDBAoAAAAAADVwM0E6zD49KgAAACoAAAAIAAAAdGVzdC50eHQxMTExMTExMTExMTExMTExMTExMQ0KMjIyMjIyMjIyMjIyMjIyMjIyMjJQSwECFAAKAAAAAAA1cDNBOsw+PSoAAAAqAAAACAAAAAAAAAAAACAAAAAAAAAAdGVzdC50eHRQSwUGAAAAAAEAAQA2AAAAUAAAAAAA";
  DEFAULT = "UEsDBBQAAAAIADVwM0E6zD49CgAAACoAAAAIAAAAdGVzdC50eHQzNMQEvFxGWAAAUEsBAhQAFAAAAAgANXAzQTrMPj0KAAAAKgAAAAgAAAAAAAAAAQAgAAAAAAAAAHRlc3QudHh0UEsFBgAAAAABAAEANgAAADAAAAAAAA==";
  SPEED   = "UEsDBBQABAAIADVwM0E6zD49CgAAACoAAAAIAAAAdGVzdC50eHQzNMQEvFxGWAAAUEsBAhQAFAAEAAgANXAzQTrMPj0KAAAAKgAAAAgAAAAAAAAAAQAgAAAAAAAAAHRlc3QudHh0UEsFBgAAAAABAAEANgAAADAAAAAAAA==";
  BEST    = "UEsDBBQAAgAIADVwM0E6zD49CgAAACoAAAAIAAAAdGVzdC50eHQzNMQEvFxGWAAAUEsBAhQAFAACAAgANXAzQTrMPj0KAAAAKgAAAAgAAAAAAAAAAQAgAAAAAAAAAHRlc3QudHh0UEsFBgAAAAABAAEANgAAADAAAAAAAA==";
}

local DATA = "11111111111111111111\r\n22222222222222222222"
local fileDesc = {
  istext   = true,
  isfile   = true,
  isdir    = false,
  -- lfs.attributes('modification') 
  mtime    = 1348048902 - 1, -- -1 - Is this bug in winrar?
  exattrib = {ZipWriter.DOS_FILE_ATTR.ARCH},
  platform = 'windows',
}

local DELTA do
  local MY_DELTA  = 14400
  local d1 = os.date("*t", fileDesc.mtime)
  d1.isdst = false
  local t1 = os.time(d1)
  local t2 = os.time(os.date("!*t", fileDesc.mtime))
  local SYS_DELTA = os.difftime(t1, t2)
  DELTA = MY_DELTA - SYS_DELTA
end

fileDesc.mtime = fileDesc.mtime + DELTA

local _ENV = TEST_CASE'ZipWriter utils' do

function test_date()
  local t = assert_table(os.date("*t", fileDesc.mtime))
  assert_equal(2012, t.year  )
  assert_equal(09,   t.month )
  assert_equal(19,   t.day   )
  assert_equal(01,   t.min   )
  assert_equal(41,   t.sec   )
  assert_equal(14,   t.hour  )
end

end

local _ENV = TEST_CASE'ZipWriter read data' do

function setup()
  fileDesc.data = DATA
end

function teardown()
  fileDesc.data = nil
end

local function Make(lvl) return function()
  local out = Stream:new()

  local writer = ZipWriter.new{
    utf8 = false;
    level = ZipWriter.COMPRESSION_LEVEL[lvl]
  }
  writer:open_stream(out)
  writer:write('test.txt', fileDesc)
  writer:close()

  local res = base64.encode( tostring(out) )
  assert_equal( ETALON[ lvl:upper() ], res )
end end

test_no      = Make('NO')
test_default = Make('DEFAULT')
test_speed   = Make('SPEED')
test_best    = Make('BEST')

end

local _ENV = TEST_CASE'ZipWriter reader' do

local function Make(lvl) return function()
  local out = Stream:new()
  -- local out    = io.open(".\\out.zip", "wb")
  
  local function reader(i)
    i = i or 1
    local chunk = string.sub(DATA, i, i + 10)
    if chunk == '' then return end
    return chunk, i + #chunk
  end

  local writer = ZipWriter.new{
    utf8 = false;
    level = ZipWriter.COMPRESSION_LEVEL[lvl]
  }
  writer:open_stream(out)
  writer:write('test.txt', fileDesc, reader)
  writer:close()

  local res = base64.encode( tostring(out) )
  assert_equal( ETALON[ lvl:upper() ], res )
end end

test_no      = Make('NO')
test_default = Make('DEFAULT')
test_speed   = Make('SPEED')
test_best    = Make('BEST')

end

local _ENV = TEST_CASE'ZipWriter reader interface' do

function test_context()
  local out = Stream:new()
  local writer = ZipWriter.new()
  writer:open_stream(out)

  local function make_reader()
    local ctx = {}
    local i = 0
    return function(o)
      if i == 0 then
        i = 1
        assert_nil(o)
        return "data", ctx
      end
      assert_equal(ctx, o)
    end
  end

  assert_true(writer:write('test.txt', fileDesc, make_reader()))
  assert_equal(1, writer:close())
end

function test_error()
  local out = Stream:new()
  local writer = ZipWriter.new()
  writer:open_stream(out)

  local ERR = {}

  local function reader()
    return nil, ERR
  end

  local ok, err = assert_nil(writer:write('test.txt', fileDesc, reader))
  assert_equal(ERR, err)
  assert_equal(1, writer:close())
end

end

local _ENV = TEST_CASE'ZipWriter sink' do

local function Make(lvl) return function()
  local out = Stream:new()

  local writer = ZipWriter.new{
    utf8 = false;
    level = ZipWriter.COMPRESSION_LEVEL[lvl]
  }
  writer:open_stream(out)

  local sink = ZipWriter.sink(writer, 'test.txt', fileDesc)
  for i = 1, #DATA do sink(DATA:sub(i,i)) end
  sink()
  writer:close()
  
  local res = base64.encode( tostring(out) )
  assert_equal( ETALON[ lvl:upper() ], res )
end end

test_no      = Make('NO')
test_default = Make('DEFAULT')
test_speed   = Make('SPEED')
test_best    = Make('BEST')

end

local _ENV = TEST_CASE'ZipWriter source' do

local ETALON = { -- testd with winrar 3.93 / 7-Zip 9.20.04 alpha
  NO      = [[UEsDBAoACAAAADVwM0EAAAAAAAAAAAAAAAAIAAAAdGVzdC50eHQxMTExMTExMTExMTExMTExMTExMQ0KMjIyMjIyMjIyMjIyMjIyMjIyMjJQSwcIOsw+PSoAAAAqAAAAUEsBAhQACgAIAAAANXAzQTrMPj0qAAAAKgAAAAgAAAAAAAAAAAAgAAAAAAAAAHRlc3QudHh0UEsFBgAAAAABAAEANgAAAGAAAAAAAA==]];
  DEFAULT = [[UEsDBBQACAAIADVwM0EAAAAAAAAAAAAAAAAIAAAAdGVzdC50eHQzNMQEvFxGWAAAUEsHCDrMPj0KAAAAKgAAAFBLAQIUABQACAAIADVwM0E6zD49CgAAACoAAAAIAAAAAAAAAAEAIAAAAAAAAAB0ZXN0LnR4dFBLBQYAAAAAAQABADYAAABAAAAAAAA=]];
  SPEED   = [[UEsDBBQADAAIADVwM0EAAAAAAAAAAAAAAAAIAAAAdGVzdC50eHQzNMQEvFxGWAAAUEsHCDrMPj0KAAAAKgAAAFBLAQIUABQADAAIADVwM0E6zD49CgAAACoAAAAIAAAAAAAAAAEAIAAAAAAAAAB0ZXN0LnR4dFBLBQYAAAAAAQABADYAAABAAAAAAAA=]];
  BEST    = [[UEsDBBQACgAIADVwM0EAAAAAAAAAAAAAAAAIAAAAdGVzdC50eHQzNMQEvFxGWAAAUEsHCDrMPj0KAAAAKgAAAFBLAQIUABQACgAIADVwM0E6zD49CgAAACoAAAAIAAAAAAAAAAEAIAAAAAAAAAB0ZXN0LnR4dFBLBQYAAAAAAQABADYAAABAAAAAAAA=]];
}

local function Make(lvl) return function()
  local data = fileDesc.data
  local function reader(i)
    i = i or 1
    local chunk = string.sub(DATA, i, i + 10)
    if chunk == '' then return end
    return chunk, i + #chunk
  end

  local writer = ZipWriter.new{
    utf8 = false;
    level = ZipWriter.COMPRESSION_LEVEL[lvl]
  }
  local RES = {}
  writer:open_writer(assert(ZipWriter.co_writer(function(reader) 
    while(true)do
      local chunk = reader()
      if not chunk then break end
      table.insert(RES,chunk)
    end
  end)))

  writer:open_stream(out)
  writer:write('test.txt', fileDesc, reader)
  writer:close()

  local res = table.concat(RES)

  res = base64.encode( res )
  assert_equal( ETALON[ lvl:upper() ], res )
end end

test_no      = Make('NO')
test_default = Make('DEFAULT')
test_speed   = Make('SPEED')
test_best    = Make('BEST')

end

local _ENV = TEST_CASE'ZipWriter ZIP64' do

local ETALON = { -- testd with 7-Zip 9.20.04 alpha
  NO      = [[UEsDBAoAAAAAADVwM0E6zD49//////////8IACAAdGVzdC50eHQBABwAKgAAAAAAAAAqAAAAAAAAAAAAAAAAAAAAAAAAADExMTExMTExMTExMTExMTExMTExDQoyMjIyMjIyMjIyMjIyMjIyMjIyMlBLAQIUAAoAAAAAADVwM0E6zD49//////////8IACAAAAAAAAAAIAAAAAAAAAB0ZXN0LnR4dAEAHAAqAAAAAAAAACoAAAAAAAAAAAAAAAAAAAAAAAAAUEsGBiwAAAAAAAAAPwA/AAAAAAAAAAAAAQAAAAAAAAABAAAAAAAAAFYAAAAAAAAAcAAAAAAAAABQSwYHAAAAAMYAAAAAAAAAAAAAAFBLBQYAAAAAAQABAFYAAABwAAAAAAA=]];
  DEFAULT = [[UEsDBBQAAAAIADVwM0E6zD49//////////8IACAAdGVzdC50eHQBABwAKgAAAAAAAAAKAAAAAAAAAAAAAAAAAAAAAAAAADM0xAS8XEZYAABQSwECFAAUAAAACAA1cDNBOsw+Pf//////////CAAgAAAAAAABACAAAAAAAAAAdGVzdC50eHQBABwAKgAAAAAAAAAKAAAAAAAAAAAAAAAAAAAAAAAAAFBLBgYsAAAAAAAAAD8APwAAAAAAAAAAAAEAAAAAAAAAAQAAAAAAAABWAAAAAAAAAFAAAAAAAAAAUEsGBwAAAACmAAAAAAAAAAAAAABQSwUGAAAAAAEAAQBWAAAAUAAAAAAA]];
  SPEED   = [[UEsDBBQABAAIADVwM0E6zD49//////////8IACAAdGVzdC50eHQBABwAKgAAAAAAAAAKAAAAAAAAAAAAAAAAAAAAAAAAADM0xAS8XEZYAABQSwECFAAUAAQACAA1cDNBOsw+Pf//////////CAAgAAAAAAABACAAAAAAAAAAdGVzdC50eHQBABwAKgAAAAAAAAAKAAAAAAAAAAAAAAAAAAAAAAAAAFBLBgYsAAAAAAAAAD8APwAAAAAAAAAAAAEAAAAAAAAAAQAAAAAAAABWAAAAAAAAAFAAAAAAAAAAUEsGBwAAAACmAAAAAAAAAAAAAABQSwUGAAAAAAEAAQBWAAAAUAAAAAAA]];
  BEST    = [[UEsDBBQAAgAIADVwM0E6zD49//////////8IACAAdGVzdC50eHQBABwAKgAAAAAAAAAKAAAAAAAAAAAAAAAAAAAAAAAAADM0xAS8XEZYAABQSwECFAAUAAIACAA1cDNBOsw+Pf//////////CAAgAAAAAAABACAAAAAAAAAAdGVzdC50eHQBABwAKgAAAAAAAAAKAAAAAAAAAAAAAAAAAAAAAAAAAFBLBgYsAAAAAAAAAD8APwAAAAAAAAAAAAEAAAAAAAAAAQAAAAAAAABWAAAAAAAAAFAAAAAAAAAAUEsGBwAAAACmAAAAAAAAAAAAAABQSwUGAAAAAAEAAQBWAAAAUAAAAAAA]];
}

function setup()
  fileDesc.data = DATA
end

function teardown()
  fileDesc.data = nil
end

local function Make(lvl) return function()
  local out = Stream:new()

  local writer = ZipWriter.new{
    utf8 = false;
    zip64 = true;
    level = ZipWriter.COMPRESSION_LEVEL[lvl]
  }
  writer:open_stream(out)
  writer:write('test.txt', fileDesc)
  writer:close()

  local res = base64.encode( tostring(out) )
  assert_equal( ETALON[ lvl:upper() ], res )
end end

test_no      = Make('NO')
test_default = Make('DEFAULT')
test_speed   = Make('SPEED')
test_best    = Make('BEST')

end

local _ENV = TEST_CASE'ZipWriter ZIP64 nonseekable' do

local ETALON = { -- testd with 7-Zip 9.20.04 alpha
  NO      = [[UEsDBAoACAAAADVwM0EAAAAA//////////8IACAAdGVzdC50eHQBABwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADExMTExMTExMTExMTExMTExMTExDQoyMjIyMjIyMjIyMjIyMjIyMjIyMlBLBwg6zD49KgAAAAAAAAAqAAAAAAAAAFBLAQIUAAoACAAAADVwM0E6zD49//////////8IACAAAAAAAAAAIAAAAAAAAAB0ZXN0LnR4dAEAHAAqAAAAAAAAACoAAAAAAAAAAAAAAAAAAAAAAAAAUEsGBiwAAAAAAAAAPwA/AAAAAAAAAAAAAQAAAAAAAAABAAAAAAAAAFYAAAAAAAAAiAAAAAAAAABQSwYHAAAAAN4AAAAAAAAAAAAAAFBLBQYAAAAAAQABAFYAAACIAAAAAAA=]];
  DEFAULT = [[UEsDBBQACAAIADVwM0EAAAAA//////////8IACAAdGVzdC50eHQBABwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADM0xAS8XEZYAABQSwcIOsw+PQoAAAAAAAAAKgAAAAAAAABQSwECFAAUAAgACAA1cDNBOsw+Pf//////////CAAgAAAAAAABACAAAAAAAAAAdGVzdC50eHQBABwAKgAAAAAAAAAKAAAAAAAAAAAAAAAAAAAAAAAAAFBLBgYsAAAAAAAAAD8APwAAAAAAAAAAAAEAAAAAAAAAAQAAAAAAAABWAAAAAAAAAGgAAAAAAAAAUEsGBwAAAAC+AAAAAAAAAAAAAABQSwUGAAAAAAEAAQBWAAAAaAAAAAAA]];
  SPEED   = [[UEsDBBQADAAIADVwM0EAAAAA//////////8IACAAdGVzdC50eHQBABwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADM0xAS8XEZYAABQSwcIOsw+PQoAAAAAAAAAKgAAAAAAAABQSwECFAAUAAwACAA1cDNBOsw+Pf//////////CAAgAAAAAAABACAAAAAAAAAAdGVzdC50eHQBABwAKgAAAAAAAAAKAAAAAAAAAAAAAAAAAAAAAAAAAFBLBgYsAAAAAAAAAD8APwAAAAAAAAAAAAEAAAAAAAAAAQAAAAAAAABWAAAAAAAAAGgAAAAAAAAAUEsGBwAAAAC+AAAAAAAAAAAAAABQSwUGAAAAAAEAAQBWAAAAaAAAAAAA]];
  BEST    = [[UEsDBBQACgAIADVwM0EAAAAA//////////8IACAAdGVzdC50eHQBABwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADM0xAS8XEZYAABQSwcIOsw+PQoAAAAAAAAAKgAAAAAAAABQSwECFAAUAAoACAA1cDNBOsw+Pf//////////CAAgAAAAAAABACAAAAAAAAAAdGVzdC50eHQBABwAKgAAAAAAAAAKAAAAAAAAAAAAAAAAAAAAAAAAAFBLBgYsAAAAAAAAAD8APwAAAAAAAAAAAAEAAAAAAAAAAQAAAAAAAABWAAAAAAAAAGgAAAAAAAAAUEsGBwAAAAC+AAAAAAAAAAAAAABQSwUGAAAAAAEAAQBWAAAAaAAAAAAA]];
}

function setup()
  fileDesc.data = DATA
end

function teardown()
  fileDesc.data = nil
end

local function Make(lvl) return function()
  local out = Stream:new()

  local writer = ZipWriter.new{
    utf8  = false;
    zip64 = true;
    level = ZipWriter.COMPRESSION_LEVEL[lvl]
  }
  writer:open_writer(function(data) if data then out:write(data) end end)
  writer:write('test.txt', fileDesc)
  writer:close()

  local res = base64.encode( tostring(out) )
  assert_equal( ETALON[ lvl:upper() ], res )
end end

test_no      = Make('NO')
test_default = Make('DEFAULT')
test_speed   = Make('SPEED')
test_best    = Make('BEST')

end

local AesEncrypt = prequire"ZipWriter.encrypt.aes"

if AesEncrypt then 

local DATA = "11111111111111111111\r\n22222222222222222222"

local fileDesc = {
  istext = true,
  isfile = true,
  isdir  = false,
  mtime   = 1348048902,
  ctime   = 1366112737,
  atime   = 1366378701,
  exattrib = {ZipWriter.DOS_FILE_ATTR.ARCH},
  platform = 'windows',
}

local _ENV = TEST_CASE'ZipWriter AES-256' do

local fname = "./test.zip"

local ETALON = {
  -- identical with 7z, but ntfs_extra field
  NO = [[UEsDBDMAAQBjADZwM0EAAAAARgAAACoAAAAIAAsAdGVzdC50eHQBmQcAAgBBRQMAAAT5Svtgr0dE1NubOucjPsa+cjopgUGk59m/cSjwBAiy1nPu7M00DxtAT4EMWReOthEL76uIxaSJ98WgyXytSyTidhZmDyJQSwECPwAzAAEAYwA2cDNBAAAAAEYAAAAqAAAACAAvAAAAAAAAACAAAAAAAAAAdGVzdC50eHQKACAAAAAAAAEAGAAAB67ETZbNAYAEQygDPc4BgEZd6Zc6zgEBmQcAAgBBRQMAAFBLBQYAAAAAAQABAGUAAAB3AAAAAAA=]];
}

function setup()
  fileDesc.data = DATA
end

function teardown()
  fileDesc.data = nil
  os.remove(fname)
end

local function Make(lvl) return function()
  local out = Stream:new()

  local writer = ZipWriter.new{
    utf8 = false;
    level = ZipWriter.COMPRESSION_LEVEL[lvl];
    encrypt = AesEncrypt.new{
      mode     = AesEncrypt.MODE.AES256;
      version  = AesEncrypt.VERSION.AE2;
      password = '123456';
      salt     = H{0x04, 0xF9, 0x4A, 0xFB, 0x60, 0xAF, 0x47, 0x44, 0xD4, 0xDB, 0x9B, 0x3A, 0xE7, 0x23, 0x3E, 0xC6};  -- optional
    }
  }
  writer:open_stream(out)
  writer:write('test.txt', fileDesc)
  writer:close()

  if DELTA == 0 and ETALON[ lvl:upper() ] then
    local res = base64.encode( tostring(out) )
    assert_equal( ETALON[ lvl:upper() ], res )
  else
    assert_true(write_file(fname, tostring(out)))
    assert_true(test_zip(fname, '123456'))
  end
end end

test_no      = Make('NO')
test_default = Make('DEFAULT')
test_speed   = Make('SPEED')
test_best    = Make('BEST')

end

end

local AesEncrypt = prequire"ZipWriter.encrypt.aes.AesFileEncrypt"

if AesEncrypt then

local _ENV = TEST_CASE'AesEncrypt self_test' do

function test()
  AesEncrypt.self_test()
end

end

end

if not HAS_RUNNER then lunit.run() end