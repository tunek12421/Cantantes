#!/bin/bash

echo "🔍 Diagnóstico del Problema de Descarga"
echo "======================================="

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Ver logs del backend
echo -e "${YELLOW}1. Últimos logs del backend:${NC}"
./scripts/logs.sh backend --tail 20 | grep -E "(GetFile|media|error|ERROR)" || echo "No se encontraron errores relevantes"

# 2. Verificar que el cambio de SendStream se aplicó
echo -e "\n${YELLOW}2. Verificando código de GetFile:${NC}"
echo "Buscando SendStream en handlers.go:"
grep -n "SendStream\|Send(" src/internal/media/handlers.go | head -5

# 3. Verificar imports
echo -e "\n${YELLOW}3. Verificando imports en handlers.go:${NC}"
grep -E "^import|\"io\"|\"fmt\"" src/internal/media/handlers.go | head -20

# 4. Test directo con curl verbose
echo -e "\n${YELLOW}4. Test directo de descarga con curl verbose:${NC}"

# Obtener token
source /tmp/fresh-websocket-tokens.txt 2>/dev/null
if [ -z "$ACCESS_TOKEN" ]; then
    echo "Obteniendo token nuevo..."
    ./get-fresh-token-complete.sh > /dev/null 2>&1
    source /tmp/fresh-websocket-tokens.txt
fi

# Crear y subir archivo pequeño
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\xcf\xc0\x00\x00\x00\x03\x00\x01^p\xeaV\x00\x00\x00\x00IEND\xaeB`\x82' > test-debug.png

UPLOAD_RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/media/upload \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@test-debug.png;type=image/png")

MEDIA_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.id')

if [ "$MEDIA_ID" != "null" ] && [ -n "$MEDIA_ID" ]; then
    echo "Archivo subido con ID: $MEDIA_ID"
    echo -e "\nIntentando descarga con curl -v:"
    
    # Intento 1: Con curl verbose
    curl -v -H "Authorization: Bearer $ACCESS_TOKEN" \
         "http://localhost:8080/api/v1/media/$MEDIA_ID" 2>&1 | grep -E "(< HTTP|< Content|Connected|curl)"
    
    echo -e "\n${YELLOW}5. Verificando el archivo en MinIO:${NC}"
    FILENAME=$(echo "$UPLOAD_RESPONSE" | jq -r '.url' | sed 's|/api/v1/media/||')
    docker exec chat_minio mc stat local/chat-media/"$FILENAME" 2>&1 | grep -E "(Name|Size|Type)" || echo "Archivo no encontrado"
    
    # Limpiar
    curl -s -X DELETE -H "Authorization: Bearer $ACCESS_TOKEN" \
        "http://localhost:8080/api/v1/media/$MEDIA_ID" > /dev/null
fi

rm -f test-debug.png

echo -e "\n${YELLOW}6. Contenido actual de GetFile (primeras 20 líneas de la función):${NC}"
awk '/func \(h \*Handler\) GetFile/,/^}/' src/internal/media/handlers.go | head -30
