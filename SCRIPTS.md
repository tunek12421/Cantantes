# 📚 Scripts de Chat E2EE

Guía de uso de los scripts del proyecto.

## 🚀 Inicio Rápido

```bash
# Primera vez
./scripts/init.sh       # Configuración inicial
./scripts/start.sh      # Iniciar servicios

# Desarrollo diario
./scripts/start.sh      # Iniciar
./scripts/status.sh     # Verificar estado
./scripts/logs.sh -f    # Ver logs
./scripts/stop.sh       # Detener
```

## 📋 Scripts Disponibles

### `init.sh`
**Configuración inicial del proyecto**

```bash
./scripts/init.sh
```

- Verifica prerequisitos (Docker, Docker Compose)
- Crea directorios necesarios
- Genera archivo `.env` con contraseñas seguras
- Configura permisos

⚠️ **Solo ejecutar una vez al clonar el repositorio**

---

### `start.sh`
**Inicia todos los servicios**

```bash
./scripts/start.sh
```

Levanta: PostgreSQL, Redis, MinIO y Backend

---

### `stop.sh`
**Detiene todos los servicios**

```bash
./scripts/stop.sh
```

---

### `restart.sh`
**Reinicia todos los servicios**

```bash
./scripts/restart.sh
```

Útil después de cambiar configuraciones.

---

### `logs.sh`
**Ver logs de servicios**

```bash
# Todos los servicios
./scripts/logs.sh

# Servicio específico
./scripts/logs.sh postgres

# Seguir logs en tiempo real
./scripts/logs.sh postgres -f
./scripts/logs.sh -f
```

Servicios: `postgres`, `redis`, `minio`, `backend`

---

### `status.sh`
**Estado completo del sistema**

```bash
./scripts/status.sh
```

Muestra:
- Estado de cada servicio
- Uso de recursos
- Espacio en disco
- Errores recientes

---

### `dev.sh`
**Modo desarrollo con hot reload**

```bash
./scripts/dev.sh
```

- Ejecuta el backend localmente (sin Docker)
- Recarga automática al cambiar código
- Ideal para desarrollo rápido

**Requisitos**: Go 1.23+, Air

---

### `shell.sh`
**Acceso rápido a diferentes shells**

```bash
# PostgreSQL
./scripts/shell.sh postgres
./scripts/shell.sh postgres "SELECT * FROM users"

# Redis
./scripts/shell.sh redis
./scripts/shell.sh redis INFO

# Contenedor backend
./scripts/shell.sh backend

# MinIO
./scripts/shell.sh minio
```

---

### `backup.sh`
**Crear backups encriptados**

```bash
./scripts/backup.sh
```

- Backup de PostgreSQL y MinIO
- Encriptación AES-256
- Limpieza automática (>7 días)
- Ubicación: `~/backups/chat-e2ee`

---

### `info.sh`
**Información rápida del proyecto**

```bash
./scripts/info.sh
```

Muestra URLs, comandos útiles y estado.

## 🔧 Ejemplos de Uso

### Flujo de desarrollo típico

```bash
# Mañana
./scripts/start.sh          # Iniciar servicios
./scripts/status.sh         # Verificar que todo esté OK

# Durante el desarrollo
./scripts/dev.sh            # En una terminal
./scripts/logs.sh -f        # En otra terminal

# Debugging
./scripts/shell.sh postgres # Consultas SQL
./scripts/shell.sh redis    # Verificar cache

# Noche
./scripts/stop.sh          # Detener todo
```

### Solución de problemas

```bash
# Ver qué está pasando
./scripts/status.sh
./scripts/logs.sh postgres -f

# Reiniciar si hay problemas
./scripts/restart.sh
```

## 📍 URLs y Puertos

| Servicio | URL/Puerto | Credenciales |
|----------|------------|--------------|
| Backend API | http://localhost:8080 | - |
| MinIO Console | http://localhost:9001 | Ver `docker/.env` |
| PostgreSQL | localhost:5432 | Ver `docker/.env` |
| Redis | localhost:6379 | Ver `docker/.env` |

## 🛡️ Mejores Prácticas

1. **Siempre verifica el estado** después de iniciar:
   ```bash
   ./scripts/status.sh
   ```

2. **Haz backups regulares**:
   ```bash
   ./scripts/backup.sh
   ```

3. **No edites manualmente** los archivos en `data/`

4. **Para desarrollo**, usa el modo dev:
   ```bash
   ./scripts/dev.sh
   ```

## 🆘 Ayuda Rápida

| Problema | Solución |
|----------|----------|
| Servicios no inician | `./scripts/status.sh` para diagnosticar |
| Puerto en uso | Cambiar puerto en `docker/.env` |
| Permisos denegados | Verificar permisos de `data/` |
| Backend no conecta | Verificar que servicios base estén corriendo |

---

*Última actualización: Enero 2025*