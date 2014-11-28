cmake_minimum_required ( VERSION 2.8 )

project ( ZipWriter NONE )
include ( cmake/dist.cmake )
include ( lua )

install_lua_module ( ZipWriter                  lua/ZipWriter.lua                   )
install_lua_module ( ZipWriter.win.cp           lua/ZipWriter/win/cp.lua            )
install_lua_module ( ZipWriter.binary_converter lua/ZipWriter/binary_converter.lua  )
install_lua_module ( ZipWriter.charset          lua/ZipWriter/charset.lua           )
install_lua_module ( ZipWriter.utils            lua/ZipWriter/utils.lua             )
install_lua_module ( ZipWriter.bit              lua/ZipWriter/bit.lua               )
install_lua_module ( ZipWriter.encrypt.aes      lua/ZipWriter/encrypt/aes.lua       )

install_data ( README.md LICENCE.txt )

install_test ( test/ )

