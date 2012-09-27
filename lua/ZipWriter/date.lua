local function prequire(m) 
  local ok, err = pcall(require, m) 
  if not ok then return nil, err end
  return err
end

local date = require "date"

local IS_WINDOWS = (package.config:sub(1,1) == '\\')

if IS_WINDOWS then
  local DateToFileTime

  if not DateToFileTime then
    local alien = prequire "alien"
    if false and alien then
      local kernel32 = assert(alien.load("kernel32.dll"))
      local SYSTEMTIME = alien.defstruct{
        {"wYear","ushort" };
        {"wMonth","ushort" };
        {"wDayOfWeek","ushort" };
        {"wDay","ushort" };
        {"wHour","ushort" };
        {"wMinute","ushort" };
        {"wSecond","ushort" };
        {"wMilliseconds","ushort" };
      }
      local FILETIME = alien.defstruct{
        {"dwLowDateTime","uint" };
        {"dwHighDateTime","uint" };
      }
      if(SYSTEMTIME.size == 16)and(FILETIME.size == 8)then
        local SystemTimeToFileTime_ = assert(kernel32.SystemTimeToFileTime) -- win2k+
        SystemTimeToFileTime_:types{abi="stdcall", ret = "int", "pointer","pointer"}
        DateToFileTime = function(d)
          local st = SYSTEMTIME:new()
          local ft = FILETIME:new()
          st.wYear         = assert(d:getyear())
          st.wMonth        = assert(d:getmonth())
          st.wDayOfWeek    = assert(d:getweekday())
          st.wDay          = assert(d:getday())
          st.wHour         = assert(d:gethours())
          st.wMinute       = assert(d:getminutes())
          st.wSecond       = assert(d:getseconds())
          st.wMilliseconds = assert(d:getticks())
          local ret = SystemTimeToFileTime_(st(), ft())
          return (ret ~= 0) and {ft.dwLowDateTime, ft.dwHighDateTime}
        end
      end
    end
  end

  if not DateToFileTime then
    local ffi = prequire "ffi"
    if ffi then
      ffi.cdef [[
         struct SYSTEMTIME{
           uint16_t  wYear;
           uint16_t  wMonth;
           uint16_t  wDayOfWeek;
           uint16_t  wDay;
           uint16_t  wHour;
           uint16_t  wMinute;
           uint16_t  wSecond;
           uint16_t  wMilliseconds;
         } ;
         struct FILETIME{
           uint32_t dwLowDateTime;
           uint32_t dwHighDateTime;
         } ;
         int32_t SystemTimeToFileTime(const struct SYSTEMTIME *src, struct FILETIME *dst);
         uint32_t GetLastError();
      ]]
      local ffi_C = ffi.C
      local SYSTEMTIME = ffi.typeof('struct SYSTEMTIME')
      local FILETIME = ffi.typeof('struct FILETIME')

    
      DateToFileTime = function(d)
        local st = SYSTEMTIME{
          d:getyear(),d:getmonth(),d:getweekday(),
          d:getday(),d:gethours(),d:getminutes(),
          d:getseconds(),(d:getticks())
        }
        local ft = FILETIME()
        local ret = ffi_C.SystemTimeToFileTime(st, ft)
        return (ret ~= 0) and {ft.dwLowDateTime, ft.dwHighDateTime}
      end
    end
  end

  if DateToFileTime then
    getmetatable(date()).asfiletime = DateToFileTime
  end
end

local bit = prequire "bit"
if bit then
  local function time2dos(d)
    return bit.bor(
      bit.lshift(d:getyear()-1980, 25),
      bit.lshift(d:getmonth(),     21),
      bit.lshift(d:getday(),       16),
      bit.lshift(d:gethours(),     11),
      bit.lshift(d:getminutes(),   5),
      bit.rshift(d:getseconds(),   1)
    )
  end
  getmetatable(date()).asdostime = time2dos
end

return date