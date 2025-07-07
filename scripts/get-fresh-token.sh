#!/bin/bash

# Script para obtener un token JWT fresco

echo "🔑 Obteniendo token JWT fresco..."

# 1. Solicitar OTP
echo -e "\n1. Solicitando OTP..."
curl -s -X POST http://localhost:8080/api/v1/auth/request-otp \
  -H "Content-Type: application/json" \
  -d '{"phone_number": "+1234567890"}' | jq '.'

# Ver logs para el OTP
echo -e "\n2. Buscando OTP en logs..."
docker logs chat_backend --tail 20 | grep "MOCK SMS" | tail -1

echo -e "\nIngresa el OTP de 6 dígitos: "
read OTP

# 3. Verificar OTP y obtener tokens
echo -e "\n3. Verificando OTP..."
RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/auth/verify-otp \
  -H "Content-Type: application/json" \
  -d "{
    \"phone_number\": \"+1234567890\",
    \"otp\": \"$OTP\",
    \"device_id\": \"test-device-$(date +%s)\",
    \"device_name\": \"Test Device\",
    \"public_key\": \"test-public-key\"
  }")

echo "$RESPONSE" | jq '.'

# Extraer tokens
ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')
USER_ID=$(echo "$RESPONSE" | jq -r '.user_id')

if [ "$ACCESS_TOKEN" != "null" ] && [ -n "$ACCESS_TOKEN" ]; then
    echo -e "\n✅ Token obtenido exitosamente!"
    echo -e "\n📋 Comandos para probar:"
    echo ""
    echo "# Verificar token con endpoint protegido:"
    echo "curl -H \"Authorization: Bearer $ACCESS_TOKEN\" http://localhost:8080/api/v1/users/me | jq '.'"
    echo ""
    echo "# Probar WebSocket:"
    echo "wscat -c \"ws://localhost:8080/ws?token=$ACCESS_TOKEN\""
    echo ""
    echo "# Ver stats:"
    echo "curl -H \"Authorization: Bearer $ACCESS_TOKEN\" http://localhost:8080/api/v1/ws/stats | jq '.'"
    echo ""
    echo "ACCESS_TOKEN=$ACCESS_TOKEN" > /tmp/fresh-token.txt
    echo "USER_ID=$USER_ID" >> /tmp/fresh-token.txt
    echo ""
    echo "Token guardado en: /tmp/fresh-token.txt"
else
    echo -e "\n❌ Error obteniendo token"
fi