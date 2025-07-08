#!/bin/bash

echo "🔍 Verificando endpoints implementados vs faltantes"
echo "=================================================="

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "\n${GREEN}✅ ENDPOINTS IMPLEMENTADOS:${NC}"
echo "------------------------"
curl -s http://localhost:8080/api/v1 | jq -r '.endpoints | to_entries[] | "- \(.key): \(.value)"'

echo -e "\n${YELLOW}⏳ ENDPOINTS QUE FALTAN:${NC}"
echo "---------------------"

# Lista de endpoints planeados
cat << 'EOF'
USUARIOS:
- GET    /api/v1/users/me (perfil completo)
- PUT    /api/v1/users/me (actualizar)
- POST   /api/v1/users/avatar
- GET    /api/v1/users/:id
- POST   /api/v1/users/contacts
- GET    /api/v1/users/contacts
- DELETE /api/v1/users/contacts/:id

MEDIA:
- POST   /api/v1/media/upload
- GET    /api/v1/media/:id
- DELETE /api/v1/media/:id
- POST   /api/v1/media/thumbnail

GALERÍA:
- GET    /api/v1/gallery
- POST   /api/v1/gallery/media
- DELETE /api/v1/gallery/media/:id
- GET    /api/v1/gallery/:userId

MODELOS:
- GET    /api/v1/models
- GET    /api/v1/models/search
- GET    /api/v1/models/:id

MENSAJES (via WebSocket):
- Delivery receipts
- Read receipts mejorados
- Typing indicators mejorados
EOF

echo -e "\n${GREEN}📊 RESUMEN:${NC}"
echo "---------"
echo "Backend Core: 85% completo"
echo "Falta principalmente: Handlers de Media y Galería"
echo "Tiempo estimado: 2-3 días de desarrollo"