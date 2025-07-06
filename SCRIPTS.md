# 📚 Guía de Scripts - Chat E2EE

Esta guía detalla todos los scripts disponibles en el proyecto, su propósito y cuándo utilizarlos.

## 🚀 Inicio Rápido

### Trabajo diario con el proyecto

```bash
# Iniciar el proyecto
./scripts/start.sh

# Verificar que todo esté funcionando
./scripts/health-check.sh

# Ver logs mientras desarrollas
./scripts/logs.sh postgres -f

# Detener el proyecto al terminar
./scripts/stop.sh
```

## 📋 Categorías de Scripts

Los scripts están organizados en categorías según su frecuencia de uso y propósito.

---

## 🟢 Scripts de USO FRECUENTE

Estos son los scripts que usarás en tu día a día de desarrollo.

### `start.sh`
**Propósito:** Inicia todos los servicios de Docker (PostgreSQL, Redis, MinIO)

**Cuándo usarlo:** Cada vez que quieras comenzar a trabajar en el proyecto

**Ejemplo:**
```bash
./scripts/start.sh
```

**Alternativa manual:**
```bash
cd docker && docker-compose up -d
```

---

### `stop.sh`
**Propósito:** Detiene todos los servicios de Docker de forma segura

**Cuándo usarlo:** Cuando termines de trabajar o necesites liberar recursos

**Ejemplo:**
```bash
./scripts/stop.sh
```

---

### `logs.sh`
**Propósito:** Ver logs de cualquier servicio en tiempo real

**Cuándo usarlo:** Para debugging o monitorear el comportamiento de los servicios

**Sintaxis:**
```bash
./scripts/logs.sh [servicio] [-f]
```

**Ejemplos:**
```bash
# Ver logs de PostgreSQL en tiempo real
./scripts/logs.sh postgres -f

# Ver últimas líneas de logs de Redis
./scripts/logs.sh redis

# Ver logs de todos los servicios
./scripts/logs.sh all -f
```

**Servicios disponibles:** `postgres`, `redis`, `minio`, `pgadmin`, `all`

---

### `health-check.sh`
**Propósito:** Verifica el estado de todos los servicios y muestra estadísticas

**Cuándo usarlo:** 
- Después de iniciar los servicios
- Si sospechas que algo no funciona bien
- Para ver uso de recursos

**Ejemplo:**
```bash
./scripts/health-check.sh
```

**Información que muestra:**
- Estado de cada servicio (✓ funcionando, ✗ detenido)
- Uso de disco
- Uso de memoria
- Errores recientes en logs

---

### `psql.sh`
**Propósito:** Acceso rápido a la consola de PostgreSQL

**Cuándo usarlo:** Para ejecutar consultas SQL o inspeccionar la base de datos

**Ejemplos:**
```bash
# Sesión interactiva
./scripts/psql.sh

# Ejecutar una consulta directa
./scripts/psql.sh "SELECT COUNT(*) FROM users;"

# Ver todas las tablas
./scripts/psql.sh "\dt"
```

---

### `redis-cli.sh`
**Propósito:** Acceso rápido a la consola de Redis/KeyDB

**Cuándo usarlo:** Para inspeccionar cache, sesiones o debug

**Ejemplos:**
```bash
# Sesión interactiva
./scripts/redis-cli.sh

# Ejecutar comando directo
./scripts/redis-cli.sh INFO

# Ver todas las keys
./scripts/redis-cli.sh KEYS "*"
```

---

## 🟡 Scripts de USO OCASIONAL

Scripts que usarás en situaciones específicas pero no diariamente.

### `restart.sh`
**Propósito:** Reinicia todos los servicios

**Cuándo usarlo:**
- Si un servicio no responde correctamente
- Después de cambiar configuraciones
- Para aplicar cambios en variables de entorno

**Ejemplos:**
```bash
# Reinicio normal
./scripts/restart.sh

# Reinicio completo (BORRA TODOS LOS DATOS)
./scripts/restart.sh --clean
```

⚠️ **PRECAUCIÓN:** La opción `--clean` elimina todas las bases de datos y archivos almacenados.

---

### `backup.sh`
**Propósito:** Crea backups encriptados de PostgreSQL y MinIO

**Cuándo usarlo:**
- Antes de actualizaciones importantes
- Periódicamente como buena práctica
- Antes de experimentos riesgosos

**Ejemplo:**
```bash
./scripts/backup.sh
```

**Características:**
- Encripta los backups con AES-256
- Guarda en `/home/usuario/backups/chat-e2ee`
- Limpia backups antiguos (más de 7 días)
- Opcionalmente sube a Backblaze B2 si está configurado

---

### `info.sh`
**Propósito:** Muestra información rápida del proyecto

**Cuándo usarlo:** Como referencia rápida de URLs, puertos y comandos

**Ejemplo:**
```bash
./scripts/info.sh
```

**Muestra:**
- URLs de servicios
- Comandos rápidos
- Estado actual
- Próximos pasos

---

## 🔴 Scripts de CONFIGURACIÓN INICIAL

Estos scripts generalmente se ejecutan una sola vez al configurar el proyecto.

### `full-setup.sh`
**Propósito:** Instalación completa del proyecto desde cero

**Cuándo usarlo:**
- Primera vez que clonas el repositorio
- Si necesitas reinstalar todo
- Si hay problemas graves de configuración

**Qué hace:**
1. Verifica prerequisitos (Docker, Docker Compose)
2. Crea estructura de directorios
3. Configura permisos
4. Genera archivo .env con contraseñas seguras
5. Inicia todos los servicios
6. Inicializa la base de datos

**Ejemplo:**
```bash
./scripts/full-setup.sh
```

---

### `init.sh`
**Propósito:** Inicialización básica del proyecto

**Cuándo usarlo:**
- Después de clonar el repo (si no usas full-setup.sh)
- Para reinicializar servicios

**Diferencia con full-setup.sh:** Menos exhaustivo, asume que ya tienes algunas cosas configuradas

---

### `setup-env.sh`
**Propósito:** Genera archivo .env con contraseñas seguras

**Cuándo usarlo:**
- Si no existe .env
- Si quieres regenerar todas las contraseñas
- Si perdiste el archivo .env

**Ejemplo:**
```bash
./scripts/setup-env.sh
```

⚠️ **NOTA:** Hará backup del .env existente antes de crear uno nuevo

---

### `fix-postgres-permissions.sh`
**Propósito:** Soluciona problemas de permisos en PostgreSQL

**Cuándo usarlo:** SOLO si encuentras errores de permisos al escribir logs

**Qué hace:**
1. Detiene servicios
2. Limpia directorios problemáticos
3. Recrea con permisos correctos
4. Modifica configuración de PostgreSQL
5. Reinicia servicios

**Ejemplo:**
```bash
./scripts/fix-postgres-permissions.sh
```

📌 **NOTA:** Este script ya se ejecutó una vez. No deberías necesitarlo nuevamente.

---

## 🔍 Scripts de DIAGNÓSTICO

Para troubleshooting y resolución de problemas.

### `diagnose-postgres.sh`
**Propósito:** Diagnóstico detallado de problemas con PostgreSQL

**Cuándo usarlo:** Si PostgreSQL no funciona o no puedes conectarte

**Qué verifica:**
- Estado del contenedor
- Logs detallados
- Proceso de PostgreSQL
- Conectividad
- Permisos de archivos
- Uso de recursos

**Ejemplo:**
```bash
./scripts/diagnose-postgres.sh
```

---

### `check-env.sh`
**Propósito:** Verifica que todas las variables de entorno estén configuradas

**Cuándo usarlo:**
- Si sospechas problemas de configuración
- Después de modificar .env
- Para verificar que no hay valores por defecto

**Ejemplo:**
```bash
./scripts/check-env.sh
```

---

### `check-ports.sh`
**Propósito:** Verifica disponibilidad de puertos necesarios

**Cuándo usarlo:**
- Si los servicios no pueden iniciar
- Error "port already in use"
- Antes de la instalación inicial

**Puertos que verifica:**
- 5432 (PostgreSQL)
- 6379 (Redis)
- 9000 (MinIO API)
- 9001 (MinIO Console)
- 5050 (pgAdmin)

**Ejemplo:**
```bash
./scripts/check-ports.sh
```

---

### `verify-all.sh`
**Propósito:** Ejecuta todas las verificaciones en secuencia

**Cuándo usarlo:** Para un diagnóstico completo del sistema

**Ejecuta en orden:**
1. check-env.sh
2. check-ports.sh
3. health-check.sh

**Ejemplo:**
```bash
./scripts/verify-all.sh
```

---

### `system-info.sh`
**Propósito:** Muestra información del sistema y recursos

**Cuándo usarlo:**
- Para verificar requisitos del sistema
- Documentar entorno de desarrollo
- Troubleshooting de performance

**Muestra:**
- OS y versión
- CPU y RAM
- Espacio en disco
- Versiones de Docker
- Uso de recursos del proyecto

**Ejemplo:**
```bash
./scripts/system-info.sh
```

---

### `list-files.sh`
**Propósito:** Lista la estructura de archivos del proyecto

**Cuándo usarlo:**
- Para ver la organización del proyecto
- Verificar que no falten archivos
- Documentación

**Ejemplo:**
```bash
./scripts/list-files.sh
```

---

## 💼 Flujos de Trabajo Comunes

### Desarrollo Diario

```bash
# Mañana - Comenzar a trabajar
./scripts/start.sh
./scripts/health-check.sh  # Verificar que todo está OK

# Durante el desarrollo
./scripts/logs.sh postgres -f  # En una terminal separada
./scripts/psql.sh              # Para queries SQL
./scripts/redis-cli.sh         # Para verificar cache

# Noche - Terminar de trabajar
./scripts/stop.sh
```

### Debugging de Problemas

```bash
# Verificación básica
./scripts/health-check.sh

# Si algo no funciona
./scripts/logs.sh [servicio] -f
./scripts/diagnose-postgres.sh

# Verificación completa
./scripts/verify-all.sh

# Reiniciar si es necesario
./scripts/restart.sh
```

### Mantenimiento Semanal

```bash
# Backup de datos
./scripts/backup.sh

# Verificar salud del sistema
./scripts/system-info.sh
./scripts/health-check.sh

# Limpiar logs antiguos (opcional)
docker system prune -f
```

### Después de Clonar el Repositorio

```bash
# Opción 1: Setup completo automático
./scripts/full-setup.sh

# Opción 2: Setup manual
./scripts/setup-env.sh
nano docker/.env  # Configurar credenciales
./scripts/init.sh
./scripts/health-check.sh
```

## 🛡️ Mejores Prácticas

1. **Siempre verifica el estado** después de iniciar servicios:
   ```bash
   ./scripts/health-check.sh
   ```

2. **Haz backups regulares** especialmente antes de cambios importantes:
   ```bash
   ./scripts/backup.sh
   ```

3. **Monitorea logs** cuando debuguees problemas:
   ```bash
   ./scripts/logs.sh [servicio] -f
   ```

4. **No uses `--clean`** a menos que realmente quieras borrar todos los datos

5. **Revisa las variables de entorno** después de actualizaciones:
   ```bash
   ./scripts/check-env.sh
   ```

## 📝 Notas Adicionales

- Todos los scripts deben ejecutarse desde la raíz del proyecto
- Los scripts asumen que tienes Docker y Docker Compose instalados
- Los datos se almacenan en `data/` (ignorado por git)
- Los logs se almacenan en `logs/` (ignorado por git)
- Las contraseñas se generan automáticamente en el primer setup

## 🆘 Solución Rápida de Problemas

| Problema | Solución |
|----------|----------|
| "Permission denied" | `./scripts/fix-postgres-permissions.sh` |
| "Port already in use" | `./scripts/check-ports.sh` luego cambiar puertos en .env |
| "Container not running" | `./scripts/restart.sh` |
| "Can't connect to PostgreSQL" | `./scripts/diagnose-postgres.sh` |
| "Lost all data" | Restaurar desde backup con instrucciones en `/home/user/backups/chat-e2ee/RESTORE_INSTRUCTIONS.md` |

## 🔗 Enlaces Útiles

- **PostgreSQL**: http://localhost:5432
- **Redis**: http://localhost:6379
- **MinIO Console**: http://localhost:9001
- **pgAdmin**: http://localhost:5050 (solo en modo desarrollo)

---

---

### `backend-init.sh`
**Propósito:** Inicializa el módulo Go del backend y descarga dependencias

**Cuándo usarlo:** 
- Primera vez antes de ejecutar el backend
- Si falta el archivo go.sum
- Después de agregar nuevas dependencias

**Ejemplo:**
```bash
./scripts/backend-init.sh
```

**Qué hace:**
- Verifica que Go esté instalado
- Inicializa go.mod si no existe
- Descarga todas las dependencias
- Genera go.sum
- Verifica que el código compile

---

### `backend-start.sh`
**Propósito:** Construye y levanta el backend con Docker

**Cuándo usarlo:** Para ejecutar el backend en modo producción

**Ejemplo:**
```bash
./scripts/backend-start.sh
```

**Características:**
- Verifica que los servicios base estén corriendo
- Inicializa el módulo Go si es necesario
- Construye la imagen Docker
- Levanta el contenedor del backend

---

### `backend-dev.sh`
**Propósito:** Ejecuta el backend en modo desarrollo con hot reload

**Cuándo usarlo:** Durante el desarrollo para ver cambios en tiempo real

**Ejemplo:**
```bash
./scripts/backend-dev.sh
```

**Características:**
- Usa Air para hot reload
- Carga variables de entorno locales
- No requiere Docker para el backend
- Ideal para desarrollo rápido

---

### `stop-backend.sh`
**Propósito:** Detiene solo el servicio backend

**Cuándo usarlo:** Cuando necesitas detener el backend sin afectar otros servicios

**Ejemplo:**
```bash
./scripts/stop-backend.sh
```

---

*Última actualización: Enero 2025*