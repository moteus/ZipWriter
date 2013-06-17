package="lzlib"
version="0.4.work3-1"
source = {
   url = "https://github.com/LuaDist/lzlib/archive/0.4-work3.zip",
   dir = "lzlib-0.4-work3",
}
description = {
   summary = "Lua bindings to the ZLib compression library",
   detailed = [[
      This package provides a library to access zlib library functions
      and also to read/write gzip files using an interface similar
      to the base io package.
   ]],
   homepage = "http://luaforge.net/projects/lzlib/",
   license = "MIT/X11"
}
dependencies = {
   "lua >= 5.1, < 5.3"
}
external_dependencies = {
   ZLIB = {
      header = "zlib.h",
      library = "z",
   }
}
build = {
   type = "builtin",
   modules = {
      zlib = {
         sources = "lzlib.c",
         libdirs = "$(ZLIB_LIBDIR)",
         incdirs = "$(ZLIB_INCDIR)",
         libraries = "z",
      },
      gzip = "gzip.lua",
   }
}
