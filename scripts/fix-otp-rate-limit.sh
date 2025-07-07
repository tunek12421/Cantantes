#!/bin/bash

echo "🔧 Solucionando problemas de OTP y tokens..."

# 1. Limpiar rate limiting en Redis
echo -e "\n1. Limpiando rate limiting de OTP en Redis..."
./scripts/shell.sh redis DEL "otp_attempts:attempts:+1234567890"

# 2. Verificar que se limpió
echo -e "\n2. Verificando limpieza..."
./scripts/shell.sh redis GET "otp_attempts:attempts:+1234567890"

# 3. Ahora solicitar OTP
echo -e "\n3. Solicitando nuevo OTP..."
curl -s -X POST http://localhost:8080/api/v1/auth/request-otp \
  -H "Content-Type: application/json" \
  -d '{"phone_number": "+1234567890"}' | jq '.'

# 4. Buscar el OTP en los logs
echo -e "\n4. Buscando OTP en logs..."
OTP=$(docker logs chat_backend --tail 50 2>&1 | grep "MOCK SMS" | tail -1 | grep -oE '[0-9]{6}' | tail -1)

if [ -z "$OTP" ]; then
    echo "❌ No se encontró el OTP. Verifica los logs manualmente:"
    docker logs chat_backend --tail 20 | grep -i "mock\|otp"
    echo -e "\nIngresa el OTP manualmente: "
    read OTP
else
    echo "✅ OTP encontrado: $OTP"
fi

# 5. Verificar OTP
echo -e "\n5. Verificando OTP..."
DEVICE_ID="test-device-$(date +%s)"
RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/auth/verify-otp \
  -H "Content-Type: application/json" \
  -d "{
    \"phone_number\": \"+1234567890\",
    \"otp\": \"$OTP\",
    \"device_id\": \"$DEVICE_ID\",
    \"device_name\": \"Test Device\",
    \"public_key\": \"test-public-key\"
  }")

echo "$RESPONSE" | jq '.'

# 6. Extraer tokens
ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')
REFRESH_TOKEN=$(echo "$RESPONSE" | jq -r '.refresh_token')
USER_ID=$(echo "$RESPONSE" | jq -r '.user_id')

if [ "$ACCESS_TOKEN" != "null" ] && [ -n "$ACCESS_TOKEN" ]; then
    echo -e "\n✅ Token obtenido exitosamente!"
    
    # Guardar tokens
    cat > /tmp/chat-e2ee-tokens.txt << EOTOKEN
# Chat E2EE Test Tokens - $(date)
ACCESS_TOKEN=$ACCESS_TOKEN
REFRESH_TOKEN=$REFRESH_TOKEN
USER_ID=$USER_ID
DEVICE_ID=$DEVICE_ID
EOTOKEN
    
    echo "Tokens guardados en: /tmp/chat-e2ee-tokens.txt"
    
    # 7. Verificar que el token funciona
    echo -e "\n7. Verificando token con endpoint protegido..."
    curl -s -H "Authorization: Bearer $ACCESS_TOKEN" http://localhost:8080/api/v1/users/me | jq '.'
    
    # 8. Verificar WebSocket stats
    echo -e "\n8. Verificando WebSocket stats..."
    curl -s -H "Authorization: Bearer $ACCESS_TOKEN" http://localhost:8080/api/v1/ws/stats | jq '.'
    
    echo -e "\n📋 Comando para probar WebSocket:"
    echo "wscat -c \"ws://localhost:8080/ws?token=$ACCESS_TOKEN\""
    
else
    echo -e "\n❌ Error obteniendo token"
fi
