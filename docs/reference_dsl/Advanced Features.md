
## BATCH 6: Advanced Features

### 6.1 Sharing Operations

Sharing enables apps to reuse logic, UI components, and actions from other apps. Shared resources are namespaced to prevent conflicts and support versioning for stability.

#### Share Action

**Description:**



**DSL:**
```nortrix
// Basic share 
share appY buttonCode

// Share with parameters
share appY primaryButton:
    text: "Submit"
    theme: "dark"

// Share with version
share appY checkout v2

// Store result from shared code
result = share appY calculateDiscount:
    subtotal: $total
    userTier: "premium"
```

**JSON:**
```json
{"share": "buttonCode", "app": "appY"}
```

```json
{
  "share": "primaryButton",
  "app": "appY",
  "params": {
    "text": "Submit",
    "theme": "dark"
  }
}
```

```json
{"share": "checkout", "app": "appY", "version": "v2"}
```

```json
{
  "var": "result",
  "value": {
    "share": "calculateDiscount",
    "app": "appY",
    "params": {
      "subtotal": {"var": "total"},
      "userTier": "premium"
    }
  }
}
```

**Parser behavior:**
- `"share"` specifies the code block name to execute
- `"app"` identifies the source app (namespace)
- `"params"` passes parameters to shared code block
- `"version"` optionally pins to specific version (defaults to latest)
- Shared code executes in isolated context with namespace: `blockName@appY`
- Returns value if shared code has return statement

---

#### Share Action

**DSL:**
```nortrix
// Call shared backend action
call "processPayment@appY":
    amount: $total
    method: "credit_card"

// With version pinning
userData = call "getUserProfile@appY" v2:
    userId: $currentUserId
```

**JSON:**
```json
{
  "call": "processPayment@appY",
  "params": {
    "amount": {"var": "total"},
    "method": "credit_card"
  }
}
```

```json
{
  "var": "userData",
  "value": {
    "call": "getUserProfile@appY",
    "version": "v2",
    "params": {
      "userId": {"var": "currentUserId"}
    }
  }
}
```

**Parser behavior:**
- Uses standard `call` operation with `@appName` suffix
- Format: `"actionName@sourceApp"`
- Backend resolves and executes action from source app
- Supports all standard call features (params, response handling)

---

#### Conditional Sharing

**DSL:**
```nortrix
// Consumer app decides which shared resource to use
if $userTier == "premium":
    share appY premiumCheckout
else:
    share appY basicCheckout

// Provider app returns different content based on consumer
code sharedButton@coreUI:
    if @consumer == "appX":
        create Button #btn backgroundColor:"#2563EB"
    elseif @consumer == "appZ":
        create Button #btn backgroundColor:"#DC2626"
    else:
        create Button #btn backgroundColor:"#6B7280"
    
    set #btn.text = @buttonText
```

**JSON:**
```json
{
  "if": [{"var": "userTier"}, "==", "premium"],
  "ops": [
    {"share": "premiumCheckout", "app": "appY"}
  ]
}
```

**Note:** The `@consumer` parameter is automatically provided by the runtime, identifying the consuming app.

---

#### Share Data Table

**DSL:**
```nortrix
// Access shared data table
products = data "products@appY": getAll

// Query shared table with filter
electronics = data "products@appY": filter category == "Electronics"

// Insert into shared table (if permissions allow)
data "products@appY": insert:
    name: $productName
    price: $price
    category: "Electronics"
```

**JSON:**
```json
{"var": "products", "value": {"data": "products@appY", "action": "getAll"}}
```

```json
{
  "var": "electronics",
  "value": {
    "data": "products@appY",
    "action": "filter",
    "where": [{"col": "category"}, "==", "Electronics"]
  }
}
```

```json
{
  "data": "products@appY",
  "action": "insert",
  "row": {
    "name": {"var": "productName"},
    "price": {"var": "price"},
    "category": "Electronics"
  }
}
```

**Parser behavior:**
- Data table name format: `"tableName@sourceApp"`
- All standard data operations supported (getAll, filter, insert, update, delete)
- Access control enforced by source app's sharing configuration

---

#### Sharing Metadata

**DSL:**
```nortrix
// Check if resource is available
available = ShareAvailable "checkout" from:"appY"

if $available:
    share appY checkout
else:
    run localCheckout

// Get sharing info
info = ShareInfo "checkout" from:"appY"
Log $info.version
Log $info.license
```

**JSON:**
```json
{
  "var": "available",
  "value": {"shareAvailable": "checkout", "app": "appY"}
}
```

```json
{
  "var": "info",
  "value": {"shareInfo": "checkout", "app": "appY"}
}
```

**Returns (ShareInfo):**
```javascript
{
  version: "v2.1",
  license: "free",
  description: "Complete checkout flow",
  author: "appY",
  lastUpdated: 1735044690
}
```

---

### 6.2 Internationalization (i18n)

Internationalization enables apps to support multiple languages and locales with dynamic translation and locale-aware formatting.

#### Translate Text

**DSL:**
```nortrix
// Basic translation
greeting = t "welcome.message"

// Translation with variables
message = t "user.greeting" name:$userName

// Translation with pluralization
itemCount = t "cart.items" count:$itemCount

// Translation with fallback
title = t "page.title" fallback:"Default Title"
```

**JSON:**
```json
{"var": "greeting", "value": {"t": "welcome.message"}}
```

```json
{
  "var": "message",
  "value": {
    "t": "user.greeting",
    "vars": {
      "name": {"var": "userName"}
    }
  }
}
```

```json
{
  "var": "itemCount",
  "value": {
    "t": "cart.items",
    "vars": {
      "count": {"var": "itemCount"}
    }
  }
}
```

```json
{
  "var": "title",
  "value": {
    "t": "page.title",
    "fallback": "Default Title"
  }
}
```

**Parser behavior:**
- `"t"` specifies translation key (dot notation for nested keys)
- `"vars"` provides variables for interpolation
- `"fallback"` used if translation key not found
- Uses current locale from session or app settings

**Translation file format (JSON):**
```json
{
  "en": {
    "welcome": {
      "message": "Welcome to our app!"
    },
    "user": {
      "greeting": "Hello, {{name}}!"
    },
    "cart": {
      "items": {
        "zero": "No items",
        "one": "{{count}} item",
        "other": "{{count}} items"
      }
    }
  },
  "pt": {
    "welcome": {
      "message": "Bem-vindo ao nosso aplicativo!"
    },
    "user": {
      "greeting": "Olá, {{name}}!"
    },
    "cart": {
      "items": {
        "zero": "Nenhum item",
        "one": "{{count}} item",
        "other": "{{count}} itens"
      }
    }
  }
}
```

---

#### Set Locale

**DSL:**
```nortrix
// Set current locale
SetLocale "pt-BR"

// Set from user preference
SetLocale $user.language

// Set with fallback chain
SetLocale "pt-BR" fallback:["pt", "en"]
```

**JSON:**
```json
{"setLocale": "pt-BR"}
```

```json
{"setLocale": {"var": ["user", "language"]}}
```

```json
{
  "setLocale": "pt-BR",
  "fallback": ["pt", "en"]
}
```

**Parser behavior:**
- Changes active locale for all subsequent translations
- Stores in session for persistence
- Fallback chain used if specific locale not available

---

#### Get Locale

**DSL:**
```nortrix
// Get current locale
currentLang = GetLocale

Log "Current language: " + $currentLang
```

**JSON:**
```json
{"var": "currentLang", "value": {"getLocale": true}}
```

**Returns:** Current locale code (e.g., `"en"`, `"pt-BR"`, `"es"`)

---

#### Format Number

**DSL:**
```nortrix
// Format as currency
price = FormatNumber($amount, type:"currency", currency:"USD")

// Format as percentage
discount = FormatNumber($rate, type:"percent")

// Format with locale-specific separators
population = FormatNumber($count, type:"decimal")
```

**JSON:**
```json
{
  "var": "price",
  "value": {
    "formatNumber": {"var": "amount"},
    "type": "currency",
    "currency": "USD"
  }
}
```

```json
{
  "var": "discount",
  "value": {
    "formatNumber": {"var": "rate"},
    "type": "percent"
  }
}
```

```json
{
  "var": "population",
  "value": {
    "formatNumber": {"var": "count"},
    "type": "decimal"
  }
}
```

**Parser behavior:**
- Uses current locale for formatting
- `"type"` options: `"currency"`, `"percent"`, `"decimal"`
- `"currency"` required when type is `"currency"` (e.g., `"USD"`, `"EUR"`, `"BRL"`)

**Examples:**
```javascript
// Locale: en-US
FormatNumber(1234.56, "currency", "USD") → "$1,234.56"
FormatNumber(0.15, "percent") → "15%"
FormatNumber(1000000, "decimal") → "1,000,000"

// Locale: pt-BR
FormatNumber(1234.56, "currency", "BRL") → "R$ 1.234,56"
FormatNumber(0.15, "percent") → "15%"
FormatNumber(1000000, "decimal") → "1.000.000"
```

---

#### Format Date (Localized)

**DSL:**
```nortrix
// Format with locale-specific pattern
formattedDate = FormatDate($timestamp, type:"long")

// Short date format
shortDate = FormatDate($timestamp, type:"short")

// Custom format with locale awareness
customDate = FormatDate($timestamp, format:"MMMM d, yyyy")
```

**JSON:**
```json
{
  "var": "formattedDate",
  "value": {
    "formatDate": {"var": "timestamp"},
    "type": "long"
  }
}
```

```json
{
  "var": "shortDate",
  "value": {
    "formatDate": {"var": "timestamp"},
    "type": "short"
  }
}
```

```json
{
  "var": "customDate",
  "value": {
    "formatDate": {"var": "timestamp"},
    "format": "MMMM d, yyyy"
  }
}
```

**Parser behavior:**
- Uses current locale for formatting
- `"type"` options: `"short"`, `"medium"`, `"long"`, `"full"`
- `"format"` allows custom patterns with locale-aware month/day names

**Examples:**
```javascript
// Locale: en-US
FormatDate(1735044690, "long") → "December 24, 2024"
FormatDate(1735044690, "short") → "12/24/24"

// Locale: pt-BR
FormatDate(1735044690, "long") → "24 de dezembro de 2024"
FormatDate(1735044690, "short") → "24/12/24"
```

---

#### Pluralization

**DSL:**
```nortrix
// Automatic pluralization based on count
message = Plural $count:
    zero: "No items"
    one: "One item"
    other: "{{count}} items"

// With translation key
cartMessage = t "cart.items" count:$itemCount
```

**JSON:**
```json
{
  "var": "message",
  "value": {
    "plural": {"var": "count"},
    "zero": "No items",
    "one": "One item",
    "other": ["{{count}}", " items"]
  }
}
```

**Parser behavior:**
- Selects appropriate form based on count value
- Forms: `"zero"` (0), `"one"` (1), `"other"` (2+)
- Some locales have additional forms (e.g., `"few"`, `"many"`)
- Variables in strings replaced with actual values

---

#### Available Locales

**DSL:**
```nortrix
// Get list of supported locales
locales = GetAvailableLocales

// Display locale selector
for locale in $locales:
    create Button #localeBtn in #langSelector:
        text: @locale.name
        onClick: SetLocale @locale.code
```

**JSON:**
```json
{"var": "locales", "value": {"getAvailableLocales": true}}
```

**Returns:** Array of locale objects
```javascript
[
  {code: "en", name: "English", nativeName: "English"},
  {code: "pt-BR", name: "Portuguese (Brazil)", nativeName: "Português (Brasil)"},
  {code: "es", name: "Spanish", nativeName: "Español"}
]
```

---

#### Load Translation File

**DSL:**
```nortrix
// Load translations from file
LoadTranslations "/i18n/translations.json"

// Load from URL
LoadTranslations url:"https://cdn.example.com/i18n/app-translations.json"

// Load specific locale
LoadTranslations "/i18n/pt-BR.json" locale:"pt-BR"
```

**JSON:**
```json
{"loadTranslations": "/i18n/translations.json"}
```

```json
{"loadTranslations": {"url": "https://cdn.example.com/i18n/app-translations.json"}}
```

```json
{
  "loadTranslations": "/i18n/pt-BR.json",
  "locale": "pt-BR"
}
```

**Parser behavior:**
- Loads translation data into memory
- Merges with existing translations
- Can be called multiple times to load additional locales
- Supports both local files and remote URLs

---

### Complete i18n Example

**Frontend with language selector:**
```nortrix
code initApp:
    // Load translations
    LoadTranslations "/i18n/translations.json"
    
    // Get current locale or default to English
    currentLang = GetLocale
    if $currentLang == null:
        SetLocale "en"
    
    // Create language selector
    create Div #langSelector in #header
    
    locales = GetAvailableLocales
    for locale in $locales:
        create Button #langBtn in #langSelector:
            text: @locale.nativeName
            onClick: changeLanguage
            data-locale: @locale.code
    
    // Render content
    run renderContent

code changeLanguage:
    locale = #langBtn.data-locale
    SetLocale $locale
    run renderContent

code renderContent:
    clear #content
    
    // Translated UI elements
    title = t "app.title"
    welcome = t "welcome.message" name:$userName
    
    create Text #title in #content text:$title fontSize:24px
    create Text #welcome in #content text:$welcome
    
    // Format numbers with locale
    price = FormatNumber($productPrice, type:"currency", currency:"USD")
    create Text #price in #content text:$price
    
    // Pluralized message
    itemCount = t "cart.items" count:$cartItemCount
    create Text #cartInfo in #content text:$itemCount

run initApp
```
