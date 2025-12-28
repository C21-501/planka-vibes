#!/bin/bash
# =============================================================================
# Planka RFC Board Setup Script
# Creates project, board and status lists for RFC integration
# =============================================================================

set -e

# Configuration
PLANKA_URL="${PLANKA_URL:-http://localhost:3000}"
PLANKA_USERNAME="${PLANKA_USERNAME:-admin}"
PLANKA_PASSWORD="${PLANKA_PASSWORD:-admin123}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Planka RFC Board Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Login and get access token
echo -e "${YELLOW}[1/5] Logging into Planka...${NC}"
LOGIN_RESPONSE=$(curl -s -X POST "${PLANKA_URL}/api/access-tokens" \
  -H "Content-Type: application/json" \
  -d "{\"emailOrUsername\": \"${PLANKA_USERNAME}\", \"password\": \"${PLANKA_PASSWORD}\"}")

ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.item // empty')
if [ -z "$ACCESS_TOKEN" ]; then
  echo -e "${RED}Failed to login. Response: ${LOGIN_RESPONSE}${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Logged in successfully${NC}"

# Step 2: Create project
echo -e "${YELLOW}[2/5] Creating RFC project...${NC}"
PROJECT_RESPONSE=$(curl -s -X POST "${PLANKA_URL}/api/projects" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -d '{"name": "RFC Management", "type": "shared"}')

PROJECT_ID=$(echo "$PROJECT_RESPONSE" | jq -r '.item.id // empty')
if [ -z "$PROJECT_ID" ]; then
  # Try to find existing project
  PROJECTS=$(curl -s -X GET "${PLANKA_URL}/api/projects" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}")
  PROJECT_ID=$(echo "$PROJECTS" | jq -r '.items[] | select(.name == "RFC Management") | .id // empty' 2>/dev/null | head -1)
  
  if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Failed to create project. Response: ${PROJECT_RESPONSE}${NC}"
    exit 1
  fi
  echo -e "${GREEN}✓ Using existing project: ${PROJECT_ID}${NC}"
else
  echo -e "${GREEN}✓ Created project: ${PROJECT_ID}${NC}"
fi

# Step 3: Create board
echo -e "${YELLOW}[3/5] Creating RFC board...${NC}"
BOARD_RESPONSE=$(curl -s -X POST "${PLANKA_URL}/api/projects/${PROJECT_ID}/boards" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -d '{"name": "RFC Status Board", "position": 65535}')

BOARD_ID=$(echo "$BOARD_RESPONSE" | jq -r '.item.id // empty')
if [ -z "$BOARD_ID" ]; then
  # Try to find existing board
  BOARDS=$(curl -s -X GET "${PLANKA_URL}/api/projects/${PROJECT_ID}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}")
  BOARD_ID=$(echo "$BOARDS" | jq -r '.included.boards[] | select(.name == "RFC Status Board") | .id // empty' 2>/dev/null | head -1)
  
  if [ -z "$BOARD_ID" ]; then
    echo -e "${RED}Failed to create board. Response: ${BOARD_RESPONSE}${NC}"
    exit 1
  fi
  echo -e "${GREEN}✓ Using existing board: ${BOARD_ID}${NC}"
else
  echo -e "${GREEN}✓ Created board: ${BOARD_ID}${NC}"
fi

# Step 4: Create status lists (columns)
echo -e "${YELLOW}[4/5] Creating status lists...${NC}"

# RFC Status lists in order
LISTS=(
  "Новый"
  "На рассмотрении"
  "Одобрен"
  "Внедрен"
  "Отклонен"
)

POSITION=65535
for LIST_NAME in "${LISTS[@]}"; do
  LIST_RESPONSE=$(curl -s -X POST "${PLANKA_URL}/api/boards/${BOARD_ID}/lists" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -d "{\"name\": \"${LIST_NAME}\", \"position\": ${POSITION}, \"type\": \"active\"}")
  
  LIST_ID=$(echo "$LIST_RESPONSE" | jq -r '.item.id // empty')
  if [ -z "$LIST_ID" ]; then
    ERROR_MSG=$(echo "$LIST_RESPONSE" | jq -r '.message // "Unknown error"')
    echo -e "${YELLOW}  ⚠ List '${LIST_NAME}': ${ERROR_MSG}${NC}"
  else
    echo -e "${GREEN}  ✓ Created list: ${LIST_NAME} (${LIST_ID})${NC}"
  fi
  
  POSITION=$((POSITION + 65536))
done

# Step 5: Generate API token for integration
echo -e "${YELLOW}[5/5] Generating API token...${NC}"
TOKEN_RESPONSE=$(curl -s -X POST "${PLANKA_URL}/api/access-tokens" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -d '{"name": "RFC Integration Token"}')

# The access token we already have can be used
API_TOKEN="$ACCESS_TOKEN"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Add these values to your .env file:${NC}"
echo ""
echo -e "PLANKA_PROJECT_ID=${PROJECT_ID}"
echo -e "PLANKA_BOARD_ID=${BOARD_ID}"
echo -e "PLANKA_API_TOKEN=${API_TOKEN}"
echo ""
echo -e "${YELLOW}Note: For production, generate a dedicated API token in Planka UI:${NC}"
echo -e "${YELLOW}      Settings -> Access Tokens -> Create${NC}"
echo ""

# Optionally update .env file
if [ -f ".env" ]; then
  echo -e "${YELLOW}Would you like to update .env file automatically? (y/n)${NC}"
  read -r UPDATE_ENV
  if [ "$UPDATE_ENV" = "y" ] || [ "$UPDATE_ENV" = "Y" ]; then
    # Update or add values in .env
    if grep -q "PLANKA_PROJECT_ID=" .env; then
      sed -i "s/PLANKA_PROJECT_ID=.*/PLANKA_PROJECT_ID=${PROJECT_ID}/" .env
    else
      echo "PLANKA_PROJECT_ID=${PROJECT_ID}" >> .env
    fi
    
    if grep -q "PLANKA_BOARD_ID=" .env; then
      sed -i "s/PLANKA_BOARD_ID=.*/PLANKA_BOARD_ID=${BOARD_ID}/" .env
    else
      echo "PLANKA_BOARD_ID=${BOARD_ID}" >> .env
    fi
    
    if grep -q "PLANKA_API_TOKEN=" .env; then
      sed -i "s|PLANKA_API_TOKEN=.*|PLANKA_API_TOKEN=${API_TOKEN}|" .env
    else
      echo "PLANKA_API_TOKEN=${API_TOKEN}" >> .env
    fi
    
    echo -e "${GREEN}✓ .env file updated${NC}"
    echo -e "${YELLOW}Restart backend to apply changes:${NC}"
    echo -e "  docker compose restart code-vibes-backend"
  fi
fi

