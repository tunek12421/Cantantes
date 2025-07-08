#!/bin/bash

echo "TEST SIMPLE DE MEDIA"
echo "==================="

# 1. Obtener token
./get-fresh-token-complete.sh > /dev/null 2>&1
source /tmp/fresh-websocket-tokens.txt

if [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ No se pudo obtener token"
    exit 1
fi
echo "✅ Token obtenido"

# 2. Crear archivo
echo "Prueba $(date)" > test.txt

# 3. Upload
echo -n "Subiendo... "
RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/media/upload \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@test.txt;type=text/plain")

ID=$(echo "$RESPONSE" | jq -r '.id')
if [ "$ID" != "null" ]; then
    echo "✅ ID: $ID"
else
    echo "❌"
    echo "$RESPONSE"
    exit 1
fi

# 4. Download
echo -n "Descargando... "
curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
     -o downloaded.txt \
     "http://localhost:8080/api/v1/media/$ID"

if [ -f "downloaded.txt" ] && [ -s "downloaded.txt" ]; then
    echo "✅"
    echo "Contenido: $(cat downloaded.txt)"
else
    echo "❌"
fi

# 5. Cleanup
curl -s -X DELETE -H "Authorization: Bearer $ACCESS_TOKEN" \
    "http://localhost:8080/api/v1/media/$ID" > /dev/null
rm -f test.txt downloaded.txt

echo "==================="
