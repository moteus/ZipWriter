--- Create zip archives.
--
-- Based on http://wiki.tcl.tk/15158
--
-- @module ZipWriter
--
-- @usage
-- local ZipWriter = require "ZipWriter"
--
-- local function make_reader(fname)
--   local f = assert(io.open(fname, 'rb'))
--   local chunk_size = 1024
--   local desc = { -- `-rw-r-----` on Unix
--     istext   = true,
--     isfile   = true,
--     isdir    = false,
--     mtime    = 1348048902, -- lfs.attributes('modification') 
--     platform = 'unix',
--     exattrib = {
--       ZipWriter.NIX_FILE_ATTR.IFREG,
--       ZipWriter.NIX_FILE_ATTR.IRUSR,
--       ZipWriter.NIX_FILE_ATTR.IWUSR,
--       ZipWriter.NIX_FILE_ATTR.IRGRP,
--       ZipWriter.DOS_FILE_ATTR.ARCH,
--     },
--   }
--   return desc, desc.isfile and function()
--     local chunk = f:read(chunk_size)
--     if chunk then return chunk end
--     f:close()
--   end
-- end
-- 
-- ZipStream = ZipWriter.new()
-- ZipStream:open_stream( assert(io.open('readme.zip', 'w+b')), true )
-- ZipStream:write('README.md', make_reader('README.md'))
-- ZipStream:close()
--
-- @usage
-- -- Make encrypted archive
-- local ZipWriter  = require"ZipWriter"
-- local AesEncrypt = require"ZipWriter.encrypt.aes"
-- 
-- ZipStream = ZipWriter.new{
--   encrypt = AesEncrypt.new('password')
-- }
-- 
-- -- as before
--

local zlib             = require "zlib"
local utils            = require "ZipWriter.utils"
local stream_converter = require "ZipWriter.binary_converter"
local bit              = utils.bit

local ZLIB_NO_COMPRESSION      = zlib.NO_COMPRESSION       or  0
local ZLIB_BEST_SPEED          = zlib.BEST_SPEED           or  1
local ZLIB_BEST_COMPRESSION    = zlib.BEST_COMPRESSION     or  9
local ZLIB_DEFAULT_COMPRESSION = zlib.DEFAULT_COMPRESSION  or -1

local sc = stream_converter

local unpack = unpack or table.unpack
local stdout = io.stdout
local fmt = string.format
local function dump_byte(data, n)
  for i = 1, n do 
    local n = sc.unpack(sc.uint8_t, data, i)
    stdout:write(fmt("0x%.2X ", n))
    if i == 16 then stdout:write('\n') end
  end
  if math.mod(n, 16) ~= 0 then stdout:write('\n') end
end

local function o(n) return tonumber(n, 8) end

local function orflags(n, t)
  if not t then return n end

  if type(t) == 'table' then
    return bit.bor(n, unpack(t))
  end

  return bit.bor(n, t)
end

local IS_WINDOWS  = utils.IS_WINDOWS
local LUA_VER_NUM = utils.LUA_VER_NUM

local toutf8        = assert(utils.loc2utf8)
local todos         = assert(utils.loc2dos)
local time2dos      = assert(utils.time2dos)
local time2filetime = utils.time2filetime

local correct_crc
if LUA_VER_NUM < 503 then
  -- we need this because of bug in lzlib 0.4.1
  -- on system when lua_Integer is 32 bit.
  -- we need represent crc as signed int
  correct_crc   = assert(stream_converter.as_int32)
  assert(correct_crc(0xFFFFFFFF) == -1)
else
  -- Assume that in Lua 5.3 lua_Integer is 64 bit
  -- or there will be fix when move lzlib to Lua 5.3
  correct_crc   = function(x) return x end
end

local STRUCT        = assert(stream_converter.STRUCT)
local struct_pack   = assert(stream_converter.pack)
local uint8_t       = assert(stream_converter.uint8_t)
local uint64_t      = assert(stream_converter.le_uint64_t)
local uint32_t      = assert(stream_converter.le_uint32_t)
local uint16_t      = assert(stream_converter.le_uint16_t)
local pchar_t       = stream_converter.pchar_t

local STRUCT_LOCAL_FILE_HEADER = STRUCT{
  uint32_t; -- signature 0x04034b50           
  uint16_t; -- version needed to extract       
  uint16_t; -- general purpose bit flag        
  uint16_t; -- compression method              
  uint32_t; -- uint16_t; -- last mod file time 
            -- uint16_t; -- last mod file date 
  uint32_t; -- crc-32                          
  uint32_t; -- compressed size                 
  uint32_t; -- uncompressed size               
  uint16_t; -- file name length                
  uint16_t; -- extra field length              
  pchar_t;  -- file name
  pchar_t;  -- extra field
}
local LFH_METHOD_OFFSET = 4 + 2 + 2

local STRUCT_DATA_DESCRIPTOR = STRUCT{
  uint32_t; -- signature 0x08074B50           
  uint32_t; -- crc-32                         
  uint32_t; -- compressed size                
  uint32_t; -- uncompressed size              
}

local STRUCT_DATA_DESCRIPTOR64 = STRUCT{
  uint32_t; -- signature 0x08074B50           
  uint32_t; -- crc-32                         
  uint64_t; -- compressed size                
  uint64_t; -- uncompressed size              
}

local STRUCT_CENTRAL_DIRECTORY = STRUCT{
  uint32_t;    -- central file header signature   (0x02014b50)
  uint16_t;    -- version made by                 
  uint16_t;    -- version needed to extract       
  uint16_t;    -- general purpose bit flag        
  uint16_t;    -- compression method              
  uint32_t;    -- uint16_t - last mod file time   
               -- uint16_t - last mod file date   
  uint32_t;    -- crc-32                          
  uint32_t;    -- compressed size                 
  uint32_t;    -- uncompressed size               
  uint16_t;    -- file name length                
  uint16_t;    -- extra field length              
  uint16_t;    -- file comment length             
  uint16_t;    -- disk number start               
  uint16_t;    -- internal file attributes        
  uint32_t;    -- external file attributes        
  uint32_t;    -- relative offset of local header 

  pchar_t;     -- file name (variable size)
  pchar_t;     -- extra field (variable size)
  pchar_t;     -- file comment (variable size)
}

local STRUCT_ZIP64_EOCD = STRUCT{
  uint32_t; -- signature 
  uint64_t; -- size of zip64 end of central directory record                
  uint16_t; -- version made by                 
  uint16_t; -- version needed to extract       
  uint32_t; -- number of this disk             
  uint32_t; -- number of the disk with the start of the central directory  
  uint64_t; -- total number of entries in the central directory on this disk  
  uint64_t; -- total number of entries in the central directory               
  uint64_t; -- size of the central directory   
  uint64_t; -- offset of start of central directory with respect to the starting disk number        
  pchar_t;  -- zip64 extensible data sector (variable size)
}
local ZIP64_EOCD_SIZE = (4 + 8 + 2 + 2 + 4 + 4 + 8 + 8 + 8 + 8)

local STRUCT_EOCD = STRUCT{
  uint32_t;    -- end of central dir signature      (0x06054b50)
  uint16_t;    -- number of this disk             
               -- number of the disk with the
  uint16_t;    -- start of the central directory  
               -- total number of entries in the
  uint16_t;    -- central directory on this disk  
               -- total number of entries in
  uint16_t;    -- the central directory           
  uint32_t;    -- size of the central directory   
               -- offset of start of central
               -- directory with respect to
  uint32_t;    -- the starting disk number        
  uint16_t;    -- .ZIP file comment length        
            
  pchar_t;     -- .ZIP file comment       (variable size)
}

local STRUCT_ZIP64_EXTRA = STRUCT{
  uint64_t; -- Original uncompressed file size
  uint64_t; -- Size of compressed data
  uint64_t; -- Offset of local header record
  uint32_t; --Number of the disk on which this file starts 
}

local STRUCT_ZIP64_EOCD_LOCATOR = STRUCT{
  uint32_t; -- signature 
  uint32_t; -- number of the disk with the start of the zip64 end of central directory 
  uint64_t; -- relative offset of the zip64 end of central directory record 
  uint32_t; -- total number of disks
}

local BIT={[0]=1,2,4,8,16,32,64,128,256,512,1024,2048,4096}

local ZIP_FLAGS = {
  UTF8                   = BIT[11];
  CRC_IN_DESCRIPTOR      = BIT[3];

  DEFLATE_NORMAL         = 0;
  DEFLATE_MAXIMUM        = BIT[1];
  DEFLATE_FAST           = BIT[2];
  DEFLATE_SUPER_FAST     = bit.bor(BIT[1], BIT[2]);

  ENCRYPT                = BIT[0]; -- general purpose bit flags
}

local ZIP_SIG = {
  LFH                = 0x04034B50;
  DATA_DESCRIPTOR    = 0x08074B50;
  CFH                = 0x02014B50;
  EOCD               = 0x06054B50;
  ZIP64_EOCD         = 0x06064B50;
  ZIP64_EOCD_LOCATOR = 0x07064B50;
}

local ZIP_COMPRESSION_METHOD = {
  STORE = 0;
       -- 1  - The file is Shrunk
       -- 2  - The file is Reduced with compression factor 1
       -- 3  - The file is Reduced with compression factor 2
       -- 4  - The file is Reduced with compression factor 3
       -- 5  - The file is Reduced with compression factor 4
       -- 6  - The file is Imploded
       -- 7  - Reserved for Tokenizing compression algorithm
  DEFLATE = 8;
       -- 9  - Enhanced Deflating using Deflate64(tm)
       -- 10 - PKWARE Data Compression Library Imploding (old IBM TERSE)
       -- 11 - Reserved by PKWARE
       -- 12 - File is compressed using BZIP2 algorithm
       -- 13 - Reserved by PKWARE
       -- 14 - LZMA (EFS)
       -- 15 - Reserved by PKWARE
       -- 16 - Reserved by PKWARE
       -- 17 - Reserved by PKWARE
       -- 18 - File is compressed using IBM TERSE (new)
       -- 19 - IBM LZ77 z Architecture (PFS)
       -- 98 - PPMd version I, Rev 1
  AES     = 99;
}

local ZIP_VERSION_EXTRACT = {
  ["1.0"] = 10;    --  Default value
  ["1.1"] = 11;    --  File is a volume label
  ["2.0"] = 20;    --  File is a folder (directory)
  ["2.0"] = 20;    --  File is compressed using Deflate compression
  ["2.0"] = 20;    --  File is encrypted using traditional PKWARE encryption
  ["2.1"] = 21;    --  File is compressed using Deflate64(tm)
  ["2.3"] = 23;
  ["2.5"] = 25;    --  File is compressed using PKWARE DCL Implode 
  ["2.7"] = 27;    --  File is a patch data set 
  ["4.5"] = 45;    --  File uses ZIP64 format extensions
  ["4.6"] = 46;    --  File is compressed using BZIP2 compression*
  ["5.0"] = 50;    --  File is encrypted using DES
  ["5.0"] = 50;    --  File is encrypted using 3DES
  ["5.0"] = 50;    --  File is encrypted using original RC2 encryption
  ["5.0"] = 50;    --  File is encrypted using RC4 encryption
  ["5.1"] = 51;    --  File is encrypted using AES encryption
  ["5.1"] = 51;    --  File is encrypted using corrected RC2 encryption**
  ["5.2"] = 52;    --  File is encrypted using corrected RC2-64 encryption**
  ["6.1"] = 61;    --  File is encrypted using non-OAEP key wrapping***
  ["6.2"] = 62;    --  Central directory encryption
  ["6.3"] = 63;    --  File is compressed using LZMA
  ["6.3"] = 63;    --  File is compressed using PPMd+
  ["6.3"] = 63;    --  File is encrypted using Blowfish
  ["6.3"] = 63;    --  File is encrypted using Twofish
}

local ZIP_VERSION_MADE = {
  FAT32  = bit.lshift(0,  8); -- MS-DOS and OS/2 (FAT / VFAT / FAT32 file systems)
  AMIGA  = bit.lshift(1,  8); -- Amiga
  OVMS   = bit.lshift(2,  8); -- OpenVMS
  UNIX   = bit.lshift(3,  8); -- UNIX
  VMCMS  = bit.lshift(4,  8); -- VM/CMS
                              --  5 - Atari ST
                              --  6 - OS/2 H.P.F.S.
                              --  7 - Macintosh
                              --  8 - Z-System
                              --  9 - CP/M
                              -- 11 - MVS (OS/390 - Z/OS)
  NTFS   = bit.lshift(10, 8); -- Windows NTFS
                              -- 12 - VSE
                              -- 13 - Acorn Risc
                              -- 14 - VFAT
                              -- 15 - alternate MVS
                              -- 16 - BeOS
                              -- 17 - Tandem
                              -- 18 - OS/400
                              -- 19 - OS/X (Darwin)
  NO_USE = bit.lshift(20, 8); -- 20 thru 255 - unused
}

local ZIP_COMPRESSION_LEVEL = {
  NO_COMPRESSION      = {value = ZLIB_NO_COMPRESSION;       flag = ZIP_FLAGS.DEFLATE_NORMAL;  method = ZIP_COMPRESSION_METHOD.STORE;};
  BEST_SPEED          = {value = ZLIB_BEST_SPEED;           flag = ZIP_FLAGS.DEFLATE_FAST;    method = ZIP_COMPRESSION_METHOD.DEFLATE;};
  BEST_COMPRESSION    = {value = ZLIB_BEST_COMPRESSION;     flag = ZIP_FLAGS.DEFLATE_MAXIMUM; method = ZIP_COMPRESSION_METHOD.DEFLATE;};
  DEFAULT_COMPRESSION = {value = ZLIB_DEFAULT_COMPRESSION;  flag = ZIP_FLAGS.DEFLATE_NORMAL;  method = ZIP_COMPRESSION_METHOD.DEFLATE;};
}

local ZIP_CDH_EXTRA_ID = {
  ZIP64  = 0x0001;    -- Zip64 extended information extra field
  AVINFO = 0x0007;    -- AV Info
          --0x0008      -- Reserved for extended language encoding data (PFS)
  OS2    = 0x0009;    -- OS/2
  NTFS   = 0x000a;    -- NTFS 
  OVMS   = 0x000c;    -- OpenVMS
  UNIX   = 0x000d;    -- UNIX
          --0x000e      -- Reserved for file stream and fork descriptors
  PATCH  = 0x000f;    -- Patch Descriptor
          --0x0014      -- PKCS#7 Store for X.509 Certificates
          --0x0015      -- X.509 Certificate ID and Signature for individual file
          --0x0016      -- X.509 Certificate ID for Central Directory
          --0x0017      -- Strong Encryption Header
          --0x0018      -- Record Management Controls
          --0x0019      -- PKCS#7 Encryption Recipient Certificate List
          --0x0065      -- IBM S/390 (Z390), AS/400 (I400) attributes - uncompressed
          --0x0066      -- Reserved for IBM S/390 (Z390), AS/400 (I400) attributes - compressed
          --0x4690      -- POSZIP 4690 (reserved)
  -- Third party mappings commonly used are:
          --0x07c8      -- Macintosh
          --0x2605      -- ZipIt Macintosh
          --0x2705      -- ZipIt Macintosh 1.3.5+
          --0x2805      -- ZipIt Macintosh 1.3.5+
          --0x334d      -- Info-ZIP Macintosh
          --0x4341      -- Acorn/SparkFS 
          --0x4453      -- Windows NT security descriptor (binary ACL)
          --0x4704      -- VM/CMS
          --0x470f      -- MVS
          --0x4b46      -- FWKCS MD5 (see below)
          --0x4c41      -- OS/2 access control list (text ACL)
          --0x4d49      -- Info-ZIP OpenVMS
          --0x4f4c      -- Xceed original location extra field
          --0x5356      -- AOS/VS (ACL)
          --0x5455      -- extended timestamp
          --0x554e      -- Xceed unicode extra field
          --0x5855      -- Info-ZIP UNIX (original, also OS/2, NT, etc)
          --0x6542      -- BeOS/BeBox
          --0x756e      -- ASi UNIX
          --0x7855      -- Info-ZIP UNIX (new)
  MSOPGH = 0xa220;    -- Microsoft Open Packaging Growth Hint
          --0xfd4a      -- SMS/QDOS
  AES    = 0x9901;
}

local STRUCT_CDH_EXTRA_RECORD = STRUCT{
  uint16_t; -- ID
  uint16_t; -- data size
  pchar_t;  -- data
}

local STRUCT_AES_EXTRA = STRUCT{
  uint16_t; -- Integer version number specific to the zip vendor(`AE` for AES)
  uint16_t; -- 2-character vendor ID  0x0001, 0x0002 (AE-1/AE-2)
  uint8_t;  -- Integer mode value indicating AES encryption strength(0x01-128 0x02-192 0x3-256)
  uint16_t; -- The actual compression method used to compress the file
}

local AES_EXTRA_SIG = bit.lshift(string.byte('E'), 8) + string.byte('A')

local AES_VERSION = {
  AE1 = 0x0001;
  AE2 = 0x0002;
}

local AES_MODE = {
  AES128 = 0x01,
  AES192 = 0x02,
  AES256 = 0x03,
}

-- Based on
-- http://unix.stackexchange.com/questions/14705/the-zip-formats-external-file-attribute

-- 1000|000|110100000|00000000|00100000
-- TTTT|sst|rwxrwxrwx|00000000|00ADVSHR
-- ^^^^|___|_________|________|________ file type as explained above
--     |^^^|_________|________|________ setuid, setgid, sticky
--     |   |^^^^^^^^^|________|________ permissions
--     |   |         |^^^^^^^^|________ This is the "lower-middle byte" your post mentions
--     |   |         |        |^^^^^^^^ DOS attribute bits

-- Extra file attributes for Unix
local NIX_FILE_ATTR = {
  IFIFO  = bit.lshift(o"010000", 16);  -- /* named pipe (fifo) */
  IFCHR  = bit.lshift(o"020000", 16);  -- /* character special */
  IFDIR  = bit.lshift(o"040000", 16);  -- /* directory */
  IFBLK  = bit.lshift(o"060000", 16);  -- /* block special */
  IFREG  = bit.lshift(o"100000", 16);  -- /* regular */
  IFLNK  = bit.lshift(o"120000", 16);  -- /* symbolic link */
  IFSOCK = bit.lshift(o"140000", 16);  -- /* socket */

  ISUID  = bit.lshift(o"004000", 16);  -- /* set user id on execution */
  ISGID  = bit.lshift(o"002000", 16);  -- /* set group id on execution */
  ISTXT  = bit.lshift(o"001000", 16);  -- /* sticky bit */
  IRWXU  = bit.lshift(o"000700", 16);  -- /* RWX mask for owner */
  IRUSR  = bit.lshift(o"000400", 16);  -- /* R for owner */
  IWUSR  = bit.lshift(o"000200", 16);  -- /* W for owner */
  IXUSR  = bit.lshift(o"000100", 16);  -- /* X for owner */
  IRWXG  = bit.lshift(o"000070", 16);  -- /* RWX mask for group */
  IRGRP  = bit.lshift(o"000040", 16);  -- /* R for group */
  IWGRP  = bit.lshift(o"000020", 16);  -- /* W for group */
  IXGRP  = bit.lshift(o"000010", 16);  -- /* X for group */
  IRWXO  = bit.lshift(o"000007", 16);  -- /* RWX mask for other */
  IROTH  = bit.lshift(o"000004", 16);  -- /* R for other */
  IWOTH  = bit.lshift(o"000002", 16);  -- /* W for other */
  IXOTH  = bit.lshift(o"000001", 16);  -- /* X for other */
  ISVTX  = bit.lshift(o"001000", 16);  -- /* save swapped text even after use */
}

-- Extra file attributes for Windows/DOS/FAT32
local DOS_FILE_ATTR = {
  NORMAL = 0x00; -- Normal file
  RDONLY = 0x01; -- Read-only file
  HIDDEN = 0x02; -- Hidden file
  SYSTEM = 0x04; -- System file
  VOLID  = 0x08; -- Volume ID
  SUBDIR = 0x10; -- Subdirectory
  ARCH   = 0x20; -- File changed since last archive
}

local function zip_make_extra(HID, data)
  local v = stream_converter.pack(STRUCT_CDH_EXTRA_RECORD, HID, #data, data)
  if not pchar_t then v = v .. data end
  return v
end

local function zip_extra_pack(HID, struct, ...)
  return zip_make_extra(HID, struct_pack(struct, ...))
end

-------------------------------------------------------------
-- streams

-- convert ZipWriter to stream
local function ZipWriter_as_stream(stream)
  -- @todo use class instead closures
  return {
    stream = stream;
    pos    = assert(stream:get_pos());

    write = function(self, chunk)
      self.stream:write_(chunk)
    end;

    seekable = function(self)
      return self.stream:seekable()
    end;

    get_pos = function(self)
      return self.stream:get_pos()
    end;

    set_pos = function(self, pos)
      return self.stream:set_pos(pos)
    end;

    close  = function(self)
      return self.stream:get_pos() - self.pos
    end;
  }
end

-- 
local function zip_stream(stream, level, method)

  local writer = {
    stream   = stream;
    last_4b  = "";
  }

  function writer:write_block_seekable (cd)
    self.stream:write(cd)
  end

  function writer:write_block_no_seekable (cd)
    local s = cd:sub(-4)
    cd = self.last_4b .. cd:sub(1,-5)
    self.last_4b = s

    self.stream:write(cd)
  end

  function writer:write_first_block(cd)
    self.write_block = assert(self.stream:seekable() and self.write_block_seekable or self.write_block_no_seekable)
    self:write_block(cd:sub(3))
  end

  writer.write_block = writer.write_first_block

  function writer:write(cd)
    self:write_block(cd)
  end

  function writer:close()
    if self.stream:seekable() then
      local pos = assert(self.stream:get_pos())
      assert(self.stream:set_pos(pos-4))
    end
    return self.stream:close()
  end

  local zstream = {
    zd = assert(zlib.deflate(writer, level, method))
  }
  
  function zstream:write(chunk)
    assert(self.zd:write(chunk))
  end

  function zstream:close()
    self.zd:close()
    return writer:close()
  end

  return zstream
end

local function table_stream(dst)
  local size = 0
  return {
    write = function(self, chunk)
      table.insert(dst, chunk)
      size = size + #chunk
    end;

    close = function(self)
      dst = nil
      return size
    end;

    seekable = function()
      return false
    end;
    
    get_pos = function()
      return size;
    end;
  }
end
-------------------------------------------------------------

--- Supported compression levels.
-- @table COMPRESSION_LEVEL
-- @field NO
-- @field DEFAULT
-- @field SPEED
-- @field BEST

--- Params that describe file or directory
-- @table FILE_DESCRIPTION
-- @tfield boolean isfile
-- @tfield boolean isdir
-- @tfield boolean istext
-- @tfield number mtime last modification time. If nil then os.clock used.
-- @tfield number ctime
-- @tfield number atime
-- @tfield number|table exattrib on Windows it can be result of GetFileAttributes. Also it can be array of flags.
-- @tfield string platform
-- @tfield ?string data file content
--
-- @see DOS_FILE_ATTR
-- @see NIX_FILE_ATTR

--- Extra file attributes for Unix
-- @table NIX_FILE_ATTR
-- @field IFIFO  named pipe (fifo)
-- @field IFCHR  character special
-- @field IFDIR  directory
-- @field IFBLK  block special
-- @field IFREG  regular
-- @field IFLNK  symbolic link
-- @field IFSOCK socket
-- @field ISUID  set user id on execution
-- @field ISGID  set group id on execution
-- @field ISTXT  sticky bit
-- @field IRWXU  RWX mask for owner
-- @field IRUSR  R for owner
-- @field IWUSR  W for owner
-- @field IXUSR  X for owner
-- @field IRWXG  RWX mask for group
-- @field IRGRP  R for group
-- @field IWGRP  W for group
-- @field IXGRP  X for group
-- @field IRWXO  RWX mask for other
-- @field IROTH  R for other
-- @field IWOTH  W for other
-- @field IXOTH  X for other
-- @field ISVTX  save swapped text even after use

--- Extra file attributes for Windows/DOS/FAT32
-- @table DOS_FILE_ATTR
-- @field NORMAL Normal file
-- @field RDONLY Read-only file
-- @field HIDDEN Hidden file
-- @field SYSTEM System file
-- @field VOLID  Volume ID
-- @field SUBDIR Subdirectory
-- @field ARCH   File changed since last archive


---
-- @type ZipWriter 
--

local ZipWriter = {}
ZipWriter.__index = ZipWriter

function ZipWriter:new(options)
  options = options or {}

  local t = setmetatable({
    private_ = {
      use_utf8  = options.utf8;
      use_zip64 = options.zip64;
      encrypt   = options.encrypt;
    }
  }, self)
  t:set_level(options.level)

  return t
end

--- Set compression level
-- @tparam table lvl {value=compression level, flag=compression flag, method=compression method }
-- 
-- @see COMPRESSION_LEVEL
function ZipWriter:set_level(lvl)
  if lvl then assert(lvl.value and lvl.flag and lvl.method, "Invalid compression level value")
  else lvl = ZIP_COMPRESSION_LEVEL.DEFAULT_COMPRESSION end
  self.private_.level = lvl
end

--- Set stream as output
-- @param stream have to support write method.
--    Also strean can support seek method.
-- @tparam[opt] boolean autoclose if true then steam:close is called
function ZipWriter:open_stream(stream, autoclose)
  if self.private_.stream == stream then return self end
  self:open_writer(
    function(chunk) 
      if not chunk then 
        if autoclose then return stream:close() end
        return true
      end
      return stream:write(chunk)
    end,
    stream.seek and function(...) return stream:seek(...) end or nil
  )
  self.private_.stream = stream 
  return self
end

--- Set writer as output
-- @param writer callable object. This function called when there is a new chunk of data.
-- @param[opt] seek callable object.
function ZipWriter:open_writer(writer, seek)
  if self.private_.writer == writer then return self end
  self.private_.seek      = seek
  self.private_.writer    = writer
  self.private_.headers   = {}; -- we can not transfer data from old stream
  self.private_.begin_pos = self:seek("cur", 0) or 0
  self.private_.pos       = self.private_.begin_pos
  return self
end

--
-- @local
function ZipWriter:str2utf8(str)
  return (self.private_.use_utf8 and toutf8 or todos)(str)
end

--
-- @local
function ZipWriter:use_utf8()
  return self.private_.use_utf8
end

--
-- @local
function ZipWriter:use_zip64()
  return self.private_.use_zip64
end

--
-- @local
function ZipWriter:seek(...)
  local seek = self.private_.seek
  if not seek then return nil, "not supported" end
  return seek(...)
end

--
-- @local
function ZipWriter:seekable()
  return self:seek('cur', 0) and true
end

--
-- @local
function ZipWriter:set_pos(pos)
  self.private_.pos = pos
  return self:seek("set", pos)
end

--
-- @local
function ZipWriter:get_pos()
  local pos = self:seek("cur", 0)
  assert((pos == nil) or (pos == self.private_.pos))
  return pos or self.private_.pos
end

--
-- @local
function ZipWriter:write_(str)
  self.private_.writer(str)
  self.private_.pos = self.private_.pos + #str
end

--
-- @local
function ZipWriter:write_fmt_(...)
  return self:write_(struct_pack(...))
end

--- Add one file to archive.
-- @tparam string fileName
-- @tparam FILE_DESCRIPTION fileDesc
-- @tparam ?callable reader must return nil on end of data
-- @tparam ?string comment
-- @see FILE_DESCRIPTION
function ZipWriter:write(
  fileName, fileDesc,
  reader, comment
)
  comment = comment or ""

  local utfpath    = self:str2utf8(fileName)
  local utfcomment = self:str2utf8(comment)

  local flags      = self:use_utf8() and ZIP_FLAGS.UTF8 or 0
  local level      = self.private_.level
  local method     = level.method

  local cdextra    = "" -- to central directory
  local extra      = ""
  local crc        = zlib.crc32()
  local seekable   = self:seekable()

  local encrypt    = fileDesc.encrypt or self.private_.encrypt

  local use_aes  = false
  if encrypt then
    if encrypt:type() ~= 'aes' then error('unsupported encrypt method: ' .. encrypt:type()) end
    use_aes = true
  end
  local AES_MODE = use_aes and encrypt:mode()
  local AES_VER  = use_aes and encrypt:version()

  local fileDesc_mtime = time2dos(fileDesc.mtime)
  local inattrib = fileDesc.istext and 1 or 0 -- internal file attributes
  local version  = fileDesc.ver_extr or ZIP_VERSION_EXTRACT["2.0"]

  if method == ZIP_COMPRESSION_METHOD.STORE then  -- winrar 3.93 do this
    inattrib = 0
  end

  if use_aes then
    version = ZIP_VERSION_EXTRACT["5.1"] -- @encrypt 7z do this
  else
    if method == ZIP_COMPRESSION_METHOD.STORE and fileDesc.isfile then  -- winrar 3.93 and 7z do this
      version = ZIP_VERSION_EXTRACT["1.0"]
    end
  end

  local ver_made 
  if use_aes then
    ver_made = ZIP_VERSION_EXTRACT["6.3"] -- @encrypt 7z do this
  else 
    ver_made = ZIP_VERSION_EXTRACT["2.0"]
  end

  local platform_made = fileDesc.platform
  if not platform_made then
    platform_made = IS_WINDOWS and 'fat32' or 'unix'
  elseif platform_made:lower() == 'windows' then
    platform_made = 'fat32' -- for compatability
  end
  platform_made = ZIP_VERSION_MADE[platform_made:upper()] or ZIP_VERSION_MADE.UNIX

  ver_made = bit.bor( ver_made, platform_made )

  if fileDesc.isfile then
    flags = bit.bor(flags, level.flag)
    if not seekable then
      flags = bit.bor(flags, ZIP_FLAGS.CRC_IN_DESCRIPTOR)
    end
  end

  local size   = 0
  local csize  = 0
  local offset = self:get_pos()

  if use_aes then
    local e = zip_extra_pack(ZIP_CDH_EXTRA_ID.AES, STRUCT_AES_EXTRA, 
      AES_VER, AES_EXTRA_SIG, AES_MODE, method)
    extra   = extra   .. e
    cdextra = cdextra .. e -- export to CD
    flags   = bit.bor(flags, ZIP_FLAGS.ENCRYPT)
  end

  local offset_extra_zip64
  if self:use_zip64() then
    offset_extra_zip64 = #extra + 4 -- position in extra field (skeep HeaderID and FieldSize)
    extra = extra .. zip_extra_pack(ZIP_CDH_EXTRA_ID.ZIP64, STRUCT_ZIP64_EXTRA, 
      size, csize, offset - self.private_.begin_pos, 0
    )
    size   = 0xFFFFFFFF
    csize  = 0xFFFFFFFF
  end

  self:write_fmt_(STRUCT_LOCAL_FILE_HEADER,
    ZIP_SIG.LFH, version, flags, 
    use_aes and ZIP_COMPRESSION_METHOD.AES or method,
    fileDesc_mtime, crc,
    csize, size, #utfpath, #extra,
    utfpath, extra
  )
  if not pchar_t then
    self:write_(utfpath)
    self:write_(extra)
  end

  if self:use_zip64() then
    -- position in stream
    offset_extra_zip64 = (self:get_pos() - #extra) + offset_extra_zip64
  end

  size   = 0
  csize  = 0

  local reader_error -- error from reader (e.g. access error to file)
  if fileDesc.isfile then
    -- create stream for file data
    local stream = ZipWriter_as_stream(self)
    if use_aes then stream = encrypt:stream(stream, fileDesc) end

    if fileDesc.data then 
      local data = fileDesc.data
      size = #data
      crc = zlib.crc32(crc, data)

      local cdata
      if method == ZIP_COMPRESSION_METHOD.DEFLATE then
        cdata = {}
        local zstream = zip_stream(table_stream(cdata), level.value, method)
        zstream:write(data)
        csize = zstream:close()
 
        -- if we can change method in LFH we can use it
        if seekable and (not use_aes) and (csize > size) then
          method = ZIP_COMPRESSION_METHOD.STORE
          cdata = data
        else cdata = table.concat(cdata) end
      else 
        assert(method == ZIP_COMPRESSION_METHOD.STORE)
        cdata = data
      end

      stream:write(cdata)
    else -- use stream
      if method == ZIP_COMPRESSION_METHOD.DEFLATE then
        stream = zip_stream(stream, level.value, method)
      else assert(method == ZIP_COMPRESSION_METHOD.STORE) end

      local chunk, ctx = reader()
      while(chunk)do
        crc = zlib.crc32(correct_crc(crc), chunk)
        stream:write(chunk)
        size = size + #chunk
        chunk, ctx = reader(ctx)
      end
      reader_error = ctx
    end

    csize = stream:close()

    if use_aes then
      method = ZIP_COMPRESSION_METHOD.AES
      if AES_VER == AES_VERSION.AE2 then crc = 0 end
    end

    if seekable then -- update the header if the output is seekable
      local cur_pos = assert(self:get_pos())
      -- field 'method' can be changed, so we also overwrite it also

      if self:use_zip64() then

        assert(self:set_pos(offset + LFH_METHOD_OFFSET))
        self:write_fmt_( -- begin of STRUCT_LOCAL_FILE_HEADER
          STRUCT{uint16_t;uint32_t;uint32_t;},
          method, fileDesc_mtime, crc
        )

        assert(self:set_pos(offset_extra_zip64))
        self:write_fmt_(STRUCT{uint64_t;uint64_t}, size, csize)

      else
        assert(self:set_pos(offset + LFH_METHOD_OFFSET))
        self:write_fmt_( -- begin of STRUCT_LOCAL_FILE_HEADER
          STRUCT{uint16_t;uint32_t;uint32_t;uint32_t;uint32_t;},
          method, fileDesc_mtime, crc, csize, size
        )
      end
      assert(self:set_pos(cur_pos))
    else
      self:write_fmt_( self:use_zip64() and STRUCT_DATA_DESCRIPTOR64 or STRUCT_DATA_DESCRIPTOR,
        ZIP_SIG.DATA_DESCRIPTOR, crc, csize, size
      )
    end
  end

  if IS_WINDOWS or (fileDesc.platform and (fileDesc.platform:lower() == 'windows')) then
    local m,a,c = fileDesc.mtime,fileDesc.atime,fileDesc.ctime
    if time2filetime and m and a and c then
      local m,a,c = time2filetime(m),time2filetime(a),time2filetime(c)
      local ntfs_elem_001 = STRUCT{
        uint16_t; -- tag  0x0001
        uint16_t; -- size 0x0018
        uint32_t;uint32_t; -- File last modification time
        uint32_t;uint32_t; -- File last access time
        uint32_t;uint32_t; -- File creation time
      }
      local ntfs_extra = zip_make_extra(ZIP_CDH_EXTRA_ID.NTFS,
        stream_converter.pack(uint32_t, 0) .. -- reserved
        stream_converter.pack(ntfs_elem_001, 
          0x0001, 0x0018, m[1],m[2],a[1],a[2],c[1],c[2]
        )
      )
      cdextra = ntfs_extra .. cdextra
    end
  end

  if self:use_zip64() then
    local z64extra = struct_pack(STRUCT_ZIP64_EXTRA, size, csize, offset - self.private_.begin_pos, 0)
    cdextra = cdextra .. zip_make_extra(ZIP_CDH_EXTRA_ID.ZIP64, z64extra)

    size   = 0xFFFFFFFF
    csize  = 0xFFFFFFFF
  end

  local cdh = struct_pack(STRUCT_CENTRAL_DIRECTORY, 
    ZIP_SIG.CFH,ver_made,version, flags, method,
    fileDesc_mtime,crc,csize,size,
    #utfpath, #cdextra, #utfcomment,
    0, inattrib, orflags(0x00, fileDesc.exattrib), offset - self.private_.begin_pos, -- disk number start
    utfpath, cdextra, utfcomment
  )
  if not pchar_t then
    cdh = cdh .. utfpath .. cdextra .. utfcomment
  end
  table.insert(self.private_.headers, cdh)

  if reader_error then return nil, reader_error end

  return true
end

--- Close archive.
-- @tparam ?string comment
function ZipWriter:close(comment)
  local headers = self.private_.headers
  local stream  = self.private_.stream
  comment = self:str2utf8(comment or "")

  local cdPos    = self:get_pos()
  local cdOffset = cdPos - self.private_.begin_pos
  for _, chdr in ipairs(headers) do
    self:write_(chdr)
  end

  local cdLength = self:get_pos() - cdPos
  local filenum = #headers

  if self:use_zip64() then
    local zip64_extra = ""
    local zip64_eocd_size = (ZIP64_EOCD_SIZE + #zip64_extra) - 12
    local zip64_eocd_offset = self:get_pos() - self.private_.begin_pos

    self:write_fmt_(STRUCT_ZIP64_EOCD,
      ZIP_SIG.ZIP64_EOCD, zip64_eocd_size,
      ZIP_VERSION_EXTRACT["6.3"], ZIP_VERSION_EXTRACT["6.3"],
      0,0,-- disk numbers
      filenum,filenum,
      cdLength,cdOffset,
      zip64_extra
    )
    if not pchar_t then
      self:write_(zip64_extra)
    end

    self:write_fmt_(STRUCT_ZIP64_EOCD_LOCATOR,
      ZIP_SIG.ZIP64_EOCD_LOCATOR, 0, zip64_eocd_offset, 0
    )
  end

  self:write_fmt_(STRUCT_EOCD,
    ZIP_SIG.EOCD, 0, 0, -- disk numbers
    filenum,filenum,cdLength,cdOffset,
    #comment, comment
  )
  if not pchar_t then
    self:write_(comment)
  end

  self.private_.writer()
  return filenum;
end

---
-- @section end

local rawget, upper, error, tostring, setmetatable = rawget, string.upper, error,tostring, setmetatable

local M = {}

M.COMPRESSION_LEVEL = setmetatable({
    NO       = assert(ZIP_COMPRESSION_LEVEL.NO_COMPRESSION);
    DEFAULT  = assert(ZIP_COMPRESSION_LEVEL.DEFAULT_COMPRESSION);
    SPEED    = assert(ZIP_COMPRESSION_LEVEL.BEST_SPEED);
    BEST     = assert(ZIP_COMPRESSION_LEVEL.BEST_COMPRESSION);
},{
  __index = function(self,lvl) 
    return rawget(self, upper( lvl )) or 
      error("Unknown compression level " .. tostring(lvl),0)
  end
});

M.NIX_FILE_ATTR = NIX_FILE_ATTR

M.DOS_FILE_ATTR = DOS_FILE_ATTR

--- Create new `ZipWriter` object
--
-- @tparam table options {utf8 = false, zip64 = false, level = DEFAULT}
--
-- @see COMPRESSION_LEVEL
function M.new(...)
  local t = ZipWriter:new(...)
  return t
end


--- Run coroutine and return writer function
--
-- @usage
-- writer = co_writer(function(reader) ... end)
--
-- @see co_reader
function M.co_writer(fn)
  local reciver, err = coroutine.create(function ()
    local reader = function ()
      return coroutine.yield(true)
    end
    fn(reader)
  end)
  if not reciver then return nil, err end
  local ok, err = coroutine.resume(reciver)
  if not ok then return nil, err end

  local function writer(chunk)
    return coroutine.resume(reciver, chunk)
  end

  return writer
end

--- Run coroutine and return reader function
--
-- @usage
-- reader = co_reader(function(writer) ... end)
--
-- @usage
--
-- local function put(reader)
--   local chunk, err
--   while true do
--     chunk, err = reader()
--     if not chunk then break end
--     print(chunk) -- proceed data
--   end
-- end
--
-- local function get(writer)
--   local t = {1111,2222,3333,4444,5555}
--   for k, v in ipairs(t) do 
--     writer(tostring(v)) -- send data
--   end
--   writer() -- EOS
-- end
--
-- get(ZipWriter.co_writer(put))
-- put(ZipWriter.co_reader(get))
--
-- @see co_writer
--
function M.co_reader(fn)
  local sender, err = coroutine.create(function ()
    local writer = function (chunk)
      return coroutine.yield(chunk)
    end
    fn(writer)
  end)
  if not sender then return nil, err end

  local function reader()
    local ok, data = coroutine.resume(sender, true)
    if ok then return data end
    return nil, data
  end

  return reader
end

--- Create new sink that write result to `ZipWriter`
--
-- @usage 
-- local ZipStream = ZipWriter.new()
-- 
-- -- write to ftp
-- --[=[ lua 5.1 needs coco
-- ZipStream:open_writer(ZipWriter.co_writer(function(reader)
--   FTP.put{
--     path = 'test.zip';
--     src  = reader;
--   }
-- end))
-- --]=]
-- 
-- -- write to file 
-- ZipStream:open_stream(assert(io.open('test.zip', 'wb+'))
-- 
-- -- read from FTP
-- FTP.get{
--   -- ftp params ...
--   path = 'test.txt'
--   sink = ZipWriter.sink(ZipStream, 'test.txt', {isfile=true;istext=1})
-- }
-- 
-- ZipStream:close()
--
function M.sink(stream, fname, desc)
  return M.co_writer(function(reader)
    stream:write(fname, desc, reader)
  end)
end

---
--
function M.source(stream, files)
  return M.co_reader(function(writer)
    stream:open_writer(writer)
    for _, file in ipairs(files) do
      local fname, fpath, desc = file[1],file[2],file[3]
      fname, fpath = fname or fpath, fpath or fname
      desc = desc or {isfile=true}
      if desc.isfile then
        local fh = assert(io.open(fpath,'rb'))
        stream:write(fname, desc, function()
          local chunk, err = fh:read()
          if not chunk then fh:close() fh = nil end
          return chunk, err
        end)
      else
        stream:write(fname, desc)
      end
    end
    stream:close()
  end)
end


return M
