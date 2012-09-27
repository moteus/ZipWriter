local IS_WINDOWS = package.config:sub(1,1) == '\\'

local ZipWriter = require "ZipWriter"
local PATH      = require "path"
local lfs       = require "lfs"

local TEXT_EXT = {".lua", ".txt", ".c", ".cpp", ".h", ".hpp", ".pas", ".cxx", ".me"}

local function isin(s, t)
  local s = s:lower()
  for _, v in ipairs(t) do if s == v then return true end end
end

local function make_file_desc(path)
  local fullpath = PATH.fullpath(path)

  local desc = {}
  desc.isfile = PATH.isfile(fullpath)
  desc.isdir  = PATH.isdir(fullpath)

  if not (desc.isfile or desc.isdir) then error('file not found :' .. path .. ' (' .. fullpath .. ')') end

  desc.mtime = PATH.getmtime(fullpath)
  desc.ctime = PATH.getctime(fullpath)
  desc.atime = PATH.getatime(fullpath)

  local ext = desc.isfile and PATH.extension(fullpath)
  desc.istext = ext and isin(ext, TEXT_EXT)
  desc.exattrib = PATH.fileattrib and PATH.fileattrib(fullpath)

  return desc
end

local function file_reader(path, chunk_size)
  local desc = assert(make_file_desc(path))
  local f = desc.isfile and assert(io.open(path, 'rb'))
  chunk_size = chunk_size or 4096
  return desc, desc.isfile and function()
    local chunk = f:read(chunk_size)
    if chunk then return chunk end
    f:close()
  end
end

local function file_writer(path)
  local f = assert(io.open(path, 'wb+'))
  return 
  function(chunk)
    if not chunk then return f:close() end
    f:write(chunk)
  end
  ,function(...) return f:seek(...) end
end

local function matchfiles(mask, recursive, cb)
  local function filePat2rexPat(pat)
    local pat = pat:gsub("%.","%%%."):gsub("%*",".*"):gsub("%?", ".")
    if IS_WINDOWS then pat = pat:upper() end
    return pat
  end

  local basepath,mask = PATH.splitpath(mask)
  mask = filePat2rexPat(mask)

  local function match(s, pat)
    if IS_WINDOWS then s = string.upper(s) end
    return nil ~= string.find(s, pat)
  end

  local function filelist (path, pat, cb)
    for file in lfs.dir(path) do if file ~= "." and file ~= ".." then
      local cur_file = PATH.join(path, file)
      if PATH.isfile(cur_file) then
        if match(file, pat) then 
          cb(path, file)
        end
      end
    end end
    return true
  end

  local function filelist_recurcive (path, pat, cb)
    filelist(path, pat, cb)
    for file in lfs.dir(path) do if file ~= "." and file ~= ".." then
      local cur_dir = PATH.join(path, file)
      if PATH.isdir(cur_dir) then
        files = filelist_recurcive(cur_dir, pat, cb)
      end
    end end
    return true
  end

  if recursive then
    return filelist_recurcive(basepath, mask, cb)
  end
  return filelist(basepath, mask, cb)
end

if not arg[1] then
  print("Usage: mkarch <archive_name> [<file_mask>]")
  return
end

local oFile = assert(arg[1])
local mask  = arg[2] or "*.*"
local mask = PATH.fullpath(mask)
local base = PATH.dirname(mask)

if PATH.extension(oFile):lower() ~= '.zip' then
  oFile = oFile .. '.zip'
end

local files = {}
matchfiles(mask, true, function(path, name) 
  local fullpath = PATH.fullpath(PATH.join(path,name))
  local relpath = string.sub(fullpath, #base + 1)
  table.insert(files,{fullpath, relpath})
end)

writer = ZipWriter.new{
  level = ZipWriter.COMPRESSION_LEVEL.DEFAULT;
  zip64 = false;
  utf8  = false;
}
writer:open_writer(file_writer(oFile))

for _, t in ipairs(files) do
  local fullpath,fileName = t[1],t[2]
  io.write("Add : " .. fileName .. ' (' .. fullpath .. ')')
  writer:write(fileName, file_reader(fullpath))
  io.write(' OK!\n')
end

writer:close()