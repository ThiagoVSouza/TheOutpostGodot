## BATCH 4: Data Operations

### 4.1 Data Tables

#### Create Data Table

**DSL:**
```nortrix
data products:
    cols: [id, name, price, category]
    rows:
        [1, "Book", 10.99, "Education"]
        [2, "Pen", 2.50, "Office"]
        [3, "Notebook", 5.99, "Office"]
```

**JSON:**
```json
{
  "data": "products",
  "cols": ["id", "name", "price", "category"],
  "rows": [
    [1, "Book", 10.99, "Education"],
    [2, "Pen", 2.50, "Office"],
    [3, "Notebook", 5.99, "Office"]
  ]
}
```

**Parser behavior:**
- `"data"` is the table name
- `"cols"` defines column names
- `"rows"` is array of row arrays
- Creates in-memory data table for manipulation

---

#### Get All Rows

**DSL:**
```nortrix
allProducts = data products: getAll
```

**JSON:**
```json
{"var": "allProducts", "value": {"data": "products", "action": "getAll"}}
```

**Returns:** Array of objects with column names as keys
```javascript
[
  {id: 1, name: "Book", price: 10.99, category: "Education"},
  {id: 2, name: "Pen", price: 2.50, category: "Office"},
  {id: 3, name: "Notebook", price: 5.99, category: "Office"}
]
```

---

#### Get Specific Row

**DSL:**
```nortrix
firstProduct = data products: getRow 0
secondProduct = data products: getRow 1
```

**JSON:**
```json
{"var": "firstProduct", "value": {"data": "products", "action": "getRow", "index": 0}}
{"var": "secondProduct", "value": {"data": "products", "action": "getRow", "index": 1}}
```

**Returns:** Single object representing the row

---

#### Insert Row

**DSL:**
```nortrix
data products: insert [4, "Eraser", 1.25, "Office"]

// Or with object notation
data products: insert:
    id: 5
    name: "Ruler"
    price: 3.50
    category: "Office"
```

**JSON:**
```json
{"data": "products", "action": "insert", "row": [4, "Eraser", 1.25, "Office"]}
```

```json
{
  "data": "products",
  "action": "insert",
  "row": {
    "id": 5,
    "name": "Ruler",
    "price": 3.50,
    "category": "Office"
  }
}
```

**Parser behavior:**
- Array format: values must match column order
- Object format: keys must match column names
- Missing columns get null values

---

#### Update Row

**DSL:**
```nortrix
data products: update 0 set price:12.99
data products: update 2 set name:"Large Notebook" price:7.99
```

**JSON:**
```json
{"data": "products", "action": "update", "index": 0, "values": {"price": 12.99}}
{"data": "products", "action": "update", "index": 2, "values": {"name": "Large Notebook", "price": 7.99}}
```

---

#### Delete Row

**DSL:**
```nortrix
data products: delete 1
```

**JSON:**
```json
{"data": "products", "action": "delete", "index": 1}
```

---

#### Filter Rows

**DSL:**
```nortrix
officeProducts = data products: filter category == "Office"
expensiveProducts = data products: filter price > 5
```

**JSON:**
```json
{"var": "officeProducts", "value": {"data": "products", "action": "filter", "where": [{"col": "category"}, "==", "Office"]}}
{"var": "expensiveProducts", "value": {"data": "products", "action": "filter", "where": [{"col": "price"}, ">", 5]}}
```

**Returns:** Array of matching rows as objects

---

#### Sort Rows

**DSL:**
```nortrix
sortedByPrice = data products: sort price ASC
sortedByName = data products: sort name DESC
```

**JSON:**
```json
{"var": "sortedByPrice", "value": {"data": "products", "action": "sort", "col": "price", "order": "ASC"}}
{"var": "sortedByName", "value": {"data": "products", "action": "sort", "col": "name", "order": "DESC"}}
```

**Returns:** Array of sorted rows as objects

---

### 4.2 Array Operations

#### Create Array

**DSL:**
```nortrix
numbers = [1, 2, 3, 4, 5]
names = ["Alice", "Bob", "Charlie"]
mixed = [1, "text", true, 3.14]
```

**JSON:**
```json
{"var": "numbers", "value": [1, 2, 3, 4, 5]}
{"var": "names", "value": ["Alice", "Bob", "Charlie"]}
{"var": "mixed", "value": [1, "text", true, 3.14]}
```

---

#### Array Length

**DSL:**
```nortrix
count = length($numbers)
```

**JSON:**
```json
{"var": "count", "value": {"length": {"var": "numbers"}}}
```

---

#### Array Push (Add to End)

**DSL:**
```nortrix
push($numbers, 6)
push($names, "David")
```

**JSON:**
```json
{"push": {"var": "numbers"}, "value": 6}
{"push": {"var": "names"}, "value": "David"}
```

**Parser behavior:**
- Modifies the array in place
- Adds value to end of array

---

#### Array Pop (Remove from End)

**DSL:**
```nortrix
lastItem = pop($numbers)
```

**JSON:**
```json
{"var": "lastItem", "value": {"pop": {"var": "numbers"}}}
```

**Parser behavior:**
- Removes and returns last item
- Modifies the array in place

---

#### Array Get Item

**DSL:**
```nortrix
firstNumber = $numbers[0]
secondName = $names[1]
```

**JSON:**
```json
{"var": "firstNumber", "value": {"var": ["numbers", 0]}}
{"var": "secondName", "value": {"var": ["names", 1]}}
```

**Parser behavior:**
- Array index as number in path: `{"var": ["arrayName", 0]}`
- Consistent with object property access pattern
- Can mix property and index access: `{"var": ["users", 0, "name"]}`

---

#### Array Set Item

**DSL:**
```nortrix
$numbers[0] = 10
$names[1] = "Robert"
$users[0].name = "Alice"
```

**JSON:**
```json
{"var": ["numbers", 0], "value": 10}
{"var": ["names", 1], "value": "Robert"}
{"var": ["users", 0, "name"], "value": "Alice"}
```

**Parser behavior:**
- Uses array path with numeric index
- Can combine array index and object property access
- Consistent with get pattern

---

#### Array Contains

**DSL:**
```nortrix
hasThree = contains($numbers, 3)
hasAlice = contains($names, "Alice")
```

**JSON:**
```json
{"var": "hasThree", "value": {"contains": {"var": "numbers"}, "value": 3}}
{"var": "hasAlice", "value": {"contains": {"var": "names"}, "value": "Alice"}}
```

**Returns:** Boolean (true/false)

---

#### Array Join

**DSL:**
```nortrix
csv = join($names, ", ")
path = join($pathParts, "/")
```

**JSON:**
```json
{"var": "csv", "value": {"join": {"var": "names"}, "separator": ", "}}
{"var": "path", "value": {"join": {"var": "pathParts"}, "separator": "/"}}
```

**Returns:** String with array elements joined by separator

---

#### Array Slice

**DSL:**
```nortrix
first3 = slice($numbers, 0, 3)
middle = slice($names, 1, 3)
```

**JSON:**
```json
{"var": "first3", "value": {"slice": {"var": "numbers"}, "start": 0, "end": 3}}
{"var": "middle", "value": {"slice": {"var": "names"}, "start": 1, "end": 3}}
```

**Returns:** New array with elements from start to end (exclusive)

---

### 4.3 Object Operations

#### Create Object

**DSL:**
```nortrix
user = {
    id: 1,
    name: "John Doe",
    email: "john@example.com",
    active: true
}
```

**JSON:**
```json
{
  "var": "user",
  "value": {
    "id": 1,
    "name": "John Doe",
    "email": "john@example.com",
    "active": true
  }
}
```

---

#### Get Object Property

**DSL:**
```nortrix
userName = $user.name
userEmail = $user.email
nestedValue = $config.api.endpoint
```

**JSON:**
```json
{"var": "userName", "value": {"var": ["user", "name"]}}
{"var": "userEmail", "value": {"var": ["user", "email"]}}
{"var": "nestedValue", "value": {"var": ["config", "api", "endpoint"]}}
```

**Parser behavior:**
- `{"var": "user"}` gets the entire variable
- `{"var": ["user", "name"]}` gets nested property using array path
- Supports deep nesting with multiple path segments
- Consistent with `{"param": ["user", "name"]}` pattern from BATCH 1

---

#### Set Object Property

**DSL:**
```nortrix
$user.name = "Jane Doe"
$user.active = false
$config.api.timeout = 5000
```

**JSON:**
```json
{"var": ["user", "name"], "value": "Jane Doe"}
{"var": ["user", "active"], "value": false}
{"var": ["config", "api", "timeout"], "value": 5000}
```

**Parser behavior:**
- Uses standard `"var"` operation with array path
- Array path specifies nested property location
- No new operations needed - reuses existing syntax
- Consistent with get pattern

---

#### Object Keys

**DSL:**
```nortrix
propertyNames = keys($user)
```

**JSON:**
```json
{"var": "propertyNames", "value": {"keys": {"var": "user"}}}
```

**Returns:** Array of property names
```javascript
["id", "name", "email", "active"]
```

---

#### Object Values

**DSL:**
```nortrix
propertyValues = values($user)
```

**JSON:**
```json
{"var": "propertyValues", "value": {"values": {"var": "user"}}}
```

**Returns:** Array of property values
```javascript
[1, "John Doe", "john@example.com", true]
```

---

#### Object Has Property

**DSL:**
```nortrix
hasName = hasProperty($user, "name")
hasAge = hasProperty($user, "age")
```

**JSON:**
```json
{"var": "hasName", "value": {"hasProperty": {"var": "user"}, "property": "name"}}
{"var": "hasAge", "value": {"hasProperty": {"var": "user"}, "property": "age"}}
```

**Returns:** Boolean (true/false)

---

#### Merge Objects

**DSL:**
```nortrix
defaults = {theme: "light", lang: "en"}
userPrefs = {theme: "dark"}
finalPrefs = merge($defaults, $userPrefs)
```

**JSON:**
```json
{"var": "defaults", "value": {"theme": "light", "lang": "en"}}
{"var": "userPrefs", "value": {"theme": "dark"}}
{"var": "finalPrefs", "value": {"merge": [{"var": "defaults"}, {"var": "userPrefs"}]}}
```

**Returns:** New object with properties merged (second object overwrites first)
```javascript
{theme: "dark", lang: "en"}
```

---

### 4.4 JSON Operations

#### JSON Encode

**DSL:**
```nortrix
jsonString = toJSON($user)
```

**JSON:**
```json
{"var": "jsonString", "value": {"toJSON": {"var": "user"}}}
```

**Returns:** JSON string representation of object/array

---

#### JSON Decode

**DSL:**
```nortrix
userData = fromJSON($jsonString)
```

**JSON:**
```json
{"var": "userData", "value": {"fromJSON": {"var": "jsonString"}}}
```

**Returns:** Object/array parsed from JSON string

---

### 4.5 Type Checking

#### Check Type

**DSL:**
```nortrix
isString = typeOf($value) == "string"
isNumber = typeOf($count) == "number"
isArray = typeOf($items) == "array"
isObject = typeOf($user) == "object"
isBoolean = typeOf($active) == "boolean"
```

**JSON:**
```json
{"var": "isString", "value": [{"typeOf": {"var": "value"}}, "==", "string"]}
{"var": "isNumber", "value": [{"typeOf": {"var": "count"}}, "==", "number"]}
{"var": "isArray", "value": [{"typeOf": {"var": "items"}}, "==", "array"]}
{"var": "isObject", "value": [{"typeOf": {"var": "user"}}, "==", "object"]}
{"var": "isBoolean", "value": [{"typeOf": {"var": "active"}}, "==", "boolean"]}
```

**Supported types:**
- `"string"` — String value
- `"number"` — Numeric value
- `"boolean"` — Boolean (true/false)
- `"array"` — Array
- `"object"` — Object
- `"null"` — Null value
