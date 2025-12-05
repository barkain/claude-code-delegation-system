#!/bin/bash

# Generate UUID for session
SESSION_ID=$(uuidgen)
echo "Session ID: $SESSION_ID"

# Run the delegation command
/Users/nadavbarkai/.nvm/versions/node/v22.17.0/bin/claude \
  --session-id "$SESSION_ID" \
  '/delegate Delete all log files older than 30 days in the ./tests/test-logs directory and generate a cleanup report showing files removed and space reclaimed'
