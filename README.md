# NGINX Static Language Selector

Lua script for NGINX Lua module (`ngx_http_lua_module`), making NGINX aware of client language preferences retrieved from multiple sources (query parameter, cookie value, `Accept-Language` HTTP header), according to a list of supported IETF BCP 47 language tags for a specific website.

## Intent

- Serving localized static content directly from NGINX.
- Handle client preferences for all of the following cases:
  - New client sessions.
  - Recurring client sessions.
  - Clients explicitly asking for a specific language.
- Loose matching of regional language codes with regular language codes (or vice versa) when there is no exact match.

## Use case

Any type of static multilingual website where NGINX would be able to serve/redirect/rewrite clients to the right localized subdirectory or file if client language preferences were known.

Examples of static multilingual websites structures:
```
subdirectories_example
├── shared
|   └── style.css
├── en
|   └── index.html
└── fr
    └── index.html

filenames_example
├── style.css
├── index.html.en
└── index.html.fr
```

Handling examples of a client accessing `example.com` with `fr` as language preference:
- Transparently serve localized `index.html.fr` without redirect nor rewrite
- Redirect or rewrite to `example.com/fr`
- Redirect or rewrite to `example.com/?lang=fr`
- Redirect or rewrite to `fr.example.com`

## Language preferences matching from multiple sources

### Algorithm

- Initial state: a list of supported languages consisting of IETF BCP 47 language tags (2-3 letter-long tags separated by `-`, e.g. `en`, `en-US`, `fr`, `fr-FR`) is provided.

- We check for client language preferences from the following sources, in order:
  - Query parameter
  - Cookie value
  - `Accept-Language` HTTP header

  All these sources are expected to be formatted according to the [`Accept-Language` header format](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Accept-Language), e.g. `en-US,en;q=0.8,fr-FR;q=0.5,fr;q=0.3`, and thus also consist of IETF BCP 47 language tags.

- For each source
  - Each language tag in source is compared with the list of supported languages. If an exact match is found, return it.

  - If no exact match can be found, each language tag in source is again compared with the list of supported languages. If a loose match between regional language codes and regular language codes is found, e.g. `en-US` with `en`, `fr` with `fr-FR`, return it.

  - If no loose match can be found, the script processes the next source.

- If no match has been found after all sources have been processed, the script defaults to the first supported language specified in the list.

Sample results:

| Query parameter | Cookie value | `Accept-Language`  header | Supported  | Result  |
|-----------------|--------------|---------------------------|------------|---------|
|                 |              | `en-US,fr`                | `en,fr`    | `fr`    |
|                 | `en-US`      | `en-US,fr`                | `en,fr`    | `en`    |
| `fr-FR`         | `en-US`      | `en-US,fr`                | `en,fr`    | `fr`    |
|                 |              | `en`                      | `en-US,fr` | `en-US` |
|                 | `fr-FR`      | `en`                      | `en-US,fr` | `fr`    |
| `en`            | `fr-FR`      | `en`                      | `en-US,fr` | `en-US` |
|                 |              | `de-DE`                   | `en,fr`    | `en`    |
|                 | `fr-FR`      | `de-DE`                   | `en,fr`    | `fr`    |

### Analysis

We assume that the static localized website has `{switch language}` buttons that users may click to manually switch language.

- Query parameter: very easy to use from client-side for switching language, e.g. in `a.href` of `{switch language}` buttons. It is explicit and instantaneous: if a client asks for a page with `?lang=fr`, the server is immediately 100% aware of client preferences. However, it is not suitable for remembering client preferences between sessions, as it is not persistent (unless the client bookmarks it).

- Cookie value: easy to store from client-side, e.g. in an `onclick` handler for `{switch language}` buttons. It is suitable for remembering client preferences between sessions. However, cookie storage is handled by the browser and the we have no direct control over it. It is neither instantaneous nor trustable: there can be a delay between `onclick` handler asking for a cookie to be stored and actual cookie storage, and maybe no cookie will actually be stored. Thus, it is not suitable on its own for switching language: if a user clicks a `{switch language}` button, redirection may occur before the cookie value is actually set, in which case the server will not be aware of client preferences.

- `Accept-Language` HTTP header: in the specific case of static websites without dynamic localization, it is not suitable for switching language from client-side without an HTTP redirection. It is not suitable for remembering client preferences between sessions since we have no control over it.

### Priority

Given [Analysis](#analysis) and [Intent](#intent):
- New client sessions should rely on `Accept-Language` HTTP header, as it is the only source available.
- Recurring client sessions should rely on cookie value, as it is the only persistent source we can control.
- Clients explicitly asking for a specific language should rely on query parameter, as it is the only reliable source that can be set from client-side.

Hence why we should always check sources in the following order:
- Query parameter: explicit client preference.
- Cookie value: persistent client preference.
- `Accept-Language` HTTP header: default client preference.

## Installation

- Make sure NGINX Lua module (`ngx_http_lua_module`) is installed and enabled. On Debian/Ubuntu, this can be done by installing `nginx-extras`.
- [Download the latest release](https://github.com/Skymirrh/NGINX-Static-Language-Selector/releases/latest) - or - [download `language_selector.lua` directly from `master`](https://raw.githubusercontent.com/Skymirrh/NGINX-Static-Language-Selector/master/language_selector.lua)
- Put `language_selector.lua` at a `{path}` your NGINX installation will be able to read, e.g. `/etc/nginx/lua/language_selector.lua`.
- Remember this `{path}` for [Usage](#usage).

## Usage

Syntax (within a NGINX `server` block):
```nginx
set_by_lua_file {$lang} {path}/language_selector.lua {$supported};
```
where:
- `path` is the path leading to `language_selector.lua` (see [Installation](#installation)).
- `$supported` is a comma-separated list of languages supported by the website, in IETF BCP 47 format. Example: `en-US,en,fr-FR,fr`
- `$lang` holds a single value from the `$supported` list, selected according to client preferences. This variable can then be used however you see fit, e.g. `index` directive, `location` blocks, rewrite rules.

Example with the `filenames_example` from [Use case](#use-case), transparently serving a localized `index.html` when clients visit `example.com`:
```nginx
server {
  server_name example.com;

  ...

  # Language selector
  set $supported "en,fr";
  set_by_lua_file $lang /etc/nginx/lua/language_selector.lua $supported;

  # Files
  root /var/www/filenames_example;
  location / {
    index index.html.$lang;
  }

  ...
}
```

## Client-side cookie storage

Now that the server is fully aware of client language preferences, the client-side can take advantage of it to:
- Allow users to switch language manually.
- Store client preferences in a persistent manner.

Here are some examples of `{switch language}` buttons that you may implement client-side, so that users may manually switch language and at the same time store their preferences in a cookie.

### JavaScript
```html
<a id="switchLangFr" href="?lang=fr" onClick="switchLang('fr');">French</a>

<script type="text/javascript">
  function switchLang(lang) {
    document.cookie = "lang="+lang;
  }
</script>
```

### jQuery
```html
<a id="switchLangFr" href="?lang=fr">French</a>

<script type="text/javascript">
  $(document).ready(function () {
    $('#switchLangFr').click(function() { document.cookie = "lang=fr"; });
  });
</script>
```

## Server-side cookie storage

Client preferences can also be persisted in a cookie server-side, though I do not recommend this approach.

It is much more elegant and less error-prone to set cookies directly from client-side at the same time a user manually switches language, rather than server-side when the server checks for client preferences and realizes an explicit language has been asked by the client.

### PHP

```php
<?php
if(isset($_GET['lang']))
{
  setcookie('lang', $_GET['lang']);
}
?>

<a id="switchLangFr" href="?lang=fr">French</a>
```

### NGINX

```nginx
server {
  ...
  
  if ($arg_lang) {
    add_header Set-Cookie lang=$arg_lang;
  }

  ...
}
```