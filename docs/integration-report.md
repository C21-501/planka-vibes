# Отчёт об интеграции Code-Vibes RFC с Planka

## 🎯 Цель интеграции

Создание двунаправленной синхронизации между системой управления RFC (Request for Change) в Code-Vibes и Kanban-доской Planka.

---

## 📁 Архитектура решения

```
┌─────────────────────┐         REST API          ┌─────────────────────┐
│   Code-Vibes        │ ─────────────────────────►│      Planka         │
│   RFC Backend       │                           │   (Kanban Board)    │
│   :8080             │◄───────────────────────── │   :3000             │
│                     │         Webhooks          │                     │
└──────────┬──────────┘                           └──────────┬──────────┘
           │                                                 │
           ▼                                                 ▼
┌─────────────────────┐                           ┌─────────────────────┐
│     PostgreSQL      │                           │     PostgreSQL      │
│     (rfc_db)        │                           │     (planka_db)     │
└─────────────────────┘                           └─────────────────────┘
```

---

## 🔧 Что было реализовано

### 1. Backend Code-Vibes (Java Spring Boot)

#### Новые файлы:

| Файл | Назначение |
|------|------------|
| `WebhookController.java` | REST контроллер для приёма webhooks от Planka |
| `PlankaIntegrationService.java` | Интерфейс сервиса интеграции |
| `PlankaIntegrationServiceImpl.java` | Реализация синхронизации RFC ↔ Planka |
| `PlankaClient.java` | HTTP-клиент для взаимодействия с Planka API |
| `PlankaConfig.java` | Конфигурация интеграции |
| `PlankaCardRequest.java` | DTO для создания карточек в Planka |
| `PlankaCardResponse.java` | DTO для ответов от Planka API |
| `PlankaWebhookPayload.java` | DTO для входящих webhooks |

#### Изменённые файлы:

| Файл | Изменения |
|------|-----------|
| `RfcEntity.java` | Добавлено поле `plankaCardId` для связи с карточкой Planka |
| `RfcServiceImpl.java` | Добавлен вызов `syncRfcToPlanka()` после создания/обновления RFC |
| `application.yaml` | Добавлена секция конфигурации `planka:` |
| `application-docker.yaml` | Docker-специфичная конфигурация |

#### Миграция БД:

- `014-add-planka-card-id-to-rfc.xml` — добавление колонки `planka_card_id` в таблицу `rfc`

---

### 2. Маппинг статусов RFC → Списки Planka

| RFC Status | Planka List |
|------------|-------------|
| `NEW` | "Новые" |
| `UNDER_REVIEW` | "На рассмотрении" |
| `APPROVED` | "Утверждено" |
| `IMPLEMENTED` | "Выполнено" |
| `REJECTED` | "Отклонено" |

---

### 3. Docker Compose интеграция

Создан/обновлён `docker-compose.yml` в `code-vibes/backend/rfc-service/`:

```yaml
services:
  backend:
    environment:
      PLANKA_ENABLED: ${PLANKA_ENABLED:-true}
      PLANKA_URL: ${PLANKA_URL:-http://planka:1337}
      PLANKA_API_TOKEN: ${PLANKA_API_TOKEN}
      PLANKA_WEBHOOK_SECRET: ${RFC_WEBHOOK_SECRET}
      PLANKA_BOARD_ID: ${PLANKA_BOARD_ID}
```

---

### 4. Тестовый скрипт

Создан `test/rfc-planka-integration-demo.sh`:

**Функционал:**
1. ✅ Аутентификация через Keycloak
2. ✅ Проверка существующих систем/подсистем
3. ✅ Создание RFC с уникальным ID
4. ✅ Верификация синхронизации с Planka
5. ✅ Вывод детальной информации о созданном RFC

---

### 5. Исправленные проблемы

| Проблема | Решение |
|----------|---------|
| `process.env` не работает в Vite | Заменено на `import.meta.env` |
| `invalid_redirect_uri` в Keycloak | Добавлены `localhost:5173`, `localhost:5174` в Valid Redirect URIs |
| `401 Unauthorized` для RFC API | Исправлен `issuer-uri` на внутренний Docker URL |
| `400 Bad Request` при создании карточки | Исправлен `type` на "project", корректная обработка `dueDate` |
| Docker build ошибки | Исправлен путь к JAR в Dockerfile |

---

## 📊 Логика синхронизации

### При создании RFC:

```java
// RfcServiceImpl.java
public RfcDto createRfc(CreateRfcRequest request) {
    RfcEntity rfc = rfcMapper.toEntity(request);
    rfc = rfcRepository.save(rfc);
    
    // Автоматическая синхронизация с Planka
    plankaIntegrationService.syncRfcToPlanka(rfc);
    
    return rfcMapper.toDto(rfc);
}
```

### Создание карточки в Planka:

```java
// PlankaIntegrationServiceImpl.java
private PlankaCardRequest buildCardRequest(RfcEntity rfc, String listId) {
    return PlankaCardRequest.builder()
        .name(rfc.getTitle())
        .description(buildDescription(rfc))
        .listId(listId)
        .position(65535.0)
        .type("project")
        .dueDate(rfc.getImplementationDate())
        .rfcData(buildRfcData(rfc))
        .build();
}
```

---

## 🗂️ Структура файлов интеграции

```
planka-vibes/
├── code-vibes/
│   └── backend/rfc-service/src/main/java/ru/c21501/rfcservice/
│       ├── controller/
│       │   └── WebhookController.java          # Webhook endpoint
│       ├── service/
│       │   ├── PlankaIntegrationService.java   # Interface
│       │   └── impl/
│       │       └── PlankaIntegrationServiceImpl.java  # Implementation
│       ├── client/
│       │   └── PlankaClient.java               # HTTP client
│       ├── config/
│       │   └── PlankaConfig.java               # Configuration
│       ├── dto/planka/
│       │   ├── PlankaCardRequest.java
│       │   ├── PlankaCardResponse.java
│       │   └── PlankaWebhookPayload.java
│       └── model/entity/
│           └── RfcEntity.java                  # +plankaCardId field
├── test/
│   └── rfc-planka-integration-demo.sh          # Demo script
└── integration-env.example                      # Environment template
```

---

## ✅ Результат

При создании RFC через API Code-Vibes:
1. RFC сохраняется в БД Code-Vibes
2. Автоматически создаётся карточка в Planka
3. Карточка появляется в списке "Новые" на доске
4. `plankaCardId` сохраняется в RFC для дальнейшей синхронизации

---

## 🚀 Запуск интеграции

### 1. Настройка окружения

```bash
cp integration-env.example .env
# Отредактировать .env с нужными параметрами
```

### 2. Запуск сервисов

```bash
cd code-vibes/backend/rfc-service
docker-compose up -d
```

### 3. Тестирование

```bash
./test/rfc-planka-integration-demo.sh
```

---

## 📝 Конфигурация

### Переменные окружения (integration-env.example):

```env
# Planka Integration
PLANKA_ENABLED=true
PLANKA_URL=http://planka:1337
PLANKA_API_TOKEN=your-planka-api-token
PLANKA_BOARD_ID=your-board-id
RFC_WEBHOOK_SECRET=your-webhook-secret

# Keycloak
KEYCLOAK_URL=http://keycloak:8080
KEYCLOAK_REALM=cab-realm
KEYCLOAK_CLIENT_ID=cab-frontend
```

---

## 🔗 Связанные репозитории

- **planka-vibes**: https://github.com/C21-501/planka-vibes
- **code-vibes**: https://github.com/C21-501/code-vibes
- **planka**: https://github.com/C21-501/planka

---

*Документ создан: 29 ноября 2025*

