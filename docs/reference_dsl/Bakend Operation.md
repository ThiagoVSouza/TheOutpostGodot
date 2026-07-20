## BATCH 5: Backend Operations

### 5.1 Action Calls (Frontend ↔ Backend)

#### Call Action (Universal)

The `call` operation works differently depending on execution context:

**Frontend Context:** Sends HTTP request to backend action  
**Backend Context:** Executes another backend action (internal call)

**DSL:**
```nortrix
// From frontend - sends request to backend
call "login":
    email: @email
    password: @password

// From backend - calls another backend action
call "sendWelcomeEmail":
    userId: @userId
    email: @email
```

**JSON:**
```json
{
  "call": "login",
  "params": {
    "email": {"param": "email"},
    "password": {"param": "password"}
  }
}
```

```json
{
  "call": "sendWelcomeEmail",
  "params": {
    "userId": {"param": "userId"},
    "email": {"param": "email"}
  }
}
```

**Parser behavior:**
- **Frontend runtime:** Sends HTTP POST to Ali with params
- **Backend runtime:** Loads and executes action JSON, passes params
- `"call"` specifies the action name
- `"params"` is object with parameter key-value pairs
- Returns response data (can be object, array, string, number, boolean, or null)

---

#### Call with Response

**DSL:**
```nortrix
userData = call "getUserData":
    userId: $currentUserId

result = call "processPayment":
    amount: $total
    method: "credit_card"
```

**JSON:**
```json
{
  "var": "userData",
  "value": {
    "call": "getUserData",
    "params": {
      "userId": {"var": "currentUserId"}
    }
  }
}
```

```json
{
  "var": "result",
  "value": {
    "call": "processPayment",
    "params": {
      "amount": {"var": "total"},
      "method": "credit_card"
    }
  }
}
```

**Parser behavior:**
- Assigns backend response to variable
- Response can be object, array, string, number, or boolean

---

#### Call without Parameters

**DSL:**
```nortrix
call "logout"
data = call "getCurrentUser"
```

**JSON:**
```json
{"call": "logout"}
{"var": "data", "value": {"call": "getCurrentUser"}}
```

**Note on calls without response:**
When a `call` operation is used without assigning its result to a variable (e.g., `call "logout"`), the parser will still receive and process the response from the backend. The backend may return operations (such as UI updates, logs, or other instructions) that the frontend parser will execute. The response is not discarded—it's simply not stored in a variable. This allows backend actions to trigger frontend updates without explicit variable assignment.

---

#### Call vs Run - Key Differences

**`call` - Action Execution:**
- Executes a **backend action** (separate file/definition)
- Frontend: Makes HTTP request to backend
- Backend: Loads action JSON and executes it
- Used for API endpoints, business logic, database operations
- Example: `call "login"`, `call "getUserData"`

**`run` - Code Block Execution:**
- Executes a **local code block** (defined in same file)
- Frontend: Runs frontend code block
- Backend: Runs backend code block
- Used for reusable logic within the same context
- Example: `run showLoginForm`, `run validateInput`

**Example - Frontend calling backend action:**
```nortrix
// Frontend code
code handleLogin:
    email = #emailInput.value
    password = #passwordInput.value
    
    // Call backend action
    result = call "login":
        email: $email
        password: $password
    
    if $result.success:
        run showDashboard
    else:
        set #error.text = $result.message
```

**Example - Backend action calling another backend action:**
```nortrix
// Backend action: register
code register:
    // Insert user into database
    userId = db "users" insert:
        email: @email
        password: Hash(@password)
    
    // Call another backend action to send welcome email
    call "sendWelcomeEmail":
        userId: $userId
        email: @email
    
    return {success: true, userId: $userId}
```

---

### 5.2 Database Operations

#### Query - Select All

**DSL:**
```nortrix
users = db "users" select *

products = db "products" select * where status == "active"
```

**JSON:**
```json
{"var": "users", "value": {"db": "users", "action": "select", "cols": "*"}}
```

```json
{
  "var": "products",
  "value": {
    "db": "products",
    "action": "select",
    "cols": "*",
    "where": [{"col": "status"}, "==", "active"]
  }
}
```

**Returns:** Array of row objects

---

#### Query - Select Specific Columns

**DSL:**
```nortrix
userNames = db "users" select [id, name, email]

activeUsers = db "users" select [id, name] where active == true
```

**JSON:**
```json
{"var": "userNames", "value": {"db": "users", "action": "select", "cols": ["id", "name", "email"]}}
```

```json
{
  "var": "activeUsers",
  "value": {
    "db": "users",
    "action": "select",
    "cols": ["id", "name"],
    "where": [{"col": "active"}, "==", true]
  }
}
```

---

#### Query - Where Conditions

**DSL:**
```nortrix
// Simple condition
admins = db "users" select * where role == "admin"

// Multiple conditions
results = db "products" select * where category == "Electronics" AND price < 1000

// Complex conditions
filtered = db "orders" select * where (status == "pending" OR status == "processing") AND total > 100
```

**JSON:**
```json
{"var": "admins", "value": {"db": "users", "action": "select", "cols": "*", "where": [{"col": "role"}, "==", "admin"]}}
```

```json
{
  "var": "results",
  "value": {
    "db": "products",
    "action": "select",
    "cols": "*",
    "where": [[{"col": "category"}, "==", "Electronics"], "AND", [{"col": "price"}, "<", 1000]]
  }
}
```

```json
{
  "var": "filtered",
  "value": {
    "db": "orders",
    "action": "select",
    "cols": "*",
    "where": [[[{"col": "status"}, "==", "pending"], "OR", [{"col": "status"}, "==", "processing"]], "AND", [{"col": "total"}, ">", 100]]
  }
}
```

---

#### Query - Order By

**DSL:**
```nortrix
sortedUsers = db "users" select * orderBy name ASC

recentOrders = db "orders" select * orderBy created_at DESC
```

**JSON:**
```json
{"var": "sortedUsers", "value": {"db": "users", "action": "select", "cols": "*", "orderBy": "name", "order": "ASC"}}
{"var": "recentOrders", "value": {"db": "orders", "action": "select", "cols": "*", "orderBy": "created_at", "order": "DESC"}}
```

---

#### Query - Limit

**DSL:**
```nortrix
first10 = db "users" select * limit 10

topProducts = db "products" select * orderBy sales DESC limit 5
```

**JSON:**
```json
{"var": "first10", "value": {"db": "users", "action": "select", "cols": "*", "limit": 10}}
{"var": "topProducts", "value": {"db": "products", "action": "select", "cols": "*", "orderBy": "sales", "order": "DESC", "limit": 5}}
```

---

#### Insert Row

**DSL:**
```nortrix
db "users" insert:
    name: "John Doe"
    email: "john@example.com"
    role: "user"
    active: true

// With variable data
db "products" insert:
    name: $productName
    price: $productPrice
    category: $category
```

**JSON:**
```json
{
  "db": "users",
  "action": "insert",
  "values": {
    "name": "John Doe",
    "email": "john@example.com",
    "role": "user",
    "active": true
  }
}
```

```json
{
  "db": "products",
  "action": "insert",
  "values": {
    "name": {"var": "productName"},
    "price": {"var": "productPrice"},
    "category": {"var": "category"}
  }
}
```

**Returns:** Inserted row ID

---

#### Update Rows

**DSL:**
```nortrix
db "users" update set active:false where id == 5

db "products" update set price:$newPrice stock:$newStock where id == $productId
```

**JSON:**
```json
{
  "db": "users",
  "action": "update",
  "values": {"active": false},
  "where": [{"col": "id"}, "==", 5]
}
```

```json
{
  "db": "products",
  "action": "update",
  "values": {
    "price": {"var": "newPrice"},
    "stock": {"var": "newStock"}
  },
  "where": [{"col": "id"}, "==", {"var": "productId"}]
}
```

**Returns:** Number of affected rows

---

#### Delete Rows

**DSL:**
```nortrix
db "users" delete where id == 5

db "sessions" delete where expires_at < $now
```

**JSON:**
```json
{"db": "users", "action": "delete", "where": [{"col": "id"}, "==", 5]}
{"db": "sessions", "action": "delete", "where": [{"col": "expires_at"}, "<", {"var": "now"}]}
```

**Returns:** Number of deleted rows

---

### 5.3 Authentication & Session

#### Get Current User

**DSL:**
```nortrix
currentUser = Auth user

if $currentUser != null:
    Log "User ID: " + $currentUser.id
```

**JSON:**
```json
{"var": "currentUser", "value": {"auth": "user"}}
```

**Returns:** User object or null if not authenticated

---

#### Check Authentication

**DSL:**
```nortrix
isLoggedIn = Auth check

if $isLoggedIn:
    run showDashboard
else:
    run showLogin
```

**JSON:**
```json
{"var": "isLoggedIn", "value": {"auth": "check"}}
```

**Returns:** Boolean (true/false)

---

#### Get Session Data

**DSL:**
```nortrix
theme = Session get "theme"
language = Session get "language"
```

**JSON:**
```json
{"var": "theme", "value": {"session": "get", "key": "theme"}}
{"var": "language", "value": {"session": "get", "key": "language"}}
```

**Returns:** Session value or null

---

#### Set Session Data

**DSL:**
```nortrix
Session set "theme" $selectedTheme
Session set "language" "en"
```

**JSON:**
```json
{"session": "set", "key": "theme", "value": {"var": "selectedTheme"}}
{"session": "set", "key": "language", "value": "en"}
```

---

#### Clear Session Data

**DSL:**
```nortrix
Session clear "theme"
Session clearAll
```

**JSON:**
```json
{"session": "clear", "key": "theme"}
{"session": "clearAll": true}
```

---

### 5.4 File Operations

#### Upload File

**DSL:**
```nortrix
result = Upload file:@uploadedFile path:"/uploads/images/"

if $result.success:
    Log "File uploaded: " + $result.url
```

**JSON:**
```json
{
  "var": "result",
  "value": {
    "upload": true,
    "file": {"param": "uploadedFile"},
    "path": "/uploads/images/"
  }
}
```

**Returns:** Object with `{success: boolean, url: string, filename: string}`

---

#### Delete File

**DSL:**
```nortrix
DeleteFile "/uploads/images/old-photo.jpg"
```

**JSON:**
```json
{"deleteFile": "/uploads/images/old-photo.jpg"}
```

---

### 5.5 Email Operations

#### Send Email

**DSL:**
```nortrix
Email send:
    to: @userEmail
    subject: "Welcome to Nortrix"
    body: "Thank you for signing up!"

// With template
Email send:
    to: $user.email
    template: "welcome"
    data:
        name: $user.name
        activationLink: $link
```

**JSON:**
```json
{
  "email": "send",
  "to": {"param": "userEmail"},
  "subject": "Welcome to Nortrix",
  "body": "Thank you for signing up!"
}
```

```json
{
  "email": "send",
  "to": {"var": ["user", "email"]},
  "template": "welcome",
  "data": {
    "name": {"var": ["user", "name"]},
    "activationLink": {"var": "link"}
  }
}
```

---

### 5.6 HTTP Requests

#### HTTP GET

**DSL:**
```nortrix
response = HTTP GET "https://api.example.com/data"

result = HTTP GET "https://api.example.com/users" headers:
    Authorization: "Bearer " + $token
```

**JSON:**
```json
{"var": "response", "value": {"http": "GET", "url": "https://api.example.com/data"}}
```

```json
{
  "var": "result",
  "value": {
    "http": "GET",
    "url": "https://api.example.com/users",
    "headers": {
      "Authorization": ["Bearer ", "+", {"var": "token"}]
    }
  }
}
```

---

#### HTTP POST

**DSL:**
```nortrix
response = HTTP POST "https://api.example.com/users" body:
    name: "John Doe"
    email: "john@example.com"

result = HTTP POST "https://api.example.com/data" body:$payload headers:
    Content-Type: "application/json"
    Authorization: "Bearer " + $token
```

**JSON:**
```json
{
  "var": "response",
  "value": {
    "http": "POST",
    "url": "https://api.example.com/users",
    "body": {
      "name": "John Doe",
      "email": "john@example.com"
    }
  }
}
```

```json
{
  "var": "result",
  "value": {
    "http": "POST",
    "url": "https://api.example.com/data",
    "body": {"var": "payload"},
    "headers": {
      "Content-Type": "application/json",
      "Authorization": ["Bearer ", "+", {"var": "token"}]
    }
  }
}
```

---

#### HTTP PUT / DELETE

**DSL:**
```nortrix
HTTP PUT "https://api.example.com/users/5" body:
    name: $updatedName

HTTP DELETE "https://api.example.com/users/5"
```

**JSON:**
```json
{
  "http": "PUT",
  "url": "https://api.example.com/users/5",
  "body": {"name": {"var": "updatedName"}}
}
```

```json
{"http": "DELETE", "url": "https://api.example.com/users/5"}
```

---

### 5.7 Utility Operations

#### Generate UUID

**DSL:**
```nortrix
uniqueId = UUID()
```

**JSON:**
```json
{"var": "uniqueId", "value": {"uuid": true}}
```

**Returns:** UUID string (e.g., "550e8400-e29b-41d4-a716-446655440000")

---

#### Hash Password

**DSL:**
```nortrix
hashedPassword = Hash($password)
```

**JSON:**
```json
{"var": "hashedPassword", "value": {"hash": {"var": "password"}}}
```

**Returns:** Hashed password string

---

#### Verify Password

**DSL:**
```nortrix
isValid = VerifyHash($inputPassword, $storedHash)
```

**JSON:**
```json
{"var": "isValid", "value": {"verifyHash": [{"var": "inputPassword"}, {"var": "storedHash"}]}}
```

**Returns:** Boolean (true/false)

---

#### Generate Random String

**DSL:**
```nortrix
token = Random(32)
code = Random(6, numeric:true)
```

**JSON:**
```json
{"var": "token", "value": {"random": 32}}
{"var": "code", "value": {"random": 6, "numeric": true}}
```

**Returns:** Random string of specified length
