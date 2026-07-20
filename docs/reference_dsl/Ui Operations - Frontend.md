## BATCH 3: UI Operations (Frontend)

### 3.1 Element Creation

#### Create Element (Block Format)

**DSL (static ID — shorthand `#`):**
```nortrix
create Div #myDiv in #container:
    width: 100%
    display: flex
    flexDirection: column
    padding: 20px
```

**DSL (dynamic ID — `id:expression`):**
```nortrix
// Variable as ID
create Div id:$panelName in #container:
    padding: 20px

// Concatenation as ID
create Div id:"panel-" + $userId in #container:
    padding: 20px

// Dynamic IDs in loops
for item in $items:
    create Div id:"item-" + @item.id in #list:
        text: @item.name
        padding: 10px
```

**JSON:**
```json
{
  "create": "div",
  "id": "myDiv",
  "target": "container",
  "width": "100%",
  "display": "flex",
  "flexDirection": "column",
  "padding": "20px"
}
```

```json
{
  "create": "div",
  "id": {"var": "panelName"},
  "target": "container",
  "padding": "20px"
}
```

```json
{
  "create": "div",
  "id": ["panel-", "+", {"var": "userId"}],
  "target": "container",
  "padding": "20px"
}
```

**Parser behavior:**
- `"create"` specifies element type (lowercase)
- `"id"` is the element identifier — can be string literal, variable reference, or expression
- `#staticId` shorthand compiles to `"id": "staticId"` (string literal)
- `id:$var` compiles to `"id": {"var": "name"}` (resolved at runtime)
- `id:"prefix-" + $var` compiles to `"id": ["prefix-", "+", {"var": "name"}]` (expression)
- `"target"` is the parent element ID (without `#`)
- All other properties are element attributes/styles
- Uses standard HTML `id` attribute — `document.getElementById()` for lookups

---

#### Create Element (Inline Format)

**DSL:**
```nortrix
create Button #submitBtn in #form text:"Submit" width:200px onClick:handleSubmit
create Input #emailInput in #form type:email placeholder:"Enter email"
```

**JSON:**
```json
{"create": "button", "id": "submitBtn", "target": "form", "text": "Submit", "width": "200px", "onClick": "handleSubmit"}
{"create": "input", "id": "emailInput", "target": "form", "type": "email", "placeholder": "Enter email"}
```

---

#### Supported Element Types

| DSL Type | HTML Element | Common Attributes |
|----------|--------------|-------------------|
| `Div` | `<div>` | width, height, padding, margin |
| `Text` | `<span>` | text, fontSize, color |
| `Button` | `<button>` | text, onClick, disabled |
| `Input` | `<input>` | type, value, placeholder, onChange |
| `Textarea` | `<textarea>` | value, placeholder, rows, cols, onChange |
| `Image` | `<img>` | src, alt, width, height |
| `Select` | `<select>` | options, value, onChange |
| `Row` | `<div>` | display:flex, flexDirection:row |
| `Column` | `<div>` | display:flex, flexDirection:column |

---

### 3.2 Element Properties

#### Set Element Property

**DSL:**
```nortrix
set #myDiv.text = "Hello World"
set #myDiv.visible = false
set #error.text = $errorMessage
set #input.value = ""
```

**JSON:**
```json
{"set": "text", "target": "myDiv", "value": "Hello World"}
{"set": "visible", "target": "myDiv", "value": false}
{"set": "text", "target": "error", "value": {"var": "errorMessage"}}
{"set": "value", "target": "input", "value": ""}
```

**Parser behavior:**
- `"set"` specifies the property/attribute name
- `"target"` is the element ID (without `#`)
- `"value"` can be literal or expression

---

#### Get Element Property

**DSL:**
```nortrix
email = #emailInput.value
isChecked = #rememberMe.checked
buttonText = #submitBtn.text
```

**JSON:**
```json
{"var": "email", "value": {"get": "value", "target": "emailInput"}}
{"var": "isChecked", "value": {"get": "checked", "target": "rememberMe"}}
{"var": "buttonText", "value": {"get": "text", "target": "submitBtn"}}
```

**Parser behavior:**
- `"get"` specifies the property/attribute to retrieve
- `"target"` is the element ID (without `#`)
- Returns the current value of the property

---

### 3.3 Element Manipulation

#### Clear Element Contents

**DSL:**
```nortrix
// Clear the root container
clear

// Clear a specific element
clear #myContainer
```

**JSON:**
```json
{"clear": true}
{"clear": "myContainer"}
```

**Parser behavior:**
- `{"clear": true}` clears the root container
- `{"clear": "elementId"}` clears specific element
- Removes all child elements from container

---

#### Remove Element

**DSL:**
```nortrix
remove #oldElement
remove #tempMessage
```

**JSON:**
```json
{"remove": "oldElement"}
{"remove": "tempMessage"}
```

**Parser behavior:**
- Completely removes element from DOM (first match by `getElementById`)
- Element ID becomes available for reuse

**Duplicate IDs:**
- **DOM elements:** Duplicate IDs are allowed. `getElementById` returns the **first match**. Dynamic lists should use unique IDs via expressions (e.g., `id:"item-" + @item.id`).
- **Abstract objects** (code blocks, data tables): Duplicate IDs **overwrite** — latest definition wins.

---

### 3.4 Event Handlers

#### Click Event

**DSL:**
```nortrix
on #loginBtn.click:
    run handleLogin

on #closeBtn.click:
    run closeModal
```

**JSON:**
```json
{
  "create": "button",
  "id": "loginBtn",
  "onClick": "handleLogin"
}
```

```json
{
  "create": "button",
  "id": "closeBtn",
  "onClick": "closeModal"
}
```

**Parser behavior:**
- `"onClick"` contains the name of a code block to execute
- Event handlers are defined during element creation
- The code block can contain any operations (call, run, create, etc.)

**Multiple code blocks:**
```json
{
  "create": "button",
  "id": "submitBtn",
  "onClick": ["validateForm", "submitData"]
}
```

**Note:** Events only run code blocks. To call backend actions, define a code block that contains the `call` operation.

---

#### Change Event

**DSL:**
```nortrix
on #searchInput.change:
    run handleSearch
```

**JSON:**
```json
{
  "create": "input",
  "id": "searchInput",
  "onChange": "handleSearch"
}
```

**With multiple code blocks:**
```json
{
  "create": "input",
  "id": "searchInput",
  "onChange": ["logChange", "handleSearch"]
}
```

**Parser behavior:**
- `"onChange"` can be a string (single code block) or array (multiple code blocks)
- Code blocks execute in sequence
- Each code block has access to element values via `get` operation

#### Supported Events

| Event | Trigger | Common Elements |
|-------|---------|----------------|
| `onClick` | Element clicked | Button, Div, Text, Image |
| `onChange` | Value changed | Input, Textarea, Select |
| `onFocus` | Element focused | Input, Textarea |
| `onBlur` | Element loses focus | Input, Textarea |
| `onKeyPress` | Key pressed | Input, Textarea |
| `onMouseEnter` | Mouse enters element | Any |
| `onMouseLeave` | Mouse leaves element | Any |
| `onTouchStart` | Touch begins | Any |
| `onTouchEnd` | Touch ends | Any |
| `onTouchMove` | Touch moves | Any |
| `onSwipeLeft` | Swipe left gesture | Any |
| `onSwipeRight` | Swipe right gesture | Any |
| `onSwipeUp` | Swipe up gesture | Any |
| `onSwipeDown` | Swipe down gesture | Any |
| `onLongPress` | Touch held > 500ms | Any |

**Note:** Swipe and long-press events are convenience gestures calculated by the runtime from touch deltas/duration.

**Example - Multiple events on one element:**
```json
{
  "create": "input",
  "id": "emailInput",
  "onChange": "validateEmail",
  "onFocus": "clearError",
  "onBlur": "checkRequired"
}
```

---

### 3.5 Layout & Utility Operations

#### ScrollTo

**DSL:**
```nortrix
// Basic scroll to element
ScrollTo #sectionProblem

// With offset (for fixed headers)
ScrollTo #sectionContact -60

// Instant scroll (no animation)
ScrollTo #sectionHow -80 instant
```

**JSON:**
```json
{"scrollto": "sectionProblem"}
{"scrollto": "sectionContact", "offset": -60}
{"scrollto": "sectionHow", "offset": -80, "behavior": "instant"}
```

**Parser behavior:**
- Smoothly scrolls element into view
- `"offset"` adjusts final position (negative for fixed headers)
- `"behavior"` can be `"smooth"` (default) or `"instant"`

---

#### LoadFont

**DSL:**
```nortrix
// Google Fonts (auto-builds URL)
LoadFont "Noto Sans"
LoadFont "Roboto" weights:[400, 500, 700]

// Custom font URL
LoadFont family:"CustomFont" url:"/assets/fonts/custom.woff2"
```

**JSON:**
```json
{"loadfont": "Noto Sans"}
{"loadfont": "Roboto", "weights": [400, 500, 700]}
{"loadfont": {"family": "CustomFont", "url": "/assets/fonts/custom.woff2"}}
```

**Parser behavior:**
- Loads web fonts dynamically
- Google Fonts: provide family name, optionally weights array
- Custom fonts: provide family name and URL
- Default fonts (Noto Sans, Noto Serif, Noto Sans Mono) auto-loaded on init

---

### 3.6 Date & Time Operations (Frontend)

#### Date - Get Current Date/Time

**DSL:**
```nortrix
// Get full date object
now = Date

// Access properties
Log $now.year           // 2024
Log $now.month          // 12 (1-12)
Log $now.day            // 24
Log $now.hour           // 9
Log $now.minute         // 51
Log $now.second         // 30
Log $now.epoch          // 1735044690 (Unix timestamp, seconds)
Log $now.ms             // 1735044690123 (milliseconds)
Log $now.weekday        // 2 (0=Sunday, 6=Saturday)
Log $now.weekdayName    // "Tuesday"
Log $now.monthName      // "December"
Log $now.timezone       // "America/Sao_Paulo"
Log $now.offset         // -180 (minutes from UTC)
Log $now.iso            // "2024-12-24T09:51:30-03:00"

// Get formatted date string
today = Date "Y-m-d"    // "2024-12-24"
time = Date "H:i:s"     // "09:51:30"
```

**JSON:**
```json
{"var": "now", "value": {"date": true}}
{"var": "today", "value": {"date": "Y-m-d"}}
{"var": "time", "value": {"date": "H:i:s"}}
```

**Parser behavior:**
- `{"date": true}` returns full object with all properties
- `{"date": "format"}` returns formatted string
- Uses browser's local timezone
- Defaults to current date/time ("now")

---

#### Date with Epoch Source

**DSL:**
```nortrix
// Use stored timestamp
eventDate = Date epoch:$event.created_at
formattedEvent = Date "Y-m-d H:i" epoch:$event.created_at
```

**JSON:**
```json
{"var": "eventDate", "value": {"date": true, "epoch": {"var": "event.created_at"}}}
{"var": "formattedEvent", "value": {"date": "Y-m-d H:i", "epoch": {"var": "event.created_at"}}}
```

**Parser behavior:**
- `"epoch"` specifies source timestamp
- If omitted, defaults to "now"
- Can use `"now"` explicitly: `{"date": true, "epoch": "now"}`

---

#### Date Modification

**DSL:**
```nortrix
// Add days
nextWeek = Date "Y-m-d" "+7 days"

// Add multiple units
meeting = Date "+3 days +2 hours"

// Subtract time
lastMonth = Date "Y-m-d" "-1 month"

// Modify from specific date
futureEvent = Date "Y-m-d" epoch:$baseDate "+30 days"

// Complex example
deadline = Date "Y-m-d H:i" "+1 month +15 days -3 hours"
```

**JSON:**
```json
{"var": "nextWeek", "value": {"date": "Y-m-d", "modify": ["day", "+", 7]}}
{"var": "meeting", "value": {"date": true, "modify": ["day", "+", 3, "hour", "+", 2]}}
{"var": "lastMonth", "value": {"date": "Y-m-d", "modify": ["month", "-", 1]}}
{"var": "futureEvent", "value": {"date": "Y-m-d", "epoch": {"var": "baseDate"}, "modify": ["day", "+", 30]}}
{"var": "deadline", "value": {"date": "Y-m-d H:i", "modify": ["month", "+", 1, "day", "+", 15, "hour", "-", 3]}}
```

**Supported modification units:**
- `year` / `years` — Add/subtract years
- `month` / `months` — Add/subtract months
- `day` / `days` — Add/subtract days
- `hour` / `hours` — Add/subtract hours
- `minute` / `minutes` — Add/subtract minutes
- `second` / `seconds` — Add/subtract seconds

**DSL Syntax:**
- Modifiers are a quoted string: `"+7 days"` or `"+3 days +2 hours"`
- Format: `+/-` followed by number and unit
- Multiple modifications: space-separated within the string
- Singular or plural units accepted (e.g., `day` or `days`)
- Order: format string (optional), `epoch:` (optional), modifier string (optional)

**Parser behavior:**
- DSL compiler parses modifier string `"+7 days"` to `["day", "+", 7]` in JSON
- `"modify"` is array: `[unit, operator, value, unit, operator, value, ...]`
- Modifications applied in sequence
- Works with both formatted output and full object

---

#### Date Format Strings

**Common format patterns:**

| Pattern | Description | Example |
|---------|-------------|---------|
| `Y` | 4-digit year | 2024 |
| `m` | 2-digit month | 12 |
| `d` | 2-digit day | 24 |
| `H` | 24-hour format (00-23) | 09 |
| `i` | Minutes (00-59) | 51 |
| `s` | Seconds (00-59) | 30 |
| `Y-m-d` | ISO date | 2024-12-24 |
| `Y-m-d H:i:s` | ISO datetime | 2024-12-24 09:51:30 |
| `d/m/Y` | European format | 24/12/2024 |
| `m/d/Y` | US format | 12/24/2024 |

**Examples:**
```json
{"date": "Y-m-d"}           // "2024-12-24"
{"date": "Y-m-d H:i:s"}     // "2024-12-24 09:51:30"
{"date": "d/m/Y"}           // "24/12/2024"
{"date": "H:i"}             // "09:51"
```
