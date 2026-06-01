#!/bin/bash
# PrepMind Backend Starter
# Binds to 0.0.0.0 so it's reachable from:
#   - Android emulator     (via 10.0.2.2:8000)
#   - iOS simulator        (via localhost:8000)
#   - iPhone/Android WiFi  (via LAN IP:8000)

set -e

# Get LAN IP
LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "unavailable")

# Update Flutter .env with current LAN IP (skipped when ngrok URL is already set)
FLUTTER_ENV="/Users/ubaid/Desktop/Ubaid/Ubexis/PrepMind/prepmind_app/.env"
if [ -f "$FLUTTER_ENV" ]; then
  CURRENT_URL=$(grep '^API_BASE_URL=' "$FLUTTER_ENV" | cut -d'=' -f2-)
  if echo "$CURRENT_URL" | grep -q "ngrok"; then
    echo "⏭️  ngrok URL detected — keeping API_BASE_URL=$CURRENT_URL"
  else
    sed -i '' "s|API_BASE_URL=.*|API_BASE_URL=http://${LAN_IP}:8000|" "$FLUTTER_ENV"
    echo "✅ Flutter API_BASE_URL set to http://${LAN_IP}:8000"
  fi
fi

echo ""
echo "┌─────────────────────────────────────────────┐"
echo "│         PrepMind Backend Starting            │"
echo "│                                              │"
echo "│  Local:    http://localhost:8000             │"
echo "│  Network:  http://${LAN_IP}:8000        │"
echo "│                                              │"
echo "│  iPhone/Android (WiFi): ${LAN_IP}:8000  │"
echo "│  Android Emulator:      10.0.2.2:8000        │"
echo "│  iOS Simulator:         localhost:8000       │"
echo "└─────────────────────────────────────────────┘"
echo ""

# Kill any existing server on port 8000
kill $(lsof -ti:8000) 2>/dev/null && echo "Stopped existing server" || true
sleep 1

# Start uvicorn bound to all interfaces
cd "$(dirname "$0")/prepmind_api"
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
