------------------------------------------------------------
-- NGINX Static Language Selector
-- Version: 1.0
-- Source: https://github.com/Skymirrh
--
-- Retrieve client language preferences from:
--   - Query parameter
--   - Cookie value
--   - Accept-Language header
--
-- See README for intent, use case, and examples.
------------------------------------------------------------

------------------------------
-- HELPERS
------------------------------

-- String split helper function adapted from https://stackoverflow.com/a/20100401
function string:split(delimiter)
  local result = {};

  for match in (self..delimiter):gmatch("(.-)"..delimiter) do
    table.insert(result, match);
  end

  return result;
end

-- Helper function to sort a list of {key, value} tuples by descending value order with sort()
function sort_by_descending_tuple_value(a, b)
  return a[2] > b[2]
end



------------------------------
-- INPUT ARGUMENTS
------------------------------

-- Set list of supported languages
-- If not provided as $arg1, immediately fail and default to "en"
local supported_languages = ngx.arg[1]
if supported_languages == nil then
  return "en"
else
  supported_languages = supported_languages:split(",");
end

-- Set query parameter name and cookie name where to retrieve client preferences in addition to Accept-Language header
-- If not provided as $arg2, default to "lang"
local query_parameter_and_cookie_name = ngx.arg[2]
if query_parameter_and_cookie_name == nil then
  query_parameter_and_cookie_name = "lang"
end



------------------------------
-- FUNCTIONS
------------------------------

-- Parse a client preferences string formatted using the Accept-Language header syntax, e.g. "en-US,en;q=0.8,fr-FR;q=0.5,fr;q=0.3"
-- Return a list of {language, priority} tuples
local REGEX = [[\s*([-*\w]+)(?:;q=(1|0\.\d+))?\s*(?:,|$)]]
function string:parse_client_preferences()
  local preferences_tuples = {}

  for match in ngx.re.gmatch(self, REGEX) do
    local language, q = unpack(match)

    -- Ignore the "any language" wildcard value ("*")
    if language ~= "*" then
      -- Set priority to 1 if none is present
      local priority
      if q then
        priority = tonumber(q)
      else
        priority = 1
      end

      table.insert(preferences_tuples, {language, priority})
    end
  end

  return preferences_tuples
end

-- Try to match a client preferences string with the list of supported languages
-- Return a matching value from supported list, or nil if no match can be found
function string:match_with_supported()
  -- Parse client preferences string and sort by descending priority
  local preferences_tuples = self:parse_client_preferences()
  table.sort(preferences_tuples, sort_by_descending_tuple_value)

  -- First try an exact match
  for _, tuple in pairs(preferences_tuples) do
    local client_preference = tuple[1]
    for _, supported_language in pairs(supported_languages) do
      if client_preference == supported_language then
        return supported_language
      end
    end
  end

  -- If no exact match can be found, try a loose match (e.g. "en-US" with "en", "fr" with "fr-FR")
  for _, tuple in pairs(preferences_tuples) do
    local client_preference = tuple[1]
    for _, supported_language in pairs(supported_languages) do
      if client_preference:find(supported_language) or supported_language:find(client_preference) then
        return supported_language
      end
    end
  end

  -- If no loose match can be found, return nil
  return nil
end



------------------------------
-- MAIN
------------------------------

-- Get client preferences from query parameter, cookie value, and Accept-Language header values
-- All of these should be formatted using the Accept-Language header syntax, e.g. "en-US,en;q=0.8,fr-FR;q=0.5,fr;q=0.3"
local query_parameter = ngx.var["arg_"..query_parameter_and_cookie_name]
local cookie_value = ngx.var["cookie_"..query_parameter_and_cookie_name]
local accept_language_header = ngx.var.http_accept_language:split(":")[1] -- "Accept-Language:" stripped off

-- Handle sources in order of priority: query parameter, cookie value, Accept-Language header
-- If a match is found, return immediately
-- Otherwise try the next source
if query_parameter ~= nil then
  local match = query_parameter:match_with_supported()
  if match ~= nil then
    return match
  end

elseif cookie_value ~= nil then
  local match = cookie_value:match_with_supported()
  if match ~= nil then
    return match
  end

elseif accept_language_header ~= nil then
  local match = accept_language_header:match_with_supported()
  if match ~= nil then
    return match
  end
end

-- If no match is found, default to first supported language
return supported_languages[1]
