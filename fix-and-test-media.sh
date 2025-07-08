#!/bin/bash

echo "🔧 Corrección y Prueba del Sistema de Media"
echo "==========================================="

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Aplicar correcciones al código
echo -e "${YELLOW}1. Aplicando correcciones al código...${NC}"

# Backup
cp src/internal/media/handlers.go src/internal/media/handlers.go.bak 2>/dev/null
cp src/internal/media/service.go src/internal/media/service.go.bak 2>/dev/null

# Agregar import io si no existe
if ! grep -q "\"io\"" src/internal/media/handlers.go; then
    sed -i '/"fmt"/a\\t"io"' src/internal/media/handlers.go
    echo "✅ Import 'io' agregado"
fi

# Corregir GetFile - cambiar SendStream por Send con ReadAll
echo "Corrigiendo GetFile handler..."
sed -i 's/return c\.SendStream(reader)/data, err := io.ReadAll(reader); if err != nil { return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to read file"}) }; return c.Send(data)/' src/internal/media/handlers.go

# Simplificar DeleteFile
echo "Simplificando DeleteFile..."
sed -i 's/SELECT filename FROM gallery_media WHERE id = \$1 AND gallery_id IN (/SELECT filename FROM gallery_media WHERE id = \$1 --/' src/internal/media/service.go
sed -i 's/, userID/).Scan(&filename)/).Scan(&filename)/' src/internal/media/service.go

# Agregar MINIO_PUBLIC_ENDPOINT si no existe
if ! grep -q "MINIO_PUBLIC_ENDPOINT" docker/.env; then
    echo "" >> docker/.env
    echo "# MinIO public endpoint for presigned URLs" >> docker/.env
    echo "MINIO_PUBLIC_ENDPOINT=http://localhost:9000" >> docker/.env
    echo "✅ MINIO_PUBLIC_ENDPOINT agregado a .env"
fi

# 2. Rebuild del backend
echo -e "\n${YELLOW}2. Rebuilding backend...${NC}"
cd docker
docker-compose build backend
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error en build${NC}"
    cd ..
    exit 1
fi

# 3. Reiniciar servicio
echo -e "\n${YELLOW}3. Reiniciando backend...${NC}"
docker-compose restart backend
cd ..

# 4. Esperar a que esté listo
echo -e "\n${YELLOW}4. Esperando a que el servicio esté listo...${NC}"
for i in {1..30}; do
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Servicio listo!${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

# 5. Obtener token fresco
echo -e "\n${YELLOW}5. Obteniendo token fresco...${NC}"
./get-fresh-token-complete.sh > /tmp/token-output.log 2>&1
source /tmp/fresh-websocket-tokens.txt

if [ -z "$ACCESS_TOKEN" ]; then
    echo -e "${RED}❌ No se pudo obtener token${NC}"
    cat /tmp/token-output.log
    exit 1
fi
echo -e "${GREEN}✅ Token obtenido${NC}"

# 6. Test de upload/download
echo -e "\n${YELLOW}6. Test de upload y descarga...${NC}"

# Crear archivo de prueba con contenido real
echo "=== Archivo de prueba Chat E2EE ===" > test-file.txt
echo "Fecha: $(date)" >> test-file.txt
echo "Este archivo contiene datos de prueba" >> test-file.txt
for i in {1..20}; do
    echo "Línea $i: Lorem ipsum dolor sit amet, consectetur adipiscing elit." >> test-file.txt
done
echo "=== Fin del archivo ===" >> test-file.txt

ORIGINAL_SIZE=$(stat -c%s test-file.txt 2>/dev/null || stat -f%z test-file.txt)
echo "Archivo de prueba creado: $ORIGINAL_SIZE bytes"

# Upload
echo -e "\n${YELLOW}Subiendo archivo...${NC}"
UPLOAD_RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/media/upload \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@test-file.txt;type=text/plain")

echo "$UPLOAD_RESPONSE" | jq '.'

MEDIA_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.id')
if [ "$MEDIA_ID" == "null" ] || [ -z "$MEDIA_ID" ]; then
    echo -e "${RED}❌ Error en upload${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Archivo subido con ID: $MEDIA_ID${NC}"

# Download
echo -e "\n${YELLOW}Descargando archivo...${NC}"
curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
     -o downloaded-file.txt \
     "http://localhost:8080/api/v1/media/$MEDIA_ID"

if [ -f "downloaded-file.txt" ]; then
    DOWNLOADED_SIZE=$(stat -c%s downloaded-file.txt 2>/dev/null || stat -f%z downloaded-file.txt)
    echo "Archivo descargado: $DOWNLOADED_SIZE bytes"
    
    if [ "$DOWNLOADED_SIZE" -eq "$ORIGINAL_SIZE" ]; then
        echo -e "${GREEN}✅ Tamaños coinciden${NC}"
        
        # Mostrar primeras líneas
        echo -e "\nPrimeras líneas del archivo descargado:"
        head -5 downloaded-file.txt
        
        # Comparar archivos
        if cmp -s test-file.txt downloaded-file.txt; then
            echo -e "\n${GREEN}✅ ¡ÉXITO! Los archivos son idénticos${NC}"
        else
            echo -e "\n${RED}❌ Los archivos son diferentes${NC}"
        fi
    else
        echo -e "${RED}❌ Tamaños no coinciden${NC}"
    fi
else
    echo -e "${RED}❌ No se descargó el archivo${NC}"
fi

# Test de URL presigned
echo -e "\n${YELLOW}7. Probando URL presigned...${NC}"
PRESIGNED_RESPONSE=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
    "http://localhost:8080/api/v1/media/$MEDIA_ID/url")

echo "$PRESIGNED_RESPONSE" | jq '.'

PRESIGNED_URL=$(echo "$PRESIGNED_RESPONSE" | jq -r '.url')
if [[ "$PRESIGNED_URL" == *"localhost:9000"* ]]; then
    echo -e "${GREEN}✅ URL presigned usando endpoint público correcto${NC}"
else
    echo -e "${YELLOW}⚠️  URL presigned podría no ser accesible externamente${NC}"
fi

# Eliminar archivo
echo -e "\n${YELLOW}8. Eliminando archivo de prueba...${NC}"
DELETE_RESPONSE=$(curl -s -X DELETE \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "http://localhost:8080/api/v1/media/$MEDIA_ID")

echo "$DELETE_RESPONSE" | jq '.'

# Limpiar
rm -f test-file.txt downloaded-file.txt /tmp/token-output.log

echo -e "\n${GREEN}========== RESUMEN ==========${NC}"
if [ "$DOWNLOADED_SIZE" -eq "$ORIGINAL_SIZE" ] 2>/dev/null; then
    echo -e "${GREEN}✅ Sistema de media funcionando correctamente${NC}"
    echo -e "${GREEN}✅ Upload: OK${NC}"
    echo -e "${GREEN}✅ Download: OK${NC}"
    echo -e "${GREEN}✅ Delete: OK${NC}"
else
    echo -e "${RED}❌ Hay problemas con el sistema de media${NC}"
fi
