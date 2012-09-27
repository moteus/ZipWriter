local ZipWriter = require "ZipWriter"
local base64    = require "base64"
local memfile   = require "memoryfile"
local lunit = require "lunitx"

function DUMP(lvl, res)
  res = base64.decode(res)
  local out = io.open(".\\" .. lvl .. ".zip", "wb")
  out:write(res)
  out:close()
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
  exattrib = 32, -- get from GetFileAttributesA
}

local TEST_NAME = 'ZipWriter read data'
if _VERSION >= 'Lua 5.2' then  _ENV = lunit.module(TEST_NAME,'seeall')
else module( TEST_NAME, package.seeall, lunit.testcase ) end

function setup()
  fileDesc.data = DATA
end

function teardown()
  fileDesc.data = nil
end

local function Make(lvl)
  local out    = memfile.open("", "wb")

  local writer = ZipWriter.new{
    utf8 = false;
    level = ZipWriter.COMPRESSION_LEVEL[lvl]
  }
  writer:open_stream(out)
  writer:write('test.txt', fileDesc)
  writer:close()

  local res = base64.encode( tostring(out) )
  assert( res == ETALON[ lvl:upper() ] )
end

function test_()
  Make('NO')
  Make('DEFAULT')
  Make('SPEED')
  Make('BEST')
end

local TEST_NAME = 'ZipWriter reader'
if _VERSION >= 'Lua 5.2' then  _ENV = lunit.module(TEST_NAME,'seeall')
else module( TEST_NAME, package.seeall, lunit.testcase ) end

local function Make(lvl)
  local out    = memfile.open("", "wb")
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
  assert( res == ETALON[ lvl:upper() ] )
end

function test_()
  Make('NO')
  Make('DEFAULT')
  Make('SPEED')
  Make('BEST')
end

local TEST_NAME = 'ZipWriter sink'
if _VERSION >= 'Lua 5.2' then  _ENV = lunit.module(TEST_NAME,'seeall')
else module( TEST_NAME, package.seeall, lunit.testcase ) end

local function Make(lvl)
  local out    = memfile.open("", "wb")

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
  assert( res == ETALON[ lvl:upper() ] )
end

function test_()
  Make('NO')
  Make('DEFAULT')
  Make('SPEED')
  Make('BEST')
end

local TEST_NAME = 'ZipWriter source'
if _VERSION >= 'Lua 5.2' then  _ENV = lunit.module(TEST_NAME,'seeall')
else module( TEST_NAME, package.seeall, lunit.testcase ) end

local ETALON = { -- testd with winrar 3.93 / 7-Zip 9.20.04 alpha
  NO      = [[UEsDBAoACAAAADVwM0EAAAAAAAAAAAAAAAAIAAAAdGVzdC50eHQxMTExMTExMTExMTExMTExMTExMQ0KMjIyMjIyMjIyMjIyMjIyMjIyMjJQSwcIOsw+PSoAAAAqAAAAUEsBAhQACgAIAAAANXAzQTrMPj0qAAAAKgAAAAgAAAAAAAAAAAAgAAAAAAAAAHRlc3QudHh0UEsFBgAAAAABAAEANgAAAGAAAAAAAA==]];
  DEFAULT = [[UEsDBBQACAAIADVwM0EAAAAAAAAAAAAAAAAIAAAAdGVzdC50eHQzNMQEvFxGWAAAUEsHCDrMPj0KAAAAKgAAAFBLAQIUABQACAAIADVwM0E6zD49CgAAACoAAAAIAAAAAAAAAAEAIAAAAAAAAAB0ZXN0LnR4dFBLBQYAAAAAAQABADYAAABAAAAAAAA=]];
  SPEED   = [[UEsDBBQADAAIADVwM0EAAAAAAAAAAAAAAAAIAAAAdGVzdC50eHQzNMQEvFxGWAAAUEsHCDrMPj0KAAAAKgAAAFBLAQIUABQADAAIADVwM0E6zD49CgAAACoAAAAIAAAAAAAAAAEAIAAAAAAAAAB0ZXN0LnR4dFBLBQYAAAAAAQABADYAAABAAAAAAAA=]];
  BEST    = [[UEsDBBQACgAIADVwM0EAAAAAAAAAAAAAAAAIAAAAdGVzdC50eHQzNMQEvFxGWAAAUEsHCDrMPj0KAAAAKgAAAFBLAQIUABQACgAIADVwM0E6zD49CgAAACoAAAAIAAAAAAAAAAEAIAAAAAAAAAB0ZXN0LnR4dFBLBQYAAAAAAQABADYAAABAAAAAAAA=]];
}

local function Make(lvl)
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
  assert( res == ETALON[ lvl:upper() ] )
end

function test_()
  Make('NO')
  Make('DEFAULT')
  Make('SPEED')
  Make('BEST')
end
