## BATCH 2: Control Flow

### 2.1 Conditionals

#### If Statement

**DSL:**
```nortrix
if $status == "active":
    Log "User is active"
```

**JSON:**
```json
{
  "if": [{"var": "status"}, "==", "active"],
  "ops": [
    {"log": "User is active"}
  ]
}
```

**Parser behavior:**
- `"if"` contains flat condition array: `[operand, operator, operand, ...]`
- Operators are strings: `"=="`, `"!="`, `">="`, `"AND"`, `"OR"`, etc.
- `"ops"` contains operations to execute when condition is true

---

#### If with ElseIf and Else

**DSL:**
```nortrix
if $status == "active":
    Log "User is active"
elseif $status == "pending":
    Log "User is pending"
else:
    Log "User is inactive"
```

**JSON:**
```json
{"if": [{"var": "status"}, "==", "active"], "ops": [{"log": "User is active"}]},
{"elseif": [{"var": "status"}, "==", "pending"], "ops": [{"log": "User is pending"}]},
{"else": [{"log": "User is inactive"}]}
```

**Note:** 
- `if`, `elseif`, and `else` are **separate sequential operations**
- Allows multiple `elseif` statements
- `else` contains only the ops array (no condition)
- Parser executes first matching condition and skips remaining

---

#### Inline If (Single Operation)

**DSL:**
```nortrix
if $count > 0: Log "Has items"
```

**JSON:**
```json
{
  "if": [{"var": "count"}, ">", 0],
  "ops": [{"log": "Has items"}]
}
```

---

#### Complex Conditions

**DSL:**
```nortrix
if $age >= 18 AND $status == "verified":
    Log "Access granted"

if ($role == "admin" OR $role == "mod") AND $active == true:
    Log "Moderator access"
```

**JSON:**
```json
{
  "if": [[{"var": "age"}, ">=", 18], "AND", [{"var": "status"}, "==", "verified"]],
  "ops": [
    {"log": "Access granted"}
  ]
}
```

```json
{
  "if": [
    [[{"var": "role"}, "==", "admin"], "OR", [{"var": "role"}, "==", "mod"]],
    "AND",
    [{"var": "active"}, "==", true]
  ],
  "ops": [
    {"log": "Moderator access"}
  ]
}
```

**Condition format:**
- **Nested arrays** for complex conditions: `[[cond1], "AND", [cond2]]`
- Each sub-condition is wrapped in array for clarity
- Operators: `"=="`, `"!="`, `">"`, `"<"`, `">="`, `"<="`, `"AND"`, `"OR"`, `"NOT"`
- Parentheses in DSL map directly to nested arrays
- Clear precedence without ambiguity

---

### 2.2 Loops

#### For Loop (Range-Based)

**DSL:**
```nortrix
for i in range(1, 10):
    Log $i

for i in range(0, 5):
    Log "Iteration " + $i

// With step
for i in range(0, 100, 10):
    Log $i
```

**JSON:**
```json
{
  "for": {"index": "i", "from": 1, "to": 10},
  "ops": [
    {"log": {"var": "i"}}
  ]
}
```

```json
{
  "for": {"index": "i", "from": 0, "to": 5},
  "ops": [
    {"log": ["Iteration ", "+", {"var": "i"}]}
  ]
}
```

```json
{
  "for": {"index": "i", "from": 0, "to": 100, "step": 10},
  "ops": [
    {"log": {"var": "i"}}
  ]
}
```

**Parser behavior:**
- `"for"` contains object with `"index"`, `"from"`, `"to"`, optional `"step"`
- `range(from, to)` — inclusive range, step defaults to 1
- `range(from, to, step)` — inclusive range with custom step
- Loop variable is accessible via `{"var": "index_name"}`
- Loop variable (`$i`) is global by default; use `$$i` for local
- **Best for:** Simple sequential iteration, custom increments

---

#### ForEach Loop

**DSL:**
```nortrix
for user in $users:
    Log @user.name
    Log @user.email
```

**JSON:**
```json
{
  "foreach": {"source": {"var": "users"}, "value": "user"},
  "ops": [
    {"log": {"param": ["user", "name"]}},
    {"log": {"param": ["user", "email"]}}
  ]
}
```

**Parser behavior:**
- `"foreach"` contains `"source"` (array/object to iterate) and `"value"` (parameter name)
- Current value accessible via `{"param": "value_name"}`
- Works with arrays and objects

---

#### ForEach with Key

**DSL:**
```nortrix
for user, key in $users:
    Log "User " + $key + ": " + @user.name

for value, key in $settings:
    Log "Setting " + $key + " = " + @value
```

**JSON:**
```json
{
  "foreach": {"source": {"var": "users"}, "value": "user", "key": "key"},
  "ops": [
    {"log": ["User ", "+", {"var": "key"}, "+", ": ", "+", {"param": ["user", "name"]}]}
  ]
}
```

```json
{
  "foreach": {"source": {"var": "settings"}, "value": "value", "key": "key"},
  "ops": [
    {"log": ["Setting ", "+", {"var": "key"}, "+", " = ", "+", {"param": "value"}]}
  ]
}
```

**Note:** 
- `"key"` is accessible as a variable (for arrays: numeric index, for objects: property name)
- `"value"` is accessible as a parameter
- Works seamlessly with both arrays and objects

---

#### While Loop

**DSL:**
```nortrix
while $count < 10:
    Log $count
    count = $count + 1
```

**JSON:**
```json
{
  "while": [{"var": "count"}, "<", 10],
  "ops": [
    {"log": {"var": "count"}},
    {"var": "count", "value": [{"var": "count"}, "+", 1]}
  ]
}
```

**Parser behavior:**
- `"while"` contains flat condition array (same format as `"if"`)
- Loop continues while condition evaluates to true
- **Warning:** Ensure loop has exit condition to prevent infinite loops

---

### 2.3 Code Blocks

#### Define Code Block

**DSL:**
```nortrix
code showLoginForm:
    create Div #loginForm in #root:
        padding: 20px
    create Input #emailInput in #loginForm placeholder:"Email"
    create Button #loginBtn in #loginForm text:"Login"
```

**JSON:**
```json
{
  "code": "showLoginForm",
  "ops": [
    {"create": "div", "id": "loginForm", "target": "root", "padding": "20px"},
    {"create": "input", "id": "emailInput", "target": "loginForm", "placeholder": "Email"},
    {"create": "button", "id": "loginBtn", "target": "loginForm", "text": "Login"}
  ]
}
```

**Parser behavior:**
- `"code"` defines a reusable block of operations
- Block name is stored for later execution
- Operations are not executed during definition

---

#### Code Block with Parameters

**DSL:**
```nortrix
code processUser(id, action="view", debug=false):
    Log "Processing user " + @id + " with action: " + @action
    if @debug: Log "Debug mode enabled"
```

**JSON:**
```json
{
  "code": "processUser",
  "params": {
    "id": {"required": true},
    "action": {"default": "view"},
    "debug": {"default": false}
  },
  "ops": [
    {"log": ["Processing user ", "+", {"param": "id"}, "+", " with action: ", "+", {"param": "action"}]},
    {
      "if": [{"param": "debug"}, "==", true],
      "ops": [{"log": "Debug mode enabled"}]
    }
  ]
}
```

**Parameter rules:**
- Parameters without `=` are **required**: `id`
- Parameters with `=value` are **optional** with a default: `action="view"`
- Required params must come before optional params
- Parameters are always **local** to the code block (accessed via `@paramName`)


---

#### Execute Code Block

**DSL:**
```nortrix
run showLoginForm

run processUser:
    id: $userId
    action: "update"
    debug: true
```

**JSON:**
```json
{"run": "showLoginForm"}
```

```json
{
  "run": "processUser",
  "params": {
    "id": {"var": "userId"},
    "action": "update",
    "debug": true
  }
}
```

**Parser behavior:**
- `"run"` executes a previously defined code block
- `"params"` passes parameters to the code block
- Parameters accessible inside block via `{"param": "name"}`

---

#### Return Statement

**DSL:**
```nortrix
code calculateTotal:
    if $items == []:
        return 0
    
    $$total = 0
    for item in $items:
        $$total += @item.price
    
    return $$total
```

**JSON:**
```json
{
  "code": "calculateTotal",
  "ops": [
    {
      "if": [{"var": "items"}, "==", []],
      "ops": [{"return": 0}]
    },
    {"lvar": "total", "value": 0},
    {
      "foreach": {"source": {"var": "items"}, "value": "item"},
      "ops": [
        {"lvar": "total", "value": [{"lvar": "total"}, "+", {"param": ["item", "price"]}]}
      ]
    },
    {"return": {"lvar": "total"}}
  ]
}
```

**Parser behavior:**
- `"return"` exits the current code block
- Can return a value or be empty
- Execution stops at return statement

---

#### Variable Scoping

**DSL:**
```nortrix
$name = "Global John"          // global — visible everywhere

code doStuff:
    $$temp = "local only"      // local — dies when code block ends
    $name = "Modified Global"  // modifies the global $name
    Log $$temp                 // works
    Log $name                  // works (reads global)

run doStuff
Log $name                      // "Modified Global"
Log $$temp                     // ERROR: undefined (local died)
```

**JSON:**
```json
{"var": "name", "value": "Global John"}
```
```json
{"lvar": "temp", "value": "local only"}
```

**Scoping rules:**
- `$var` → `{"var": "name"}` — **Global.** Accessible from anywhere. Persists after code block ends.
- `$$var` → `{"lvar": "name"}` — **Local.** Only accessible within the current code block. Destroyed when block ends.
- `@param` → `{"param": "name"}` — **Local.** Code block parameters. Always scoped to the code block.
- Loop variables (`$i` in `for i in range(...)`) are global by default. Use `$$i` for local loop counters.
- If `$i` is used in nested code blocks, they **will collide** (this is accepted — use `$$i` to avoid).
