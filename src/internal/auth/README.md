# Auth Module - Chat E2EE

Módulo de autenticación completo con SMS OTP y JWT para Chat E2EE.

## 📦 Componentes

### 1. **JWT Service** (`jwt.go`)
- Generación de tokens de acceso y refresh
- Validación de tokens
- Refresh de tokens expirados
- Duración configurable

### 2. **SMS Service** (`sms.go`)
- Generación de OTP de 6 dígitos
- Envío de SMS via Twilio o Mock
- Verificación de OTP con expiración
- Rate limiting de intentos

### 3. **Auth Middleware** (`middleware.go`)
- Protección de rutas con JWT
- Autenticación opcional
- Verificación de roles (future)
- Rate limiting

### 4. **Redis Store** (`redis_store.go`)
- Almacenamiento de OTPs temporales
- Gestión de sesiones
- Contadores para rate limiting

### 5. **Auth Handlers** (`handlers.go`)
- Endpoints REST para autenticación
- Registro/login con teléfono
- Gestión de dispositivos
- Logout

## 🚀 Uso

### Endpoints Disponibles

```
POST /api/v1/auth/request-otp
POST /api/v1/auth/verify-otp
POST /api/v1/auth/refresh
POST /api/v1/auth/logout (protected)
```

### Flujo de Autenticación

1. **Solicitar OTP**
```bash
curl -X POST http://localhost:8080/api/v1/auth/request-otp \
  -H "Content-Type: application/json" \
  -d '{"phone_number": "+1234567890"}'
```

2. **Verificar OTP**
```bash
curl -X POST http://localhost:8080/api/v1/auth/verify-otp \
  -H "Content-Type: application/json" \
  -d '{
    "phone_number": "+1234567890",
    "otp": "123456",
    "device_id": "device-uuid",
    "device_name": "Chrome on Windows",
    "public_key": "base64-encoded-public-key"
  }'
```

Respuesta:
```json
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "user_id": "uuid",
  "is_new_user": true
}
```

3. **Usar Token de Acceso**
```bash
curl -X GET http://localhost:8080/api/v1/users/me \
  -H "Authorization: Bearer eyJ..."
```

4. **Renovar Token**
```bash
curl -X POST http://localhost:8080/api/v1/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "eyJ..."}'
```

## 🔧 Configuración

Variables de entorno necesarias:

```bash
# JWT
JWT_SECRET=your-secret-key
JWT_ACCESS_TOKEN_EXPIRE=15m
JWT_REFRESH_TOKEN_EXPIRE=7d

# SMS Provider
SMS_PROVIDER=mock  # or "twilio"
TWILIO_ACCOUNT_SID=your-sid
TWILIO_AUTH_TOKEN=your-token
TWILIO_PHONE_NUMBER=+1234567890
```

## 🔒 Seguridad

- OTPs válidos por 5 minutos
- Máximo 3 intentos de OTP por hora
- Tokens de acceso: 15 minutos
- Tokens de refresh: 7 días
- Rate limiting en endpoints públicos
- Almacenamiento seguro de public keys para E2EE

## 🧪 Testing

En modo desarrollo (`SMS_PROVIDER=mock`), los OTPs se loguean en consola:

```
[MOCK SMS] To: +1234567890, Message: Your Chat E2EE verification code is: 123456
Valid for 5 minutes.
```

## 📝 Notas

- Los tokens JWT incluyen `user_id` y `device_id`
- Cada dispositivo tiene su propia clave pública para E2EE
- Las sesiones se almacenan en Redis con el refresh token como key
- El sistema soporta múltiples dispositivos por usuario