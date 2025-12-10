#!/bin/bash

# ============================================================================
# RFC-Planka Integration Demo Script
# 
# This script demonstrates the full RFC lifecycle with automatic Planka sync:
# 1. Creates a new RFC → Card appears in "Новые" list
# 2. Tests bidirectional status sync (Planka → RFC)
# 3. Shows container logs for debugging
# ============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
BACKEND_URL="${BACKEND_URL:-http://localhost:8080}"
PLANKA_URL="${PLANKA_URL:-http://localhost:3000}"
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8081}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-cab-realm}"
KEYCLOAK_CLIENT="${KEYCLOAK_CLIENT:-cab-frontend}"
KEYCLOAK_USER="${KEYCLOAK_USER:-admin}"
KEYCLOAK_PASSWORD="${KEYCLOAK_PASSWORD:-admin}"

# Generate random RFC ID suffix
RANDOM_ID=$(date +%s | tail -c 6)
RFC_TITLE="RFC-TEST-${RANDOM_ID}: Integration Demo"

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        RFC-Planka Integration Demo                              ║"
echo "║        RFC ID: ${RANDOM_ID}                                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Function to print step
print_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# ============================================================================
# Step 1: Get Keycloak Token
# ============================================================================
print_step "Step 1: Authenticating with Keycloak"

print_info "Getting token from ${KEYCLOAK_URL}..."
TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${KEYCLOAK_USER}" \
    -d "password=${KEYCLOAK_PASSWORD}" \
    -d "grant_type=password" \
    -d "client_id=${KEYCLOAK_CLIENT}" 2>/dev/null)

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

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

SYSTEM_COUNT=$(echo "$SYSTEMS" | jq -r '.totalElements // 0')
print_info "Found ${SYSTEM_COUNT} system(s)"

if [ "$SYSTEM_COUNT" = "0" ] || [ -z "$SYSTEM_COUNT" ]; then
    print_info "Creating test system, team, and subsystem..."
    
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

IMPLEMENTATION_DATE=$(date -d "+30 days" +%Y-%m-%dT10:00:00Z 2>/dev/null || date -v+30d +%Y-%m-%dT10:00:00Z 2>/dev/null || echo "2025-01-15T10:00:00Z")

print_info "Sending RFC creation request..."

RFC_RESPONSE=$(curl -s -X POST "${BACKEND_URL}/rfc" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"title\": \"${RFC_TITLE}\",
        \"description\": \"This RFC was created by the integration demo script. Random ID: ${RANDOM_ID}\",
        \"urgency\": \"PLANNED\",
        \"implementationDate\": \"${IMPLEMENTATION_DATE}\",
        \"affectedSystems\": [{
            \"systemId\": 1,
            \"affectedSubsystems\": [{\"subsystemId\": 1, \"executorId\": 1}]
        }]
    }")

RFC_ID=$(echo "$RFC_RESPONSE" | jq -r '.id // empty')
RFC_STATUS=$(echo "$RFC_RESPONSE" | jq -r '.status // empty')

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

# Check backend logs for Planka sync and get card ID
print_info "Checking backend logs for Planka card creation..."
if docker ps --format '{{.Names}}' | grep -q "cab_backend"; then
    PLANKA_LOGS=$(docker logs cab_backend --tail 20 2>&1 | grep -i "planka")
    
    if echo "$PLANKA_LOGS" | grep -q "Card created successfully"; then
        print_success "Card created in Planka!"
        # Extract card ID from logs
        PLANKA_CARD_ID=$(echo "$PLANKA_LOGS" | grep -o 'id=[0-9]*' | head -1 | cut -d'=' -f2)
        if [ -z "$PLANKA_CARD_ID" ]; then
            PLANKA_CARD_ID=$(echo "$PLANKA_LOGS" | grep -o 'plankaCardId=[0-9]*' | tail -1 | cut -d'=' -f2)
        fi
        if [ -n "$PLANKA_CARD_ID" ]; then
            echo -e "  ${CYAN}Planka Card ID:${NC} $PLANKA_CARD_ID"
        fi
    else
        print_info "Planka sync logs:"
        echo "$PLANKA_LOGS" | tail -3
    fi
else
    print_info "Backend container not found"
fi

# ============================================================================
# Step 5: Get RFC details
# ============================================================================
print_step "Step 5: Getting RFC details"

RFC_DETAILS=$(curl -s "${BACKEND_URL}/rfc/${RFC_ID}" \
    -H "Authorization: Bearer $ACCESS_TOKEN")

echo -e "${CYAN}RFC Details:${NC}"
echo "$RFC_DETAILS" | jq '{id, title, status, plankaCardId, urgency}' 2>/dev/null || echo "$RFC_DETAILS"

# Try to get plankaCardId from response if not from logs
if [ -z "$PLANKA_CARD_ID" ]; then
    PLANKA_CARD_ID=$(echo "$RFC_DETAILS" | jq -r '.plankaCardId // empty')
fi

# ============================================================================
# Step 6: Test Bidirectional Sync - Move card in Planka
# ============================================================================
print_step "Step 6: Testing Bidirectional Sync (Planka → RFC)"

# Get Planka token
print_info "Getting Planka authentication token..."
PLANKA_TOKEN_RESPONSE=$(curl -s -X POST "${PLANKA_URL}/api/access-tokens" \
    -H "Content-Type: application/json" \
    -d '{"emailOrUsername":"demo@demo.demo","password":"demo"}')

PLANKA_TOKEN=$(echo "$PLANKA_TOKEN_RESPONSE" | jq -r '.item // empty')

if [ -z "$PLANKA_TOKEN" ]; then
    print_error "Failed to get Planka token"
    echo "Response: $PLANKA_TOKEN_RESPONSE"
else
    print_success "Planka token obtained"
    
    if [ -n "$PLANKA_CARD_ID" ]; then
        print_info "RFC linked to Planka card: $PLANKA_CARD_ID"
        
        # Move card to "Отклонено" list to test reverse sync
        REJECTED_LIST_ID="1661938954796008461"
        
        print_info "Moving card to 'Отклонено' list..."
        MOVE_RESPONSE=$(curl -s -X PATCH "${PLANKA_URL}/api/cards/${PLANKA_CARD_ID}" \
            -H "Authorization: Bearer $PLANKA_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"listId\": \"$REJECTED_LIST_ID\", \"position\": 65536}")
        
        sleep 3  # Wait for webhook to process
        
        # Check RFC status after card move
        RFC_AFTER_MOVE=$(curl -s "${BACKEND_URL}/rfc/${RFC_ID}" \
            -H "Authorization: Bearer $ACCESS_TOKEN")
        
        NEW_STATUS=$(echo "$RFC_AFTER_MOVE" | jq -r '.status // empty')
        
        if [ "$NEW_STATUS" = "REJECTED" ]; then
            print_success "Bidirectional sync works! RFC status changed to: $NEW_STATUS"
        else
            print_info "RFC status after card move: $NEW_STATUS"
        fi
    else
        print_info "Planka card ID not found, skipping bidirectional test"
        print_info "Card may still be syncing..."
    fi
fi

# ============================================================================
# Step 7: List all RFCs
# ============================================================================
print_step "Step 7: Listing all RFCs"

ALL_RFCS=$(curl -s "${BACKEND_URL}/rfc" \
    -H "Authorization: Bearer $ACCESS_TOKEN")

TOTAL_RFCS=$(echo "$ALL_RFCS" | jq -r '.totalElements // 0')
print_info "Total RFCs in system: $TOTAL_RFCS"

# ============================================================================
# Step 8: Show Container Logs
# ============================================================================
print_step "Step 8: Container Logs (Last 15 lines)"

echo -e "\n${CYAN}=== Backend Logs (Planka Integration) ===${NC}"
if docker ps --format '{{.Names}}' | grep -q "cab_backend"; then
    docker logs cab_backend --tail 15 2>&1 | grep -i "planka\|webhook\|rfc.*status\|card" || echo "No relevant logs found"
else
    echo "Backend container not found"
fi

echo -e "\n${CYAN}=== Planka Logs (Webhook) ===${NC}"
if docker ps --format '{{.Names}}' | grep -q "planka-planka"; then
    docker logs planka-planka-1 --tail 15 2>&1 | grep -i "rfc\|webhook\|card moved" || echo "No relevant logs found"
else
    echo "Planka container not found"
fi

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
echo -e "  • Initial Status: ${GREEN}$RFC_STATUS${NC}"
echo -e "  • Final Status: ${GREEN}${NEW_STATUS:-$RFC_STATUS}${NC}"
echo -e "  • Planka Card ID: ${GREEN}${PLANKA_CARD_ID:-N/A}${NC}"
echo -e "  • Total RFCs: ${GREEN}$TOTAL_RFCS${NC}"
echo ""
echo -e "${CYAN}Check Planka board at:${NC} ${PLANKA_URL}"
echo ""
echo -e "${YELLOW}Integration test completed!${NC}"
