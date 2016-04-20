##Library for creating ZIP archive for Lua 5.1/5.2.

Based on http://wiki.tcl.tk/15158

[![Build Status](https://travis-ci.org/moteus/ZipWriter.png)](https://travis-ci.org/moteus/ZipWriter)
[![Coverage Status](https://coveralls.io/repos/moteus/ZipWriter/badge.png)](https://coveralls.io/r/moteus/ZipWriter)
[![Licence](http://img.shields.io/badge/Licence-MIT-brightgreen.svg)](LICENCE.txt)

## Documentation ##

[Documentation](http://moteus.github.io/ZipWriter)

## Dependencies ##

### Core ###
- [lzlib](https://luarocks.org/modules/hisham/lzlib) or [lua-zlib](https://luarocks.org/modules/brimworks/lua-zlib)
- [struct](https://luarocks.org/modules/luarocks/struct) (only for Lua < 5.3)
- [bit32](https://luarocks.org/modules/siffiejoe/bit32) (only for Lua = 5.1)

### Optional ###
- [iconv](https://luarocks.org/modules/luarocks/lua-iconv) (if not found then file names passed as is)
- [alien](https://luarocks.org/modules/mascarenhas/alien) or [ffi](https://github.com/jmckaskill/luaffi)/[ffi](http://luajit.org/ext_ffi.html) (on Windows detect system default codepage)
- [AesFileEncrypt](https://github.com/moteus/lua-AesFileEncrypt) or [LuaCrypto](https://luarocks.org/modules/luarocks/luacrypto)

### Test ###
- [lunitx](https://luarocks.org/modules/dougcurrie/lunitx)
- [lbase64](https://luarocks.org/modules/ignacio/lbase64)

## Supports ##
- write to non seekable stream
- utf8 file names in archives (required iconv)
- ZIP64 (does not use stream:seek())

## Install ##

Since version 0.1.5 rockspec does not have any dependencies because there no way to specify
them as optional. E.g. if you already have installed `lua-zlib` and you then install `lzlib` then
your existed code may stop working. So you have to install appropriate library by hand.
Also some dependencies need only for specific Lua version.

- Install zlib binding
```bash
luarocks install lua-zlib
```
or
```bash
luarocks install lzlib
```

- Lua 5.1/5.2/JIT dependencies
```bash
luarocks install struct
```

- Lua 5.1 dependencies
```bash
luarocks install bit32
```

- Install ZipWriter itself
```bash
luarocks install zipwriter
```

## Usage ##

Make simple archive

```lua
local ZipWriter = require "ZipWriter"

function make_reader(fname)
  local f = assert(io.open(fname, 'rb'))
  local chunk_size = 1024
  local desc = { -- `-rw-r-----` on Unix
    istext   = true,
    isfile   = true,
    isdir    = false,
    mtime    = 1348048902, -- lfs.attributes('modification')
    platform = 'unix',
    exattrib = {
      ZipWriter.NIX_FILE_ATTR.IFREG,
      ZipWriter.NIX_FILE_ATTR.IRUSR,
      ZipWriter.NIX_FILE_ATTR.IWUSR,
      ZipWriter.NIX_FILE_ATTR.IRGRP,
      ZipWriter.DOS_FILE_ATTR.ARCH,
    },
  }
  return desc, desc.isfile and function()
    local chunk = f:read(chunk_size)
    if chunk then return chunk end
    f:close()
  end
end

ZipStream = ZipWriter.new()
ZipStream:open_stream( assert(io.open('readme.zip', 'w+b')), true )
ZipStream:write('README.md', make_reader('README.md'))
ZipStream:close()
```

Reading file from FTP and saving archive on FTP
```lua
local ZipWriter = require "ZipWriter"
local FTP = require "socket.ftp"

local ZipStream = ZipWriter.new()

-- write zip file directly to ftp
-- lua 5.1 needs coco
ZipStream:open_writer(ZipWriter.co_writer(function(reader)
  FTP.put{
    -- ftp params ...
    path = 'test.zip';
    src  = reader;
  }
end))

-- read from FTP
FTP.get{
  -- ftp params ...
  path = 'test.txt'
  sink = ZipWriter.sink(ZipStream, 'test.txt', {isfile=true;istext=1})
}

ZipStream:close()
```

Make encrypted archive
```lua
local ZipWriter  = require"ZipWriter"
local AesEncrypt = require"ZipWriter.encrypt.aes"

ZipStream = ZipWriter.new{
  encrypt = AesEncrypt.new('password')
}

-- as before

```



[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/moteus/zipwriter/trend.png)](https://bitdeli.com/free "Bitdeli Badge")

