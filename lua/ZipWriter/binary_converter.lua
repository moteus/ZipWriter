local string = require "string"

local struct_unpack, struct_pack, struct_size
if string.pack then
  struct_unpack, struct_pack, struct_size = assert(string.unpack), assert(string.pack)
else
  local struct = require "struct"
  struct_unpack, struct_pack, struct_size = assert(struct.unpack), assert(struct.pack), assert(struct.size)
end

local string_byte, string_char, string_gsub = string.byte, string.char, string.gsub
local table_concat = table.concat

local pairs,assert,setmetatable = pairs,assert,setmetatable

local unpack = unpack or table.unpack
local math_mod = function(...) 
  local a,b = math.modf(...)
  return b
end

local converter_t = {
  int64  = {"i8",8};
  uint64 = {"I8",8};
  int32  = {"i4",4};
  uint32 = {"I4",4};
  int16  = {"i2",2};
  uint16 = {"I2",2};

  -- little endian
  le_int64  = {"<i8",8};
  le_uint64 = {"<I8",8};
  le_int32  = {"<i4",4};
  le_uint32 = {"<I4",4};
  le_int16  = {"<i2",2};
  le_uint16 = {"<I2",2};

  -- big endian
  be_int64  = {">i8",8};
  be_uint64 = {">I8",8};
  be_int32  = {">i4",4};
  be_uint32 = {">I4",4};
  be_int16  = {">i2",2};
  be_uint16 = {">I2",2};

  int8   = {"b" ,1};
  uint8  = {"B" ,1};

}

if not string.pack then
  converter_t.pchar  = {"c0",0};
end

if struct_size then
  for _, t in pairs(converter_t)do
    if t[2] > 0 then
      assert(struct_size(t[1]) == t[2])
    end
  end
end

local converter = {
  pack         = struct_pack;
  unpack       = struct_unpack;
  struct_size  = struct_size;
  types        = converter_t;
}
-- @param art  - тип элемента
-- @param data - бинарное представление массива элементов art
-- @param size - количечтво элементов в массиве (optional)
converter.unpack_array = function(art, data, size)
  if not size then
    local elem_size = struct_size(art)
    assert(0 == math_mod(#data, elem_size))
    size = math.floor(#data / elem_size)
  end
  local fmt = string.rep(art, size)
  local t = {struct_unpack(fmt,data)}
  table.remove(t)
  return t
end;

-- @param art  - тип элемента
-- @param data - массив элементов art
-- @param size - количечтво элементов в массиве (optional)
converter.pack_array = function(art, data, size)
  size = size or #data
  local fmt = string.rep(art, size)
  return struct_pack(fmt, unpack(data))
end;

converter.unpack_array_ex = function(art, data, size)
  local s = 1
  local t = {}
  for i = 1, size do
    local elem = {struct_unpack(art,data,s)}
    s = elem[#elem]
    table.remove(elem)
    if #elem > 1 then 
      t[i] = elem
    else
      t[i] = elem[1]
    end
  end
  return t
end;

converter.pack_array_ex = function(art, data, size)
  if type(data[1]) ~= 'table' then
    return converter.pack_array(art, data, size)
  end
  size = size or #data
  local s = ""
  for i = 1, size do
    s = s .. struct_pack(art, unpack(data[i]))
  end
  return s
end;

converter.STRUCT = function (t)
  local len = 0
  for i,v in pairs(t) do
    assert(v, "Unknown field #" .. i)
    len = len + 1;
  end
  assert(#t == len," Thera are unknown fields in struct")
  return table_concat(t) 
end;

converter.as = function(type_mnemo, val) return struct_pack(type_mnemo,struct_unpack(type_mnemo,val)) end;

if converter.struct_size then --test converter
  local function cmp_arr(t1,t2)
    if #t1 ~= #t2 then return false end
    for k,v in ipairs(t1)do
      if t2[k] ~= v then return false end
    end
    return true
  end
  local function test(types, ar)
    for _,fmt in ipairs(types) do
      local data = converter.pack_array(fmt, ar)
      assert(converter.struct_size(fmt) * #ar == #data)
      assert(cmp_arr(ar, converter.unpack_array(fmt,data)))
    end
  end
  test(
    {"i2","i4","b","I2","I4","B"},
    {1,2,3,4,5,6,7,8,9}
  )
  test(
    {"i2","i4","b"},
    {1,2,3,4,5,6,7,8,9,-1,-2,-3,-4,-5,-6,-7,-8,-9}
  )
end

for typename, vt in pairs(converter_t) do
  local type_mnemo =  assert(vt[1])
  local type_size  =  assert(vt[2])

  local stream_to_type = function(val) return struct_unpack(type_mnemo,val) end
  local type_to_stream = function(val) return struct_pack(type_mnemo,val) end
  local lua_as_type    = function(val) return struct_unpack(type_mnemo, struct_pack(type_mnemo,val) ) end

  converter["to_" .. typename] = stream_to_type
  converter[typename .. "_to"] = type_to_stream
  converter[typename .. "_t" ] = type_mnemo
  converter["as_" .. typename] = lua_as_type
end


return converter