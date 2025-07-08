#!/bin/bash

# Script completo para corregir el sistema de descarga de media

echo "🔧 Corrección completa del sistema de Media"
echo "==========================================="

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Primero, corregir manualmente el archivo handlers.go
echo -e "${YELLOW}1. Corrigiendo handlers.go manualmente...${NC}"

# Crear backup
cp src/internal/media/handlers.go src/internal/media/handlers.go.backup-$(date +%Y%m%d_%H%M%S)

# Crear versión corregida del GetFile
cat > /tmp/fix_getfile.py << 'PYTHON'
import re

# Leer el archivo
with open('src/internal/media/handlers.go', 'r') as f:
    content = f.read()

# Buscar la función GetFile completa
getfile_start = content.find('func (h *Handler) GetFile(')
if getfile_start == -1:
    print("ERROR: No se encontró GetFile")
    exit(1)

# Encontrar el final de la función
brace_count = 0
i = getfile_start
while i < len(content):
    if content[i] == '{':
        brace_count += 1
    elif content[i] == '}':
        brace_count -= 1
        if brace_count == 0:
            getfile_end = i + 1
            break
    i += 1

# Reemplazar la función completa con una versión correcta
new_getfile = '''func (h *Handler) GetFile(c *fiber.Ctx) error {
	mediaID := c.Params("id")
	userID := c.Locals("userID").(string)

	// Get file from service
	media, reader, err := h.service.GetFile(c.Context(), mediaID, userID)
	if err != nil {
		if err == ErrMediaNotFound {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "Media not found",
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to retrieve file",
		})
	}
	defer reader.Close()

	// Set headers
	c.Set("Content-Type", media.MimeType)
	c.Set("Content-Length", strconv.FormatInt(media.Size, 10))
	c.Set("Content-Disposition", fmt.Sprintf("inline; filename=\"%s\"", media.OriginalFilename))

	// Read and send file content
	data, err := io.ReadAll(reader)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to read file",
		})
	}

	// Send the file data
	return c.Send(data)
}'''

# Reemplazar en el contenido
new_content = content[:getfile_start] + new_getfile + content[getfile_end:]

# Guardar
with open('src/internal/media/handlers.go', 'w') as f:
    f.write(new_content)

print("✅ GetFile corregido exitosamente")
PYTHON

python3 /tmp/fix_getfile.py

# 2. También corregir el problema en service.go DeleteFile
echo -e "\n${YELLOW}2. Corrigiendo service.go...${NC}"

cat > /tmp/fix_service.py << 'PYTHON'
import re

# Leer el archivo
with open('src/internal/media/service.go', 'r') as f:
    content = f.read()

# Corregir la query mal formateada en DeleteFile
bad_query = '''query := `SELECT filename FROM gallery_media WHERE id = $1 --
		SELECT id FROM model_galleries WHERE model_id = $2
	)`'''

good_query = '''query := `SELECT filename FROM gallery_media WHERE id = $1`'''

content = content.replace(bad_query, good_query)

# También corregir la línea del Scan
content = re.sub(r'err := s\.db\.QueryRowContext\(ctx, query, mediaID, userID\)\.Scan\(&filename\)',
                 'err := s.db.QueryRowContext(ctx, query, mediaID).Scan(&filename)',
                 content)

# Guardar
with open('src/internal/media/service.go', 'w') as f:
    f.write(content)

print("✅ service.go corregido")
PYTHON

python3 /tmp/fix_service.py

# 3. Verificar que las correcciones se aplicaron
echo -e "\n${YELLOW}3. Verificando correcciones...${NC}"
echo "GetFile function (últimas 15 líneas):"
awk '/func \(h \*Handler\) GetFile/,/^}/' src/internal/media/handlers.go | tail -15

# 4. Compilar para verificar sintaxis
echo -e "\n${YELLOW}4. Verificando compilación...${NC}"
cd src
if go build -o /tmp/test-compile ./cmd/server 2>&1; then
    echo -e "${GREEN}✅ Compilación exitosa${NC}"
    rm -f /tmp/test-compile
else
    echo -e "${RED}❌ Error de compilación${NC}"
    cd ..
    exit 1
fi
cd ..

# 5. Rebuild y restart
echo -e "\n${YELLOW}5. Rebuilding backend...${NC}"
cd docker
docker-compose build backend
docker-compose restart backend
cd ..

# 6. Esperar a que esté listo
echo -e "\n${YELLOW}6. Esperando servicio...${NC}"
for i in {1..30}; do
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Servicio listo!${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

# 7. Obtener token NUEVO (el anterior expiró)
echo -e "\n${YELLOW}7. Obteniendo token nuevo...${NC}"
./get-fresh-token-complete.sh > /tmp/fresh-token.log 2>&1
source /tmp/fresh-websocket-tokens.txt

if [ -z "$ACCESS_TOKEN" ]; then
    echo -e "${RED}❌ No se pudo obtener token${NC}"
    cat /tmp/fresh-token.log | tail -20
    exit 1
fi
echo -e "${GREEN}✅ Token obtenido${NC}"

# 8. Test completo
echo -e "\n${YELLOW}8. Test completo de upload/download...${NC}"

# Crear imagen PNG válida
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\xcf\xc0\x00\x00\x00\x03\x00\x01^p\xeaV\x00\x00\x00\x00IEND\xaeB`\x82' > test.png

# Upload
echo "Subiendo archivo PNG..."
UPLOAD_RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/media/upload \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@test.png;type=image/png")

echo "$UPLOAD_RESPONSE" | jq '.'

MEDIA_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.id')
FILENAME=$(echo "$UPLOAD_RESPONSE" | jq -r '.url' | sed 's|/api/v1/media/||')

if [ "$MEDIA_ID" != "null" ] && [ -n "$MEDIA_ID" ]; then
    echo -e "${GREEN}✅ Upload exitoso: $MEDIA_ID${NC}"
    
    # Pequeña pausa
    sleep 1
    
    # Test descarga con diferentes métodos
    echo -e "\n${YELLOW}Test 1: curl con output file...${NC}"
    HTTP_CODE=$(curl -s -w "%{http_code}" -H "Authorization: Bearer $ACCESS_TOKEN" \
         -o downloaded.png \
         "http://localhost:8080/api/v1/media/$MEDIA_ID")
    
    echo "HTTP Code: $HTTP_CODE"
    
    if [ -f "downloaded.png" ]; then
        SIZE=$(stat -c%s downloaded.png 2>/dev/null || stat -f%z downloaded.png)
        echo "Archivo descargado: $SIZE bytes"
        
        # Verificar que es un PNG válido
        if file downloaded.png | grep -q "PNG image"; then
            echo -e "${GREEN}✅ ¡DESCARGA EXITOSA! El archivo es un PNG válido${NC}"
        else
            echo -e "${YELLOW}⚠️  Archivo descargado pero podría estar corrupto${NC}"
            hexdump -C downloaded.png | head -3
        fi
    else
        echo -e "${RED}❌ No se creó el archivo${NC}"
        
        # Diagnóstico adicional
        echo -e "\n${YELLOW}Diagnóstico adicional:${NC}"
        echo "Verificando en MinIO:"
        docker exec chat_minio mc stat local/chat-media/"$FILENAME" 2>&1 | grep -E "(Name|Size|Type)"
        
        echo -e "\nÚltimos logs del backend:"
        ./scripts/logs.sh backend --tail 10 | grep -E "(GetFile|error|ERROR)"
    fi
    
    # Test con wget también
    echo -e "\n${YELLOW}Test 2: wget...${NC}"
    wget -q --header="Authorization: Bearer $ACCESS_TOKEN" \
         -O downloaded2.png \
         "http://localhost:8080/api/v1/media/$MEDIA_ID"
    
    if [ -f "downloaded2.png" ]; then
        SIZE2=$(stat -c%s downloaded2.png 2>/dev/null || stat -f%z downloaded2.png)
        echo "wget descargó: $SIZE2 bytes"
    fi
    
    # Limpiar
    echo -e "\n${YELLOW}9. Limpiando...${NC}"
    curl -s -X DELETE -H "Authorization: Bearer $ACCESS_TOKEN" \
        "http://localhost:8080/api/v1/media/$MEDIA_ID" > /dev/null
fi

# Limpiar archivos temporales
rm -f test.png downloaded.png downloaded2.png /tmp/fix_*.py /tmp/fresh-token.log

echo -e "\n${GREEN}========== CORRECCIÓN COMPLETADA ==========${NC}"
echo "Si la descarga sigue sin funcionar, revisa:"
echo "1. ./scripts/logs.sh backend -f"
echo "2. docker logs chat_minio"
echo "3. Verificar que MinIO esté accesible en http://localhost:9000"
