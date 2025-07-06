# Chat E2EE Backend

Backend en Go para la plataforma de chat privado con encriptación end-to-end.

## 🏗️ Arquitectura

```
src/
├── cmd/
│   └── server/
│       └── main.go          # Punto de entrada
├── internal/
│   ├── api/                 # Handlers HTTP y rutas
│   ├── auth/                # Autenticación y JWT
│   ├── config/              # Configuración
│   ├── database/            # Conexiones DB
│   ├── media/               # Gestión de archivos
│   ├── models/              # Modelos de datos
│   ├── presence/            # Estado online/offline
│   └── relay/               # WebSocket relay
├── pkg/
│   ├── e2ee/                # Helpers E2EE
│   └── utils/               # Utilidades comunes
├── go.mod
└── go.sum
```

## 🚀 Desarrollo

### Prerequisitos
- Go 1.21+
- Docker y Docker Compose
- Air (para hot reload)

### Instalación

```bash
# Instalar air para hot reload
go install github.com/cosmtrek/air@latest

# Descargar dependencias
cd src
go mod download
```

### Ejecutar en desarrollo

```bash
# Con hot reload
./scripts/backend-dev.sh

# O manualmente
cd src
air
```

### Ejecutar con Docker

```bash
cd docker
docker-compose up -d backend
```

## 📡 API Endpoints

### Health Check
```
GET /health
```

### Authentication
```
POST /api/v1/auth/request-otp    # Solicitar código SMS
POST /api/v1/auth/verify-otp     # Verificar código
POST /api/v1/auth/refresh        # Renovar token
POST /api/v1/auth/logout         # Cerrar sesión
```

### Users
```
GET  /api/v1/users/me           # Perfil actual
PUT  /api/v1/users/me           # Actualizar perfil
GET  /api/v1/users/:id          # Ver usuario
POST /api/v1/users/contacts     # Agregar contacto
```

### WebSocket
```
WS /ws                          # Conexión WebSocket para chat
```

### Media
```
POST   /api/v1/media/upload     # Subir archivo
GET    /api/v1/media/:id        # Obtener archivo
DELETE /api/v1/media/:id        # Eliminar archivo
```

### Gallery (Models)
```
GET    /api/v1/gallery          # Mi galería
POST   /api/v1/gallery/media    # Agregar a galería
DELETE /api/v1/gallery/media/:id # Eliminar de galería
```

## 🔐 Autenticación

El sistema usa JWT con dos tokens:
- **Access Token**: 15 minutos
- **Refresh Token**: 7 días

Flujo:
1. Usuario solicita OTP con número telefónico
2. Sistema envía SMS
3. Usuario verifica código
4. Sistema devuelve access + refresh tokens
5. Cliente renueva con refresh token cuando expira

## 🔒 E2EE Protocol

Implementación del Signal Protocol:
1. Cada dispositivo genera keypair
2. Intercambio de public keys
3. Mensajes encriptados cliente-a-cliente
4. Servidor solo hace relay (no puede leer)

## 📊 WebSocket Messages

### Cliente → Servidor
```json
{
  "type": "message",
  "to": "user-uuid",
  "payload": "encrypted-data"
}
```

### Servidor → Cliente
```json
{
  "type": "message",
  "from": "user-uuid",
  "payload": "encrypted-data",
  "timestamp": "2024-01-01T00:00:00Z"
}
```

### Tipos de mensaje
- `message`: Mensaje encriptado
- `typing`: Indicador escribiendo
- `read`: Confirmación de lectura
- `presence`: Cambio de estado online/offline

## 🔧 Configuración

Variables de entorno principales:

```bash
# App
APP_ENV=development
APP_PORT=8080
APP_DEBUG=true

# Database
POSTGRES_HOST=localhost
POSTGRES_USER=chat_user
POSTGRES_PASSWORD=xxx

# Redis
REDIS_HOST=localhost
REDIS_PASSWORD=xxx

# JWT
JWT_SECRET=xxx

# SMS
SMS_PROVIDER=twilio
TWILIO_ACCOUNT_SID=xxx
TWILIO_AUTH_TOKEN=xxx
```

## 🧪 Testing

```bash
# Unit tests
go test ./...

# Con coverage
go test -cover ./...

# Test específico
go test -v ./internal/auth
```

## 📈 Performance

Optimizaciones implementadas:
- Connection pooling para DB
- Rate limiting con Redis
- Compresión WebSocket
- Caching de media con ETags
- Graceful shutdown

## 🚢 Deployment

El backend se compila a un binario estático:

```bash
# Build para producción
CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o chat-e2ee cmd/server/main.go

# Con Docker
docker build -f docker/backend/Dockerfile -t chat-e2ee-backend .
```