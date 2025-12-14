# Planka-Vibes

RFC (Request for Change) Management System integrated with Planka Kanban Board.

## Features

- **RFC Management**: Create, track, and manage change requests
- **Planka Integration**: Bidirectional sync between RFC system and Planka kanban
- **Keycloak Auth**: Secure authentication via Keycloak
- **Status Workflow**: Automated status transitions based on approvals

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Frontend      │────▶│   Backend       │────▶│   PostgreSQL    │
│   (React)       │     │   (Spring Boot) │     │   (code-vibes)  │
│   :5173         │     │   :8080         │     │                 │
└─────────────────┘     └────────┬────────┘     └─────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    │                         │
               ┌────▼────┐              ┌─────▼─────┐
               │ Keycloak│              │  Planka   │
               │  :8081  │              │   :3000   │
               └─────────┘              └───────────┘
```

## Quick Start

### Prerequisites

- Docker & Docker Compose
- Git

### Setup

1. **Clone the repository with submodules:**
   ```bash
   git clone --recursive https://github.com/C21-501/planka-vibes.git
   cd planka-vibes
   ```

2. **Configure environment:**
   ```bash
   # Copy example environment file
   cp .env.example .env
   
   # Edit .env and set all required values:
   # - POSTGRES_PASSWORD
   # - KEYCLOAK_ADMIN_PASSWORD
   # - PLANKA_SECRET_KEY (generate: openssl rand -hex 32)
   # - PLANKA_ADMIN_PASSWORD
   # - PLANKA_WEBHOOK_SECRET (generate: openssl rand -hex 16)
   ```

3. **Start all services:**
   ```bash
   docker compose up -d --build
   ```

4. **Wait for services to be healthy:**
   ```bash
   docker compose ps
   ```

5. **Configure Planka integration:**
   
   a. Open Planka: http://localhost:3000
   
   b. Login with admin credentials from `.env`
   
   c. Create a project and board for RFC
   
   d. Generate API token: Settings → Access Tokens
   
   e. Update `.env` with:
      - `PLANKA_API_TOKEN` - generated token
      - `PLANKA_PROJECT_ID` - from API or URL
      - `PLANKA_BOARD_ID` - from board URL
   
   f. Restart backend:
      ```bash
      docker compose up -d code-vibes-backend
      ```

## Services

| Service | URL | Description |
|---------|-----|-------------|
| RFC Frontend | http://localhost:5173 | React web application |
| RFC Backend | http://localhost:8080 | Spring Boot REST API |
| Keycloak | http://localhost:8081 | Authentication server |
| Planka | http://localhost:3000 | Kanban board |

## Default Credentials

> ⚠️ **Change these in production!**

| Service | Username | Password |
|---------|----------|----------|
| Keycloak Admin | admin | (from .env: KEYCLOAK_ADMIN_PASSWORD) |
| RFC System | admin | admin (synced from Keycloak) |
| Planka | admin | (from .env: PLANKA_ADMIN_PASSWORD) |

## First Start Checklist

After `docker compose up -d`:

1. **Verify all services are running:**
   ```bash
   docker compose ps
   # All services should show "healthy" or "Up"
   ```

2. **Login to Planka** at http://localhost:3000 with `admin` / `admin`

3. **Login to RFC System** at http://localhost:5173 with `admin` / `admin`
   
   > First login may show "User not found" error - this is expected.
   > The user will be auto-created on first successful login.

4. **Configure integration** (see Quick Start step 5)

## Environment Variables

See [.env.example](.env.example) for all available options.

### Required Variables

| Variable | Description |
|----------|-------------|
| `POSTGRES_PASSWORD` | PostgreSQL database password |
| `KEYCLOAK_ADMIN_PASSWORD` | Keycloak admin password |
| `PLANKA_SECRET_KEY` | JWT secret (min 32 chars) |
| `PLANKA_ADMIN_PASSWORD` | Planka admin password |
| `PLANKA_WEBHOOK_SECRET` | Webhook validation secret |

### Integration Variables

| Variable | Description |
|----------|-------------|
| `PLANKA_API_TOKEN` | API token from Planka |
| `PLANKA_PROJECT_ID` | Target project ID |
| `PLANKA_BOARD_ID` | Target board ID |

## Development

### Running Frontend Locally

```bash
cd code-vibes/frontend
npm install
npm run dev
```

### Running Backend Locally

```bash
cd code-vibes/backend/rfc-service
./gradlew bootRun
```

## Security Notes

- Never commit `.env` file
- Use strong passwords in production
- Rotate API tokens periodically
- Enable HTTPS in production

## License

MIT
