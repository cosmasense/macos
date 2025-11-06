# Network Access Fix

## Problem
The app was unable to connect to the backend API due to macOS App Sandbox restrictions. The error was:
```
nw_resolver_can_use_dns_xpc_block_invoke Sandbox does not allow access to com.apple.dnssd.service
Connection failed with error code: -1003 "A server with the specified hostname could not be found."
```

## Solution
Added network client entitlements to allow outgoing HTTP connections.

## What Was Changed

### 1. Created Entitlements File
**File:** `fileSearchForntend/fileSearchForntend.entitlements`

Added three key entitlements:
- `com.apple.security.app-sandbox`: Enables app sandboxing (already present)
- `com.apple.security.files.user-selected.read-only`: Allows reading user-selected files (already present)
- **`com.apple.security.network.client`**: **NEW** - Allows outgoing network connections

### 2. Updated Xcode Project
Modified `project.pbxproj` to reference the entitlements file in both Debug and Release configurations:
```
CODE_SIGN_ENTITLEMENTS = fileSearchForntend/fileSearchForntend.entitlements;
```

## Backend Configuration

The API client is configured to connect to:
```
http://localhost:8080/api/search
```

If your backend runs on a different port, update `Services/APIClient.swift`:

```swift
static let `default` = APIConfiguration(
    baseURL: URL(string: "http://localhost:YOUR_PORT")!,
    timeout: 30.0
)
```

## How to Test

1. **Start your backend server** on port 8080 (or update the port in APIClient.swift)
2. **Rebuild the app** (the entitlements are now included)
3. **Run the app** and try searching
4. You should see successful API requests in the logs

## Expected Behavior After Fix

✅ No more sandbox errors
✅ Network connections to localhost:8080 succeed
✅ Search results display from your backend
✅ Error handling works for actual API errors (vs. network blocked)

## Additional Network Permissions

If you need to connect to external APIs (not localhost), the current entitlements already support that with:
```xml
<key>com.apple.security.network.client</key>
<true/>
```

This allows connections to:
- localhost (127.0.0.1)
- Any external domain
- Any port

## Debugging Network Issues

If you still have connection issues:

1. **Verify backend is running:**
   ```bash
   curl http://localhost:8080/api/search -X POST -H "Content-Type: application/json" -d '{"query":"test","limit":10}'
   ```

2. **Check the port number** in both:
   - Your backend server
   - `Services/APIClient.swift`

3. **Review Console logs** for detailed error messages

4. **Verify entitlements are applied:**
   ```bash
   codesign -d --entitlements - /path/to/fileSearchForntend.app
   ```
