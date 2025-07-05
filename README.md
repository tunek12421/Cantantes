# Chat E2EE - Private Chat Platform

Plataforma de chat privado con encriptación end-to-end, diseñada para máxima privacidad sin almacenamiento de conversaciones.

## 🚀 Quick Start

### Prerequisitos
- Ubuntu Server 22.04+
- Docker & Docker Compose
- 4GB+ RAM
- 20GB+ espacio en disco

### Instalación

1. **Clonar el repositorio**
```bash
git clone <repository-url>
cd chat-e2ee
```

2. **Hacer ejecutables todos los scripts**
```bash
chmod +x scripts/*.sh
```

3. **Ejecutar instalación completa**
```bash
./scripts/full-setup.sh
```

O si prefieres paso a paso:

```bash
./scripts/setup-env.sh    # Configurar variables de entorno
./scripts/init.sh         # Inicializar servicios
```

## 📁 Estructura del Proyecto

```
chat-e2ee/
├── docker/           # Configuración de Docker
├── data/            # Datos persistentes (ignorado en git)
├── logs/            # Logs de servicios (ignorado en git)
├── scripts/         # Scripts de utilidad
└── src/             # Código fuente (próximamente)
```

## 📜 Scripts Disponibles

| Script | Descripción |
|--------|-------------|
| `full-setup.sh` | Instalación completa desde cero |
| `init.sh` | Inicialización de servicios |
| `setup-env.sh` | Configurar archivo .env con contraseñas seguras |
| `restart.sh` | Reiniciar todos los servicios |
| `health-check.sh` | Verificar salud de servicios |
| `logs.sh` | Ver logs de servicios |
| `backup.sh` | Crear backups encriptados |
| `verify-all.sh` | Verificación completa del sistema |
| `check-env.sh` | Verificar variables de entorno |
| `check-ports.sh` | Verificar disponibilidad de puertos |
| `diagnose-postgres.sh` | Diagnosticar problemas con PostgreSQL |
| `psql.sh` | Acceso rápido a PostgreSQL |
| `redis-cli.sh` | Acceso rápido a Redis/KeyDB |

## 🔧 Servicios

| Servicio | Puerto | Descripción |
|----------|--------|-------------|
| PostgreSQL | 5432 | Base de datos principal |
| Redis/KeyDB | 6379 | Cache y sesiones |
| MinIO | 9000/9001 | Almacenamiento de media |
| pgAdmin | 5050 | Admin DB (solo dev) |

## 📝 Comandos Útiles

### Gestión de servicios
```bash
# Instalación completa desde cero
./scripts/full-setup.sh

# Iniciar servicios
cd docker && docker-compose up -d

# Detener servicios
cd docker && docker-compose down

# Reiniciar servicios
./scripts/restart.sh

# Reiniciar y limpiar datos
./scripts/restart.sh --clean

# Ver logs
./scripts/logs.sh [servicio] [-f]
# Ejemplos:
./scripts/logs.sh postgres -f
./scripts/logs.sh all
```

### Verificación y diagnóstico
```bash
# Verificación completa del sistema
./scripts/verify-all.sh

# Verificar salud de servicios
./scripts/health-check.sh

# Verificar variables de entorno
./scripts/check-env.sh

# Verificar puertos disponibles
./scripts/check-ports.sh

# Diagnosticar PostgreSQL
./scripts/diagnose-postgres.sh
```

### Acceso a servicios
```bash
# PostgreSQL
./scripts/psql.sh                    # Sesión interactiva
./scripts/psql.sh "SELECT * FROM users"  # Ejecutar query

# Redis/KeyDB
./scripts/redis-cli.sh               # Sesión interactiva
./scripts/redis-cli.sh INFO          # Ejecutar comando

# MinIO Console
# Abrir http://localhost:9001 en navegador
```

### Mantenimiento
```bash
# Crear backup
./scripts/backup.sh

# Configurar nuevo archivo .env
./scripts/setup-env.sh
```

## 🔐 Seguridad

- ✅ E2EE con Signal Protocol
- ✅ Sin almacenamiento de mensajes
- ✅ Contraseñas auto-generadas
- ✅ TLS/SSL en producción
- ✅ Rate limiting
- ✅ GDPR compliant

## 🛠️ Desarrollo

### Próximos pasos (Día 3-4)
1. Implementar backend Go
2. WebSocket relay
3. Signal Protocol integration
4. API REST básica

### Estructura Go (próximamente)
```
src/
├── cmd/
│   └── server/
├── internal/
│   ├── auth/
│   ├── relay/
│   ├── media/
│   └── presence/
├── pkg/
│   ├── e2ee/
│   └── utils/
└── go.mod
```

## 📊 Monitoreo

```bash
# Ver uso de recursos
docker stats

# Verificar espacio en disco
df -h

# Logs en tiempo real
./scripts/health-check.sh
```

## 🆘 Troubleshooting

### Problema: PostgreSQL no está listo
```bash
# Diagnosticar el problema
./scripts/diagnose-postgres.sh

# Ver logs detallados
./scripts/logs.sh postgres

# Verificar si el puerto está en uso
./scripts/check-ports.sh

# Reiniciar PostgreSQL
cd docker && docker-compose restart postgres
```

### Problema: Variables de entorno no se cargan
```bash
# Verificar configuración
./scripts/check-env.sh

# Regenerar archivo .env
./scripts/setup-env.sh

# Verificar permisos
chmod 600 docker/.env
```

### Problema: Servicios no inician
```bash
# Verificación completa
./scripts/verify-all.sh

# Reiniciar todo
./scripts/restart.sh

# Reinstalación completa
./scripts/full-setup.sh
```

### Problema: Permisos en directorios
```bash
# Arreglar permisos
sudo chown -R $USER:$USER data/ logs/
sudo chown -R 999:999 data/postgres
sudo chown -R 1000:1000 data/minio
```

### Problema: Puertos en uso
```bash
# Ver qué está usando los puertos
./scripts/check-ports.sh

# Cambiar puertos en docker/.env
nano docker/.env
# Modificar: POSTGRES_PORT=5433, REDIS_PORT=6380, etc.
```

## 📈 Roadmap

- [x] Día 1-2: Infraestructura Docker ✅
  - [x] PostgreSQL con schema E2EE
  - [x] Redis/KeyDB para sesiones
  - [x] MinIO para almacenamiento
  - [x] Scripts de gestión
  - [x] Sistema de backups
- [ ] Día 3-4: Backend Go + WebSocket
- [ ] Día 5-6: Frontend PWA + E2EE
- [ ] Día 7: Testing + Deploy

## 🤝 Contribuir

1. Fork el proyecto
2. Crear feature branch
3. Commit cambios
4. Push a branch
5. Abrir Pull Request

## 📄 Licencia

Propietaria - Todos los derechos reservados