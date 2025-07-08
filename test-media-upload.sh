#!/bin/bash

echo "🧪 Probando sistema de media upload..."

# 1. Obtener token fresco
echo -e "\n1. Obteniendo token de autenticación..."
./get-fresh-token-complete.sh

# Cargar token
source /tmp/fresh-websocket-tokens.txt

if [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ No se pudo obtener token"
    exit 1
fi

echo "✅ Token obtenido"

# 2. Crear archivo de prueba (imagen simulada)
echo -e "\n2. Creando archivo de prueba..."
# Crear una imagen PNG simple de 1x1 pixel
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x00\x00\x00\x00IEND\xaeB`\x82' > test-image.png
echo "✅ Archivo test-image.png creado"

# 3. Subir archivo
echo -e "\n3. Subiendo archivo..."
UPLOAD_RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/media/upload \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@test-image.png;type=image/png")

echo "Respuesta:"
echo "$UPLOAD_RESPONSE" | jq '.'

# Extraer ID del archivo subido
MEDIA_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.id')

if [ "$MEDIA_ID" != "null" ] && [ -n "$MEDIA_ID" ]; then
    echo "✅ Archivo subido exitosamente. ID: $MEDIA_ID"
    
    # 4. Verificar que podemos obtener el archivo
    echo -e "\n4. Verificando descarga del archivo..."
    DOWNLOAD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      "http://localhost:8080/api/v1/media/$MEDIA_ID")
    
    if [ "$DOWNLOAD_STATUS" == "200" ]; then
        echo "✅ Archivo descargado correctamente"
    else
        echo "❌ Error al descargar archivo. Status: $DOWNLOAD_STATUS"
    fi
    
    # 5. Agregar a galería
    echo -e "\n5. Agregando archivo a galería..."
    GALLERY_RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/gallery/media \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"media_id\": \"$MEDIA_ID\"}")
    
    echo "$GALLERY_RESPONSE" | jq '.'
    
    # 6. Ver galería
    echo -e "\n6. Obteniendo galería..."
    curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
      http://localhost:8080/api/v1/gallery | jq '.'
    
    # 7. Limpiar - eliminar archivo
    echo -e "\n7. Eliminando archivo de prueba..."
    DELETE_RESPONSE=$(curl -s -X DELETE \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      "http://localhost:8080/api/v1/media/$MEDIA_ID")
    
    echo "$DELETE_RESPONSE" | jq '.'
    
else
    echo "❌ Error al subir archivo"
fi

# 8. Limpiar archivo local
rm -f test-image.png

echo -e "\n✅ Prueba completada!"