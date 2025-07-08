#!/bin/bash

echo "Corrigiendo error de comillas..."

# Corregir las comillas mal escapadas en handlers.go
sed -i 's/fmt.Sprintf("inline; filename="%s"", media.OriginalFilename)/fmt.Sprintf("inline; filename=\\"%s\\"", media.OriginalFilename)/g' src/internal/media/handlers.go

echo "✅ Corregido"

# Verificar compilación
cd src
if go build -o /tmp/test ./cmd/server; then
    echo "✅ Compila correctamente"
    rm -f /tmp/test
else
    echo "❌ Aún hay errores"
    exit 1
fi
