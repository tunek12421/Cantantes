#!/bin/bash

echo "🔍 Diagnosticando sistema de media..."

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Verificar archivos en la base de datos
echo -e "\n${YELLOW}1. Archivos en la base de datos:${NC}"
./scripts/shell.sh postgres -c "
SELECT id, filename, size_bytes, created_at 
FROM gallery_media 
ORDER BY created_at DESC 
LIMIT 5;" 2>/dev/null

# 2. Verificar archivos en MinIO
echo -e "\n${YELLOW}2. Verificando MinIO:${NC}"
docker exec chat_minio mc alias set local http://localhost:9000 chat_minio_admin \
    "$(grep MINIO_ROOT_PASSWORD docker/.env | cut -d'=' -f2)" 2>/dev/null

echo "Buckets disponibles:"
docker exec chat_minio mc ls local 2>/dev/null || echo "Error al listar buckets"

echo -e "\nArchivos en chat-media:"
docker exec chat_minio mc ls local/chat-media --recursive 2>/dev/null | head -10 || echo "No hay archivos o error"

# 3. Test de upload y descarga directo
echo -e "\n${YELLOW}3. Test directo de upload/descarga:${NC}"

# Obtener token
source /tmp/fresh-websocket-tokens.txt 2>/dev/null
if [ -z "$ACCESS_TOKEN" ]; then
    echo "Obteniendo token nuevo..."
    ./get-fresh-token-complete.sh > /dev/null 2>&1
    source /tmp/fresh-websocket-tokens.txt
fi

# Crear archivo de prueba más grande
echo -e "\nCreando archivo de prueba con contenido real..."
echo "Este es un archivo de prueba para Chat E2EE" > test-content.txt
echo "Fecha: $(date)" >> test-content.txt
echo "Contenido de prueba con múltiples líneas" >> test-content.txt
for i in {1..10}; do
    echo "Línea $i: Lorem ipsum dolor sit amet, consectetur adipiscing elit." >> test-content.txt
done

# Upload
echo "Subiendo archivo de texto..."
UPLOAD_RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/media/upload \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@test-content.txt;type=text/plain")

echo "$UPLOAD_RESPONSE" | jq '.'

MEDIA_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.id')

if [ "$MEDIA_ID" != "null" ] && [ -n "$MEDIA_ID" ]; then
    # Esperar un momento
    sleep 1
    
    # Intentar descarga con curl verbose
    echo -e "\n${YELLOW}4. Descargando con curl (verbose):${NC}"
    curl -v -H "Authorization: Bearer $ACCESS_TOKEN" \
         -o downloaded-test.txt \
         "http://localhost:8080/api/v1/media/$MEDIA_ID" 2>&1 | grep -E "(< HTTP|Content-Length|Content-Type)"
    
    if [ -f "downloaded-test.txt" ]; then
        echo -e "\nContenido descargado:"
        echo "Tamaño: $(stat -c%s downloaded-test.txt 2>/dev/null || stat -f%z downloaded-test.txt 2>/dev/null) bytes"
        echo "Primeras líneas:"
        head -3 downloaded-test.txt
        
        # Comparar archivos
        if cmp -s test-content.txt downloaded-test.txt; then
            echo -e "${GREEN}✅ Archivos idénticos${NC}"
        else
            echo -e "${RED}❌ Archivos diferentes${NC}"
        fi
    else
        echo -e "${RED}❌ No se creó el archivo descargado${NC}"
    fi
    
    # Verificar en MinIO directamente
    echo -e "\n${YELLOW}5. Verificando archivo en MinIO:${NC}"
    FILENAME=$(echo "$UPLOAD_RESPONSE" | jq -r '.url' | sed 's|/api/v1/media/||')
    echo "Buscando: $FILENAME"
    docker exec chat_minio mc stat local/chat-media/"$FILENAME" 2>&1 | grep -E "(Name|Size|Type)" || echo "Archivo no encontrado en MinIO"
    
    # Limpiar
    echo -e "\n${YELLOW}6. Limpiando...${NC}"
    DELETE_RESPONSE=$(curl -s -X DELETE \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      "http://localhost:8080/api/v1/media/$MEDIA_ID")
    echo "Respuesta de eliminación: $DELETE_RESPONSE"
fi

# Limpiar archivos locales
rm -f test-content.txt downloaded-test.txt

echo -e "\n${GREEN}Diagnóstico completado${NC}"
