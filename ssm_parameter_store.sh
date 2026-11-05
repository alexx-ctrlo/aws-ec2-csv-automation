# ---------------------------------------------------------
# 1. CREACIÓ D'UN PARÀMETRE SEGUR A PARAMETER STORE - ALEX ARJONA LÓPEZ
# ---------------------------------------------------------
echo -e "\n---> [PAS 1/4] Creant un paràmetre al Parameter Store..."
aws ssm put-parameter \
    --name "/app/db_password" \
    --value "SuperSecretPass2026!" \
    --type "SecureString" \
    --overwrite

# ---------------------------------------------------------
# 2. LLISTAT DE PARÀMETRES CREATS SOTA EL CAMÍ /app
# ---------------------------------------------------------
echo -e "\n---> [PAS 2/4] Llistant els paràmetres existents:"
aws ssm get-parameters-by-path \
    --path "/app" \
    --output table

# ---------------------------------------------------------
# 3. LECTURA I DESXIFRAT DEL PARÀMETRE
# ---------------------------------------------------------
echo -e "\n---> [PAS 3/4] Obtinguent el valor desxifrat del paràmetre:"
aws ssm get-parameter \
    --name "/app/db_password" \
    --with-decryption \
    --query "Parameter.[Name,Type,Value]" \
    --output table

# ---------------------------------------------------------
# 4. NETEJA DE RECURSOS (ELIMINACIÓ DEL PARÀMETRE)
# ---------------------------------------------------------
echo -e "\n---> [PAS 4/4] Eliminant el paràmetre de prova..."
aws ssm delete-parameter \
    --name "/app/db_password"

echo -e "\n=========================================================="
echo "   EXERCICI 1.8 COMPLETAT I RECURSOS NETEJATS             "
echo "=========================================================="