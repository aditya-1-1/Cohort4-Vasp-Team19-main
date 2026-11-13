#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
# Kill existing instance if running
pkill -f "python3.*server.py" 2>/dev/null || true
sleep 0.5
echo "Starting Rehearse AI Backend on http://localhost:8080..."
nohup python3 server.py > server.log 2>&1 &
sleep 1
curl -s http://localhost:8080/health && echo ""
echo "Rehearse AI Backend is running."

