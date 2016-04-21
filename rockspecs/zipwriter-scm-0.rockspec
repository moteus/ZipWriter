package = "ZipWriter"
version = "scm-0"
source = {
  url = "https://github.com/moteus/ZipWriter/archive/master.zip",
  dir = "ZipWriter-master",
}

description = {
  summary = "Library for creating ZIP archive for Lua",
  homepage = "https://github.com/moteus/ZipWriter",
  detailed = [[This package provides a library to create zip archives.
  This library support non seekable streams (e.g. socket), ZIP64 format and AES encrypting.
  ]],
  license  = "MIT/X11",
}

dependencies = {
  "lua >= 5.1, < 5.4",
  -- "lzlib",
  -- "lua-zlib",
  -- "struct >= 1.2",       -- For Lua < 5.3
  -- "bit32",               -- Lua 5.1 only
  -- "aesfileencrypt",      -- optional fast aes encryption
  -- "luacrypto >= 0.3.0",  -- optional to support aes
  -- "lua-iconv >= 7.0",    -- optional
  -- "alien >= 0.7.0",      -- optional on windows
}

build = {
  type = "builtin",
  copy_directories = {"test"},

  platforms = {
    windows = {
      modules = {
        ["ZipWriter.win.cp"]  = "lua/ZipWriter/win/cp.lua",
      }
    }
  },

  modules = {
    ["ZipWriter" ]                           = "lua/ZipWriter.lua",
    ["ZipWriter.module"]                     = "lua/ZipWriter/module.lua",
    ["ZipWriter.binary_converter"]           = "lua/ZipWriter/binary_converter.lua",
    ["ZipWriter.charset"]                    = "lua/ZipWriter/charset.lua",
    ["ZipWriter.bit"]                        = "lua/ZipWriter/bit.lua",
    ["ZipWriter.utils"]                      = "lua/ZipWriter/utils.lua",
    ["ZipWriter.encrypt.aes"]                = "lua/ZipWriter/encrypt/aes.lua",
    ["ZipWriter.encrypt.aes.AesFileEncrypt"] = "lua/ZipWriter/encrypt/aes/AesFileEncrypt.lua",
  }
}



