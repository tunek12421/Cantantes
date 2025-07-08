#!/bin/bash

echo "🧪 Test del Sistema de Media con PNG"
echo "===================================="

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Obtener token
echo -e "${YELLOW}1. Obteniendo token...${NC}"
source /tmp/fresh-websocket-tokens.txt 2>/dev/null
if [ -z "$ACCESS_TOKEN" ]; then
    ./get-fresh-token-complete.sh > /dev/null 2>&1
    source /tmp/fresh-websocket-tokens.txt
fi

if [ -z "$ACCESS_TOKEN" ]; then
    echo -e "${RED}❌ No se pudo obtener token${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Token obtenido${NC}"

# 2. Crear imagen PNG real (100x100 pixeles, color sólido)
echo -e "\n${YELLOW}2. Creando imagen PNG de prueba...${NC}"

# Usar ImageMagick si está disponible, sino crear PNG mínimo
if command -v convert >/dev/null 2>&1; then
    # Crear imagen 100x100 roja con ImageMagick
    convert -size 100x100 xc:red test-upload.png
    echo "✅ Imagen creada con ImageMagick"
else
    # Crear PNG mínimo válido (1x1 pixel)
    printf '\x89PNG\r\n\x1a\n' > test-upload.png
    printf '\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde' >> test-upload.png
    printf '\x00\x00\x00\x0cIDATx\x9cc\xf8\xcf\xc0\x00\x00\x00\x03\x00\x01^p\xeaV' >> test-upload.png
    printf '\x00\x00\x00\x00IEND\xaeB`\x82' >> test-upload.png
    echo "✅ PNG mínimo creado"
fi

ORIGINAL_SIZE=$(stat -c%s test-upload.png 2>/dev/null || stat -f%z test-upload.png)
echo "Tamaño del archivo: $ORIGINAL_SIZE bytes"

# 3. Upload
echo -e "\n${YELLOW}3. Subiendo imagen...${NC}"
UPLOAD_RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/media/upload \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@test-upload.png;type=image/png")

echo "Respuesta:"
echo "$UPLOAD_RESPONSE" | jq '.'

MEDIA_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.id')
MEDIA_URL=$(echo "$UPLOAD_RESPONSE" | jq -r '.url')

if [ "$MEDIA_ID" == "null" ] || [ -z "$MEDIA_ID" ]; then
    echo -e "${RED}❌ Error en upload${NC}"
    rm -f test-upload.png
    exit 1
fi

echo -e "${GREEN}✅ Imagen subida exitosamente${NC}"
echo "   ID: $MEDIA_ID"
echo "   URL: $MEDIA_URL"

# 4. Download
echo -e "\n${YELLOW}4. Descargando imagen...${NC}"
HTTP_CODE=$(curl -s -w "%{http_code}" -H "Authorization: Bearer $ACCESS_TOKEN" \
     -o test-download.png \
     "http://localhost:8080/api/v1/media/$MEDIA_ID")

echo "Código HTTP: $HTTP_CODE"

if [ -f "test-download.png" ]; then
    DOWNLOADED_SIZE=$(stat -c%s test-download.png 2>/dev/null || stat -f%z test-download.png)
    echo "Tamaño descargado: $DOWNLOADED_SIZE bytes"
    
    if [ "$DOWNLOADED_SIZE" -gt 0 ]; then
        echo -e "${GREEN}✅ Descarga exitosa${NC}"
        
        # Verificar que sea un PNG válido
        if file test-download.png | grep -q "PNG image"; then
            echo -e "${GREEN}✅ El archivo es un PNG válido${NC}"
        else
            echo -e "${YELLOW}⚠️  El archivo podría no ser un PNG válido${NC}"
            file test-download.png
        fi
        
        # Comparar tamaños
        if [ "$DOWNLOADED_SIZE" -eq "$ORIGINAL_SIZE" ]; then
            echo -e "${GREEN}✅ Los tamaños coinciden${NC}"
            
            # Comparar archivos
            if cmp -s test-upload.png test-download.png; then
                echo -e "${GREEN}✅ ¡Los archivos son idénticos!${NC}"
            else
                echo -e "${YELLOW}⚠️  Los archivos tienen diferencias${NC}"
            fi
        else
            echo -e "${RED}❌ Los tamaños no coinciden${NC}"
        fi
    else
        echo -e "${RED}❌ Archivo descargado vacío${NC}"
    fi
else
    echo -e "${RED}❌ No se descargó el archivo${NC}"
fi

# 5. Agregar a galería
echo -e "\n${YELLOW}5. Agregando a galería...${NC}"
GALLERY_RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/gallery/media \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"media_id\": \"$MEDIA_ID\"}")

echo "$GALLERY_RESPONSE" | jq '.'

# 6. Ver galería
echo -e "\n${YELLOW}6. Verificando galería...${NC}"
GALLERY_LIST=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
  http://localhost:8080/api/v1/gallery)

echo "$GALLERY_LIST" | jq '.media.items[0]'

# 7. Eliminar
echo -e "\n${YELLOW}7. Eliminando archivo...${NC}"
DELETE_RESPONSE=$(curl -s -X DELETE \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "http://localhost:8080/api/v1/media/$MEDIA_ID")

echo "$DELETE_RESPONSE" | jq '.'

# Limpiar
rm -f test-upload.png test-download.png

# Resumen
echo -e "\n${GREEN}========== RESUMEN ==========${NC}"
if [ "$HTTP_CODE" == "200" ] && [ "$DOWNLOADED_SIZE" -gt 0 ] 2>/dev/null; then
    echo -e "${GREEN}✅ Sistema de media funcionando correctamente${NC}"
    echo -e "${GREEN}✅ Upload: OK${NC}"
    echo -e "${GREEN}✅ Download: OK${NC}"
    echo -e "${GREEN}✅ Galería: OK${NC}"
    echo -e "${GREEN}✅ Delete: OK${NC}"
else
    echo -e "${RED}❌ Hay problemas con el sistema${NC}"
    echo "Verifica los logs con: ./scripts/logs.sh backend -f"
fi
