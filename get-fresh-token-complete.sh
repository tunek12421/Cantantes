#!/bin/bash

echo "🔑 Obteniendo token fresco para WebSocket"
echo "========================================"

# 1. Limpiar rate limiting anterior si existe
echo -e "\n1. Limpiando rate limiting..."
./scripts/shell.sh redis DEL "otp_attempts:attempts:+1234567890" > /dev/null 2>&1

# 2. Solicitar OTP
echo -e "\n2. Solicitando OTP..."
OTP_RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/auth/request-otp \
  -H "Content-Type: application/json" \
  -d '{"phone_number": "+1234567890"}')

echo "$OTP_RESPONSE" | jq '.'

# 3. Buscar OTP en los logs
echo -e "\n3. Buscando OTP en logs..."
sleep 1
OTP=$(docker logs chat_backend --tail 20 2>&1 | grep "MOCK SMS" | tail -1 | grep -oE '[0-9]{6}' | tail -1)

if [ -z "$OTP" ]; then
    echo "No se encontró el OTP automáticamente."
    echo "Busca en los logs el mensaje: [MOCK SMS] To: +1234567890, Message: Your Chat E2EE verification code is: XXXXXX"
    echo ""
    docker logs chat_backend --tail 10 | grep -i "mock\|otp"
    echo ""
    echo -n "Ingresa el OTP de 6 dígitos: "
    read OTP
else
    echo "✅ OTP encontrado: $OTP"
fi

# 4. Verificar OTP
echo -e "\n4. Verificando OTP..."
DEVICE_ID="test-device-$(date +%s)"
VERIFY_RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/auth/verify-otp \
  -H "Content-Type: application/json" \
  -d "{
    \"phone_number\": \"+1234567890\",
    \"otp\": \"$OTP\",
    \"device_id\": \"$DEVICE_ID\",
    \"device_name\": \"Test WebSocket Device\",
    \"public_key\": \"test-public-key-base64\"
  }")

echo "$VERIFY_RESPONSE" | jq '.'

# 5. Extraer tokens
ACCESS_TOKEN=$(echo "$VERIFY_RESPONSE" | jq -r '.access_token')
REFRESH_TOKEN=$(echo "$VERIFY_RESPONSE" | jq -r '.refresh_token')
USER_ID=$(echo "$VERIFY_RESPONSE" | jq -r '.user_id')

if [ "$ACCESS_TOKEN" != "null" ] && [ -n "$ACCESS_TOKEN" ]; then
    # 6. Guardar tokens
    cat > /tmp/fresh-websocket-tokens.txt << EOF
# Fresh tokens for WebSocket - $(date)
export ACCESS_TOKEN="$ACCESS_TOKEN"
export REFRESH_TOKEN="$REFRESH_TOKEN"
export USER_ID="$USER_ID"
export DEVICE_ID="$DEVICE_ID"
EOF
    
    echo -e "\n✅ Token obtenido exitosamente!"
    echo "Tokens guardados en: /tmp/fresh-websocket-tokens.txt"
    
    # 7. Verificar que el token funciona
    echo -e "\n5. Verificando token con endpoint protegido..."
    curl -s -H "Authorization: Bearer $ACCESS_TOKEN" http://localhost:8080/api/v1/users/me | jq '.'
    
    # 8. Verificar WebSocket stats
    echo -e "\n6. Verificando WebSocket stats..."
    curl -s -H "Authorization: Bearer $ACCESS_TOKEN" http://localhost:8080/api/v1/ws/stats | jq '.'
    
    echo -e "\n📋 COMANDOS PARA PROBAR WEBSOCKET:"
    echo "=================================="
    echo ""
    echo "1. Cargar el token fresco:"
    echo "   source /tmp/fresh-websocket-tokens.txt"
    echo ""
    echo "2. Conectar al WebSocket:"
    echo "   wscat -c \"ws://localhost:8080/ws?token=\$ACCESS_TOKEN\""
    echo ""
    echo "3. Una vez conectado, envía:"
    echo '   {"type":"ping"}'
    echo ""
    echo "4. Para enviar un mensaje a otro usuario:"
    echo '   {"type":"message","to":"USER_ID","payload":"SGVsbG8gV29ybGQh"}'
    echo ""
    echo "Token directo (si prefieres copiar/pegar):"
    echo "wscat -c \"ws://localhost:8080/ws?token=$ACCESS_TOKEN\""
    
else
    echo -e "\n❌ Error obteniendo token"
    echo "Respuesta completa:"
    echo "$VERIFY_RESPONSE"
fi