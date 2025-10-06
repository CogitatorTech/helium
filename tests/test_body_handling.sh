#!/bin/bash
# Test script to verify request body handling

echo "Building the project..."
cd /home/hassan/Workspace/CLionProjects/helium
zig build

echo -e "\n=== Starting the server in background ==="
./zig-out/bin/e1_simple_example &
SERVER_PID=$!
sleep 2

echo -e "\n=== Test 1: PUT request with body (should work) ==="
curl -X PUT http://127.0.0.1:3000/user/1 \
  -H "Content-Type: application/json" \
  -d '{"id":1,"name":"John Doe"}' \
  -w "\nHTTP Status: %{http_code}\n"

echo -e "\n=== Test 2: GET request without body (should work) ==="
curl -X GET http://127.0.0.1:3000/user/1 \
  -w "\nHTTP Status: %{http_code}\n"

echo -e "\n=== Test 3: POST request with body (should work) ==="
curl -X POST http://127.0.0.1:3000/user/2 \
  -H "Content-Type: application/json" \
  -d '{"id":2,"name":"Jane Smith"}' \
  -w "\nHTTP Status: %{http_code}\n"

echo -e "\n=== Stopping server ==="
kill $SERVER_PID
wait $SERVER_PID 2>/dev/null

echo -e "\n=== Tests completed ==="

