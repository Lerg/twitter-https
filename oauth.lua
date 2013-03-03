local _M = {}
 
local crypto = require('crypto')
local mime = require('mime')

-- Replaces unsafe URL characters with %hh (two hex characters)
local function encode_parameter(str)
    return str:gsub('[^-%._~a-zA-Z0-9]',function(c)
        return string.format('%%%02x',c:byte()):upper()
    end)
end

local function sha1(str,key,binary)
    binary = binary or false
    return crypto.hmac(crypto.sha1,str,key,binary)
end

local function get_nonce()
    return mime.b64(crypto.hmac(crypto.sha1,tostring(math.random()) .. 'random'
        .. tostring(os.time()),'keyyyy'))
end

local function get_timestamp()
    return tostring(os.time() + 1)
end

local function oAuthSign(url, method, args, consumer_secret)
    local token_secret = args.oauth_token_secret or ''
    args.oauth_token_secret = nil
    local keys_and_values = {}

    for key, val in pairs(args) do
        table.insert(keys_and_values, {
            key = encode_parameter(key),
            val = encode_parameter(val) })
    end
 
    table.sort(keys_and_values, function(a,b)
        if a.key < b.key then
            return true
        elseif a.key > b.key then
            return false
        else
            return a.val < b.val
        end
    end)
    
    local key_value_pairs = {}
 
    for _, rec in pairs(keys_and_values) do
        table.insert(key_value_pairs, rec.key .. '=' .. rec.val)
    end
    
    local query_string_except_signature = table.concat(key_value_pairs, '&')

    local sign_base_string = method .. '&' .. encode_parameter(url) .. '&'
        .. encode_parameter(query_string_except_signature)

    local key = encode_parameter(consumer_secret) .. '&' .. encode_parameter(token_secret)
    local hmac_binary = sha1(sign_base_string, key, true)

    local hmac_b64 = mime.b64(hmac_binary)
    local query_string = query_string_except_signature .. '&oauth_signature=' .. encode_parameter(hmac_b64)
 
    if method == 'GET' then
        return url .. '?' .. query_string
    else
        return query_string
    end
end

function _M.getRequestToken(consumer_key, token_ready_url, request_token_url, consumer_secret, callback)
    local post_data = {
        oauth_consumer_key     = consumer_key,
        oauth_timestamp        = get_timestamp(),
        oauth_version          = '1.0',
        oauth_nonce            = get_nonce(),
        oauth_callback         = token_ready_url,
        oauth_signature_method = 'HMAC-SHA1'}
    
    local post_data = oAuthSign(request_token_url, 'POST', post_data, consumer_secret)
    _M.rawPostRequest(request_token_url, post_data, function (event)
            if not event.isError then
                local response = event.response
                callback{isError = false, token = response:match('oauth_token=([^&]+)'), token_secret = response:match('oauth_token_secret=([^&]+)')}
            else
                callback{isError = true}
            end
        end)
end

function _M.getAccessToken(token, verifier, token_secret, consumer_key, consumer_secret, access_token_url, callback)
    local post_data = {
        oauth_consumer_key = consumer_key,
        oauth_timestamp    = get_timestamp(),
        oauth_version      = '1.0',
        oauth_nonce        = get_nonce(),
        oauth_token        = token,
        oauth_token_secret = token_secret,
        oauth_verifier     = verifier,
        oauth_signature_method = 'HMAC-SHA1'}
    local post_data = oAuthSign(access_token_url, 'POST', post_data, consumer_secret)
    _M.rawPostRequest(access_token_url, post_data, function (event)
            if not event.isError then
                callback{isError = false, response = event.response}
            else
                callback{isError = true}
            end
        end)
end

function _M.makeRequest(url, body, consumer_key, token, consumer_secret, token_secret, method, callback)
    local post_data = {
        oauth_consumer_key = consumer_key,
        oauth_nonce        = get_nonce(),
        oauth_signature_method = 'HMAC-SHA1',
        oauth_token        = token,
        oauth_timestamp    = get_timestamp(),
        oauth_version      = '1.0',
        oauth_token_secret = token_secret}
    for i=1, #body do
        post_data[body[i].key] = body[i].value
    end
    local post_data = oAuthSign(url, method, post_data, consumer_secret)
    if method == 'POST' then
        _M.rawPostRequest(url, post_data, callback)
    else
        _M.rawGetRequest(post_data, callback)
    end
end

function _M.rawGetRequest(url, callback)
    network.request(url, 'GET', callback)
end

function _M.rawPostRequest(url, rawdata, callback)
    network.request(url, 'POST', callback, {
        headers = {
            ['Content-Type'] = 'application/x-www-form-urlencoded', 
            ['Content-Length'] = string.len(rawdata)},
        body = rawdata})
end

return _M