#!/bin/bash

echo "TEST CON PNG"
echo "============"

# 1. Token
./get-fresh-token-complete.sh > /dev/null 2>&1
source /tmp/fresh-websocket-tokens.txt
echo "✅ Token obtenido"

# 2. Crear PNG mínimo (1x1 pixel)
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\xcf\xc0\x00\x00\x00\x03\x00\x01^p\xeaV\x00\x00\x00\x00IEND\xaeB`\x82' > test.png

# 3. Upload
echo -n "Subiendo PNG... "
RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/media/upload \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@test.png;type=image/png")

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
     -o down.png \
     "http://localhost:8080/api/v1/media/$ID"

if [ -f "down.png" ] && [ -s "down.png" ]; then
    SIZE=$(stat -c%s down.png 2>/dev/null || stat -f%z down.png)
    echo "✅ ($SIZE bytes)"
else
    echo "❌"
fi

# 5. Cleanup
curl -s -X DELETE -H "Authorization: Bearer $ACCESS_TOKEN" \
    "http://localhost:8080/api/v1/media/$ID" > /dev/null
rm -f test.png down.png
