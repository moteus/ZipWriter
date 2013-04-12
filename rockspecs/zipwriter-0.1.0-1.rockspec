package = "ZipWriter"
version = "0.1.0-1"
source = {
  url = "https://github.com/moteus/ZipWriter/archive/v0.1.0.zip",
  dir = "ZipWriter-0.1.0",
}

description = {
  summary = "Library for creating ZIP archive for Lua 5.1/5.2",
  homepage = "https://github.com/ZipWriter",
  detailed = [[This package provides a library to create zip archives.
  This library support non seekable streams (e.g. socket) and ZIP64 format.
  ]],
  license  = "MIT/X11",
}

dependencies = {
  "lua >= 5.1",
  "struct >= 1.2",
  "bit32",
  "lzlib",
  -- "lua-iconv >= 7.0",  -- optional
  -- "alien >= 0.7.0",    -- optional on windows
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
    ["ZipWriter" ]                 = "lua/ZipWriter.lua",
    ["ZipWriter.binary_converter"] = "lua/ZipWriter/binary_converter.lua",
    ["ZipWriter.charset"]          = "lua/ZipWriter/charset.lua",
    ["ZipWriter.utils"]            = "lua/ZipWriter/utils.lua",
  }
}



