## Core Operations

### 1.1 Variables

#### Set Variable

**DSL:**
```nortrix
x = 10
name = "John Doe"
isActive = true
user = { id: 1, name: "John" }
items = [1, 2, 3]
```

**JSON:**
```json
{"var": "x", "value": 10}
{"var": "name", "value": "John Doe"}
{"var": "isActive", "value": true}
{"var": "user", "value": {"id": 1, "name": "John"}}
{"var": "items", "value": [1, 2, 3]}
```

**Parser behavior:**
- Key `"var"` identifies variable operation
- If `"value"` present: set variable
- If `"value"` absent: get variable (returns value)

---

#### Get Variable

**DSL:**
```nortrix
Log $userName
total = $price * $quantity
```

**JSON (inline reference):**
```json
{"log": {"var": "userName"}}
{"var": "total", "value": {"mul": [{"var": "price"}, {"var": "quantity"}]}}
```

**Note:** Variable references use nested `{"var": "name"}` format when used as values.

---

#### Get Parameter

**DSL:**
```nortrix
Log @email
Log @user.name
```

**JSON:**
```json
{"log": {"param": "email"}}
{"log": {"param": ["user", "name"]}}
```

**Parser behavior:**
- `"param"` with string: single parameter
- `"param"` with array: nested path (dot notation)

---

### 1.2 Math Expressions

#### Basic Math Operations

**DSL:**
```nortrix
sum = 10 + 20
total = $price * $qty
discount = $total * 0.1
final = $total - $discount
division = $total / 2
remainder = $count % 2
```

**JSON:**
```json
{"var": "sum", "value": [10, "+", 20]}
{"var": "total", "value": [{"var": "price"}, "*", {"var": "qty"}]}
{"var": "discount", "value": [{"var": "total"}, "*", 0.1]}
{"var": "final", "value": [{"var": "total"}, "-", {"var": "discount"}]}
{"var": "division", "value": [{"var": "total"}, "/", 2]}
{"var": "remainder", "value": [{"var": "count"}, "%", 2]}
```

**Supported operations:**
- `"+"` — Addition
- `"-"` — Subtraction
- `"*"` — Multiplication
- `"/"` — Division
- `"%"` — Modulo

---

#### Compound Assignment

**DSL:**
```nortrix
count += 1
total -= $discount
price *= 1.1
```

**JSON:**
```json
{"var": "count", "value": [{"var": "count"}, "+", 1]}
{"var": "total", "value": [{"var": "total"}, "-", {"var": "discount"}]}
{"var": "price", "value": [{"var": "price"}, "*", 1.1]}
```

**Note:** Compound assignments compile to full expressions.

---

### 1.3 Comparison & Logic

#### Comparison Operations

**DSL:**
```nortrix
isAdult = $age >= 18
isEqual = $status == "active"
isNotEmpty = $email != ""
isEmpty = $email == ""
```

**JSON:**
```json
{"var": "isAdult", "value": [{"var": "age"}, ">=", 18]}
{"var": "isEqual", "value": [{"var": "status"}, "==", "active"]}
{"var": "isNotEmpty", "value": [{"var": "email"}, "!=", ""]}
{"var": "isEmpty", "value": [{"var": "email"}, "==", ""]}
```

**Supported comparisons:**
- `"=="` — Equal
- `"!="` — Not equal
- `">"` — Greater than
- `"<"` — Less than
- `">="` — Greater than or equal
- `"<="` — Less than or equal

---

#### Logical Operations

**DSL:**
```nortrix
canAccess = $isAdmin OR $isModerator
isValid = $email != "" AND $password != ""
isNotActive = NOT $isActive
```

**JSON:**
```json
{"var": "canAccess", "value": [{"var": "isAdmin"}, "OR", {"var": "isModerator"}]}
{"var": "isValid", "value": [{"var": "email"}, "!=", "", "AND", {"var": "password"}, "!=", ""]}
{"var": "isNotActive", "value": ["NOT", {"var": "isActive"}]}
```

**Supported logic:**
- `"AND"` — Logical AND
- `"OR"` — Logical OR
- `"NOT"` — Logical NOT (prefix operator)

---

### 1.4 String Operations

#### Concatenation

**DSL:**
```nortrix
greeting = "Hello " + $name + "!"
Log "User: " + $userName
```

**JSON:**
```json
{"var": "greeting", "value": ["Hello ", "+", {"var": "name"}, "+", "!"]}
{"log": ["User: ", "+", {"var": "userName"}]}
```

**Note:** String concatenation uses the same `"+"` operator as math addition.

---

#### Replace

**DSL:**
```nortrix
result = replace($text, ".", "-")
cleanName = replace($name, " ", "_")
```

**JSON:**
```json
{"var": "result", "value": {"replace": {"var": "text"}, "search": ".", "with": "-"}}
{"var": "cleanName", "value": {"replace": {"var": "name"}, "search": " ", "with": "_"}}
```

**Note:** `replace()` is a value-returning function. Arguments: `(source, search, replacement)`.

---

#### Validate

**DSL:**
```nortrix
isValidEmail = validate($email, "email")
isValidPhone = validate($phone, "^[0-9]{10}$")
```

**JSON:**
```json
{"var": "isValidEmail", "value": {"validate": {"var": "email"}, "pattern": "email"}}
{"var": "isValidPhone", "value": {"validate": {"var": "phone"}, "pattern": "^[0-9]{10}$"}}
```

**Note:** `validate()` is a value-returning function. Arguments: `(value, pattern)`. Returns boolean.

---

### 1.5 Logging & Debugging

**DSL:**
```nortrix
Log "Hello World"
Log $userName
Log "User: " + $userName + " logged in"
```

**JSON:**
```json
{"log": "Hello World"}
{"log": {"var": "userName"}}
{"log": ["User: ", "+", {"var": "userName"}, "+", " logged in"]}
```
