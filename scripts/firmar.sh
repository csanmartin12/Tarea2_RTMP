#!/bin/bash
# Genera la firma que exige Node-Media-Server cuando auth.publish / auth.play están activos.
# Uso: ./scripts/firmar.sh /live/test [segundos_de_validez] [secret]
# Formato: <expiración>-<md5("<ruta>-<expiración>-<secret>")>
RUTA="${1:-/live/test}"
VALIDEZ="${2:-3600}"
SECRET="${3:-tallerredes2026}"
EXP=$(( $(date +%s) + VALIDEZ ))
HASH=$(printf "%s" "$RUTA-$EXP-$SECRET" | md5sum | cut -d' ' -f1)
echo "$EXP-$HASH"
