#!/bin/bash

echo "🔧 Corrigiendo formato de GetFile"
echo "=================================="

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Backup
echo -e "${YELLOW}1. Creando backup...${NC}"
cp src/internal/media/handlers.go src/internal/media/handlers.go.bak-format

# 2. Crear Python script para corregir el formato
echo -e "\n${YELLOW}2. Creando script de corrección...${NC}"
cat > /tmp/fix_format.py << 'PYTHON'
import re

# Leer el archivo
with open('src/internal/media/handlers.go', 'r') as f:
    content = f.read()

# Buscar la línea problemática
pattern = r'data, err := io\.ReadAll\(reader\); if err != nil \{ return c\.Status\(fiber\.StatusInternalServerError\)\.JSON\(fiber\.Map\{"error": "Failed to read file"\}\) \}; return c\.Send\(data\)'

replacement = '''// Read all content
	data, err := io.ReadAll(reader)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to read file",
		})
	}
	
	// Send the data
	return c.Send(data)'''

# Reemplazar
content_new = content.replace(pattern.replace('\\', ''), replacement)

# Guardar
with open('src/internal/media/handlers.go', 'w') as f:
    f.write(content_new)

print("✅ Formato corregido")
PYTHON

python3 /tmp/fix_format.py

# 3. Verificar que se corrigió
echo -e "\n${YELLOW}3. Verificando corrección...${NC}"
echo "Últimas líneas de GetFile:"
awk '/func \(h \*Handler\) GetFile/,/^}/' src/internal/media/handlers.go | tail -15

# 4. Compilar para verificar
echo -e "\n${YELLOW}4. Verificando compilación...${NC}"
cd src
if go build -o /tmp/test-compile ./cmd/server 2>&1; then
    echo -e "${GREEN}✅ Compilación exitosa${NC}"
    rm -f /tmp/test-compile
else
    echo -e "${RED}❌ Error de compilación${NC}"
    go build ./cmd/server 2>&1 | head -20
    cd ..
    exit 1
fi
cd ..

# 5. Rebuild Docker
echo -e "\n${YELLOW}5. Rebuilding Docker...${NC}"
cd docker
docker-compose build backend
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error en Docker build${NC}"
    cd ..
    exit 1
fi

docker-compose restart backend
cd ..

# 6. Esperar
echo -e "\n${YELLOW}6. Esperando a que el servicio esté listo...${NC}"
for i in {1..30}; do
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Servicio listo!${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

# 7. Test de descarga
echo -e "\n${YELLOW}7. Test de descarga...${NC}"

# Obtener token
source /tmp/fresh-websocket-tokens.txt 2>/dev/null
if [ -z "$ACCESS_TOKEN" ]; then
    echo "Obteniendo token nuevo..."
    ./get-fresh-token-complete.sh > /dev/null 2>&1
    source /tmp/fresh-websocket-tokens.txt
fi

# Crear PNG de prueba
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\xcf\xc0\x00\x00\x00\x03\x00\x01^p\xeaV\x00\x00\x00\x00IEND\xaeB`\x82' > test.png

# Upload
echo "Subiendo archivo..."
UPLOAD_RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/media/upload \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@test.png;type=image/png")

MEDIA_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.id')

if [ "$MEDIA_ID" != "null" ] && [ -n "$MEDIA_ID" ]; then
    echo "✅ Upload exitoso: $MEDIA_ID"
    
    # Test descarga con diferentes métodos
    echo -e "\nTest 1: curl con output file..."
    HTTP_CODE=$(curl -s -w "%{http_code}" -H "Authorization: Bearer $ACCESS_TOKEN" \
         -o downloaded.png \
         "http://localhost:8080/api/v1/media/$MEDIA_ID")
    
    echo "HTTP Code: $HTTP_CODE"
    
    if [ -f "downloaded.png" ]; then
        SIZE=$(stat -c%s downloaded.png 2>/dev/null || stat -f%z downloaded.png)
        echo "Tamaño descargado: $SIZE bytes"
        
        if [ "$SIZE" -eq 69 ]; then
            echo -e "${GREEN}✅ ¡DESCARGA FUNCIONANDO CORRECTAMENTE!${NC}"
            
            # Verificar contenido
            if cmp -s test.png downloaded.png; then
                echo -e "${GREEN}✅ Archivos idénticos${NC}"
            else
                echo "⚠️  Archivos diferentes"
            fi
        else
            echo -e "${RED}❌ Tamaño incorrecto${NC}"
        fi
    else
        echo -e "${RED}❌ No se creó el archivo${NC}"
    fi
    
    echo -e "\nTest 2: wget..."
    wget -q --header="Authorization: Bearer $ACCESS_TOKEN" \
         -O downloaded2.png \
         "http://localhost:8080/api/v1/media/$MEDIA_ID"
    
    if [ -f "downloaded2.png" ]; then
        SIZE2=$(stat -c%s downloaded2.png 2>/dev/null || stat -f%z downloaded2.png)
        echo "wget descargó: $SIZE2 bytes"
    fi
    
    # Cleanup
    curl -s -X DELETE -H "Authorization: Bearer $ACCESS_TOKEN" \
        "http://localhost:8080/api/v1/media/$MEDIA_ID" > /dev/null
fi

# Limpiar
rm -f test.png downloaded.png downloaded2.png /tmp/fix_format.py

echo -e "\n${GREEN}========== CORRECCIÓN COMPLETADA ==========${NC}"
