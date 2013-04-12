Library for creating ZIP archive for Lua 5.1/5.2.
Based on http://wiki.tcl.tk/15158

## Dependences ##

- lzlib
- struct
- bit32 or bit
- iconv (if not found then file names passed as is)
- alien/ffi (on Windos detect system default codepage)
- lunit (only for test)
- memoryfile (only for test)

## Supports ##
- write to non seekable stream
- utf8 file names in archives (required iconv)
- ZIP64 (does not use stream:seek())
 
## Usage ##

Make simple archive

```lua
function make_reader(fname)
  local f = assert(io.open(fname, 'rb'))
  local chunk_size = 1024
  local desc = {
    istext   = true,
    isfile   = true,
    isdir    = false,
    mtime    = 1348048902, -- lfs.attributes('modification') 
    exattrib = 32,         -- get from GetFileAttributesA
  }
  return desc, desc.isfile and function()
    local chunk = f:read(chunk_size)
    if chunk then return chunk end
    f:close()
  end
end

local ZipWriter = require "ZipWriter"
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
