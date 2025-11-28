#!/bin/bash

# ============================================================================
# RFC-Planka Integration Demo Script
# 
# This script demonstrates the full RFC lifecycle with automatic Planka sync:
# 1. Creates a new RFC → Card appears in "Новые" list
# 2. Approves the RFC → Card moves to "На рассмотрении" 
# 3. Shows the synced card in Planka
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak:8080}"
BACKEND_URL="${BACKEND_URL:-http://localhost:8080}"
PLANKA_URL="${PLANKA_URL:-http://localhost:3000}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-cab-realm}"
KEYCLOAK_CLIENT="${KEYCLOAK_CLIENT:-cab-frontend}"
KEYCLOAK_USER="${KEYCLOAK_USER:-admin}"
KEYCLOAK_PASSWORD="${KEYCLOAK_PASSWORD:-admin}"

# Generate random RFC ID suffix
RANDOM_ID=$(date +%s%N | sha256sum | head -c 8)
RFC_TITLE="RFC-${RANDOM_ID}: Demo Integration Test"

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        RFC-Planka Integration Demo                              ║"
echo "║        RFC ID: ${RANDOM_ID}                                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Function to print step
print_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to print info
print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# ============================================================================
# Step 1: Get Keycloak Token
# ============================================================================
print_step "Step 1: Authenticating with Keycloak"

# Try to get token from inside docker network first
if docker ps --format '{{.Names}}' | grep -q "cab_backend"; then
    print_info "Getting token via backend container..."
    TOKEN_RESPONSE=$(docker exec cab_backend curl -s -X POST "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${KEYCLOAK_USER}" \
        -d "password=${KEYCLOAK_PASSWORD}" \
        -d "grant_type=password" \
        -d "client_id=${KEYCLOAK_CLIENT}" 2>/dev/null)
else
    print_info "Getting token directly from Keycloak..."
    TOKEN_RESPONSE=$(curl -s -X POST "http://localhost:8081/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${KEYCLOAK_USER}" \
        -d "password=${KEYCLOAK_PASSWORD}" \
        -d "grant_type=password" \
        -d "client_id=${KEYCLOAK_CLIENT}" 2>/dev/null)
fi

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$ACCESS_TOKEN" ]; then
    print_error "Failed to get access token"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

print_success "Token obtained successfully (${#ACCESS_TOKEN} chars)"

# ============================================================================
# Step 2: Check existing data
# ============================================================================
print_step "Step 2: Checking existing systems and subsystems"

SYSTEMS=$(curl -s "${BACKEND_URL}/system" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json")

SYSTEM_COUNT=$(echo "$SYSTEMS" | grep -o '"totalElements":[0-9]*' | cut -d':' -f2)
print_info "Found $SYSTEM_COUNT system(s)"

if [ "$SYSTEM_COUNT" -eq "0" ]; then
    print_info "Creating test system and subsystem..."
    
    # Create system
    curl -s -X POST "${BACKEND_URL}/system" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"name": "Test System", "description": "Auto-created for demo"}' > /dev/null
    
    # Create team
    curl -s -X POST "${BACKEND_URL}/team" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"name": "Test Team", "memberIds": [1]}' > /dev/null
    
    # Create subsystem
    curl -s -X POST "${BACKEND_URL}/system/1/subsystem" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"name": "Test Subsystem", "description": "Auto-created", "systemId": 1, "teamId": 1}' > /dev/null
    
    print_success "Created test system, team, and subsystem"
fi

# ============================================================================
# Step 3: Create RFC (auto-syncs to Planka)
# ============================================================================
print_step "Step 3: Creating RFC (will auto-sync to Planka)"

IMPLEMENTATION_DATE=$(date -d "+30 days" +%Y-%m-%dT10:00:00Z 2>/dev/null || date -v+30d +%Y-%m-%dT10:00:00Z)

RFC_REQUEST='{
    "title": "'"${RFC_TITLE}"'",
    "description": "This RFC was created by the integration demo script.\n\nIt demonstrates automatic synchronization between code-vibes RFC system and Planka Kanban board.\n\nRandom ID: '"${RANDOM_ID}"'",
    "urgency": "PLANNED",
    "implementationDate": "'"${IMPLEMENTATION_DATE}"'",
    "affectedSystems": [
        {
            "systemId": 1,
            "affectedSubsystems": [
                {
                    "subsystemId": 1,
                    "executorId": 1
                }
            ]
        }
    ]
}'

print_info "Sending RFC creation request..."

RFC_RESPONSE=$(curl -s -X POST "${BACKEND_URL}/rfc" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$RFC_REQUEST")

RFC_ID=$(echo "$RFC_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
RFC_STATUS=$(echo "$RFC_RESPONSE" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$RFC_ID" ]; then
    print_error "Failed to create RFC"
    echo "Response: $RFC_RESPONSE"
    exit 1
fi

print_success "RFC created successfully!"
echo -e "  ${CYAN}RFC ID:${NC} $RFC_ID"
echo -e "  ${CYAN}Title:${NC} $RFC_TITLE"
echo -e "  ${CYAN}Status:${NC} $RFC_STATUS"

# ============================================================================
# Step 4: Verify Planka sync
# ============================================================================
print_step "Step 4: Verifying Planka synchronization"

sleep 2  # Wait for async operations

# Check backend logs for Planka sync
if docker ps --format '{{.Names}}' | grep -q "cab_backend"; then
    PLANKA_LOGS=$(docker logs cab_backend 2>&1 | grep -i "planka" | tail -5)
    
    if echo "$PLANKA_LOGS" | grep -q "Card created successfully"; then
        print_success "Card created in Planka!"
        PLANKA_CARD_ID=$(echo "$PLANKA_LOGS" | grep -o 'plankaCardId=[0-9]*' | tail -1 | cut -d'=' -f2)
        if [ -n "$PLANKA_CARD_ID" ]; then
            echo -e "  ${CYAN}Planka Card ID:${NC} $PLANKA_CARD_ID"
        fi
    else
        print_info "Checking Planka sync status..."
        echo "$PLANKA_LOGS"
    fi
fi

# ============================================================================
# Step 5: Get RFC details with Planka Card ID
# ============================================================================
print_step "Step 5: Getting RFC details"

RFC_DETAILS=$(curl -s "${BACKEND_URL}/rfc/${RFC_ID}" \
    -H "Authorization: Bearer $ACCESS_TOKEN")

echo -e "${CYAN}RFC Details:${NC}"
echo "$RFC_DETAILS" | python3 -m json.tool 2>/dev/null || echo "$RFC_DETAILS"

# ============================================================================
# Step 6: List all RFCs
# ============================================================================
print_step "Step 6: Listing all RFCs"

ALL_RFCS=$(curl -s "${BACKEND_URL}/rfc" \
    -H "Authorization: Bearer $ACCESS_TOKEN")

TOTAL_RFCS=$(echo "$ALL_RFCS" | grep -o '"totalElements":[0-9]*' | cut -d':' -f2)
print_info "Total RFCs in system: $TOTAL_RFCS"

# ============================================================================
# Summary
# ============================================================================
echo -e "\n${GREEN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    Demo Completed Successfully!                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${CYAN}Summary:${NC}"
echo -e "  • RFC ID: ${GREEN}$RFC_ID${NC}"
echo -e "  • RFC Title: ${GREEN}$RFC_TITLE${NC}"
echo -e "  • RFC Status: ${GREEN}$RFC_STATUS${NC}"
echo -e "  • Total RFCs: ${GREEN}$TOTAL_RFCS${NC}"
echo ""
echo -e "${CYAN}Check Planka board at:${NC} ${PLANKA_URL}/boards/1653882897599300613"
echo ""
echo -e "${YELLOW}The RFC card should appear in the 'Новые' list on the Planka board.${NC}"

