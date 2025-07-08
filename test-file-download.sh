#!/bin/bash

echo "🧪 Probando descarga de archivos..."

# 1. Cargar token
source /tmp/fresh-websocket-tokens.txt

if [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ No hay token disponible. Ejecuta primero: ./get-fresh-token-complete.sh"
    exit 1
fi

# 2. Crear y subir archivo de prueba
echo -e "\n1. Creando y subiendo archivo de prueba..."
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x00\x00\x00\x00IEND\xaeB`\x82' > test-download.png

UPLOAD_RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/media/upload \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@test-download.png;type=image/png")

MEDIA_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.id')

if [ "$MEDIA_ID" != "null" ] && [ -n "$MEDIA_ID" ]; then
    echo "✅ Archivo subido. ID: $MEDIA_ID"
    
    # 3. Descargar usando wget en lugar de curl
    echo -e "\n2. Descargando archivo con wget..."
    wget -q --header="Authorization: Bearer $ACCESS_TOKEN" \
         -O downloaded-file.png \
         "http://localhost:8080/api/v1/media/$MEDIA_ID"
    
    if [ -f "downloaded-file.png" ]; then
        echo "✅ Archivo descargado exitosamente"
        echo "   Tamaño: $(stat -c%s downloaded-file.png) bytes"
        
        # Verificar que los archivos son idénticos
        if cmp -s test-download.png downloaded-file.png; then
            echo "✅ El archivo descargado es idéntico al original"
        else
            echo "❌ Los archivos no coinciden"
        fi
        
        # Limpiar archivo descargado
        rm -f downloaded-file.png
    else
        echo "❌ Error al descargar archivo"
    fi
    
    # 4. Probar URL presigned
    echo -e "\n3. Obteniendo URL temporal directa..."
    PRESIGNED_RESPONSE=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
        "http://localhost:8080/api/v1/media/$MEDIA_ID/url")
    
    echo "$PRESIGNED_RESPONSE" | jq '.'
    
    # 5. Limpiar
    echo -e "\n4. Eliminando archivo de prueba..."
    curl -s -X DELETE -H "Authorization: Bearer $ACCESS_TOKEN" \
        "http://localhost:8080/api/v1/media/$MEDIA_ID" | jq '.'
    
else
    echo "❌ Error al subir archivo"
fi

# 6. Limpiar archivos locales
rm -f test-download.png

echo -e "\n✅ Prueba completada!"