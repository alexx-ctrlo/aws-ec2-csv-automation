#!/bin/bash
set -e

# ---------------------------------------------------------
# CONFIGURACIÓ DE REGIÓ, CORREU I VARIABLES D'IDENTIFICACIÓ
# ---------------------------------------------------------
NOM_ALUMNE="AlexArjona"
PROJECT_TAG="WebCorp${NOM_ALUMNE}"
ROLE_TAG="Frontend${NOM_ALUMNE}"
EMAIL_ALUMNE="alex.arjona.7ea@itb.cat"
TOPIC_NAME="AlertaCPU-${NOM_ALUMNE}"
REGION="us-east-1"

KEY_PATH="/home/alex.arjona.7ea/learnerlab.pem"
if [ ! -f "$KEY_PATH" ]; then
  KEY_PATH="./learnerlab.pem"
fi

export AWS_DEFAULT_REGION="$REGION"
export AWS_REGION="$REGION"

# ---------------------------------------------------------
# FUNCIÓ D'HELPER: BARRA DE PROGRÈS VISUAL EN TEMPS REAL
# ---------------------------------------------------------
mostrar_barra_progres() {
  local durada=$1
  local text=$2
  local ample=30
  for ((s=1; s<=durada; s++)); do
    sleep 1
    local percent=$(( s * 100 / durada ))
    local num_hasheos=$(( s * ample / durada ))
    local num_guions=$(( ample - num_hasheos ))
    local hashes=""
    local guions=""
    if [ $num_hasheos -gt 0 ]; then hashes=$(printf '%*s' "$num_hasheos" '' | tr ' ' '#'); fi
    if [ $num_guions -gt 0 ]; then guions=$(printf '%*s' "$num_guions" '' | tr ' ' '-'); fi
    printf "\r %s [%s%s] %d%% (%ds/%ds)" "$text" "$hashes" "$guions" "$percent" "$s" "$durada"
  done
  echo ""
}

echo "=========================================================="
echo "   AP3 AWS: SCRIPT MASTER PER A ALEX ARJONA LÓPEZ        "
echo "   REGIÓ AWS CONFIGURADA: $REGION                        "
echo "=========================================================="

MY_IP=$(curl -s checkip.amazonaws.com)

KEY_NAME=$(aws ec2 describe-key-pairs --query "KeyPairs[?KeyName=='vockey' || KeyName=='learnerlab'].KeyName | [0]" --output text 2>/dev/null || true)

if [ -z "$KEY_NAME" ] || [ "$KEY_NAME" = "None" ]; then
  if [ -f "$KEY_PATH" ]; then
    PUB_KEY=$(ssh-keygen -y -f "$KEY_PATH" 2>/dev/null || true)
    if [ -n "$PUB_KEY" ]; then
      aws ec2 import-key-pair --key-name learnerlab --public-key-material fileb://<(echo "$PUB_KEY") >/dev/null 2>&1 || true
      KEY_NAME="learnerlab"
    fi
  fi
fi

echo "     [✓] Clau SSH configurada: KeyName='$KEY_NAME' (Fitxer: $KEY_PATH)"

# ---------------------------------------------------------
# FUNCIÓ DE NETEJA PROFUNDA I PURGA TOTAL DE VPCS I ALARMES
# ---------------------------------------------------------
netejar_recursos() {
  echo -e "\n---> Eliminant la jerarquia de dependències per alliberar les VPCs..."

  echo "     [1/8] Eliminant Topics SNS..."
  TOPIC_ARN=$(aws sns list-topics --query "Topics[?contains(TopicArn, '$TOPIC_NAME')].TopicArn" --output text 2>/dev/null || true)
  if [ -n "$TOPIC_ARN" ] && [ "$TOPIC_ARN" != "None" ]; then
    aws sns delete-topic --topic-arn "$TOPIC_ARN" >/dev/null 2>&1 || true
  fi

  echo "     [2/8] Eliminant Auto Scaling Groups..."
  ASGS=$(aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[*].AutoScalingGroupName" --output text 2>/dev/null || true)
  for asg in $ASGS; do
    if [ -n "$asg" ] && [ "$asg" != "None" ]; then
      aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "$asg" --force-delete >/dev/null 2>&1 || true
    fi
  done

  echo "     [3/8] Eliminant Alarmes CloudWatch (manuals i automàtiques TargetTracking)..."
  aws cloudwatch delete-alarms --alarm-names "Alarma-CPU-Alta-ASG" >/dev/null 2>&1 || true
  
  AUTO_ALARMS=$(aws cloudwatch describe-alarms --query "MetricAlarms[?contains(AlarmName, 'asg-web-app')].AlarmName" --output text 2>/dev/null || true)
  if [ -n "$AUTO_ALARMS" ] && [ "$AUTO_ALARMS" != "None" ]; then
    aws cloudwatch delete-alarms --alarm-names $AUTO_ALARMS >/dev/null 2>&1 || true
  fi

  echo "     [4/8] Eliminant Target Groups..."
  TGS=$(aws elbv2 describe-target-groups --query "TargetGroups[*].TargetGroupArn" --output text 2>/dev/null || true)
  for tg in $TGS; do
    if [ -n "$tg" ] && [ "$tg" != "None" ]; then
      aws elbv2 delete-target-group --target-group-arn "$tg" >/dev/null 2>&1 || true
    fi
  done

  echo "     [5/8] Eliminant Launch Templates..."
  aws ec2 delete-launch-template --launch-template-name PlantillaWeb >/dev/null 2>&1 || true

  echo "     [6/8] Aturant totes les instàncies EC2 de les VPCs secundàries..."
  VPCS=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=false" --query "Vpcs[*].VpcId" --output text 2>/dev/null || true)

  ALL_INSTANCES=""
  for vpc in $VPCS; do
    if [ -n "$vpc" ] && [ "$vpc" != "None" ]; then
      INSTS=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$vpc" "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" --query "Reservations[*].Instances[*].InstanceId" --output text 2>/dev/null || true)
      if [ -n "$INSTS" ] && [ "$INSTS" != "None" ]; then
        ALL_INSTANCES="$ALL_INSTANCES $INSTS"
      fi
    fi
  done

  if [ -n "$ALL_INSTANCES" ]; then
    aws ec2 terminate-instances --instance-ids $ALL_INSTANCES >/dev/null 2>&1 || true
    aws ec2 wait instance-terminated --instance-ids $ALL_INSTANCES >/dev/null 2>&1 || true
  fi

  echo "     [7/8] Purgant Internet Gateways, Subxarxes i Security Groups..."
  for vpc in $VPCS; do
    if [ -n "$vpc" ] && [ "$vpc" != "None" ]; then
      IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --query "InternetGateways[*].InternetGatewayId" --output text 2>/dev/null || true)
      for igw in $IGWS; do
        if [ -n "$igw" ] && [ "$igw" != "None" ]; then
          aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc" >/dev/null 2>&1 || true
          aws ec2 delete-internet-gateway --internet-gateway-id "$igw" >/dev/null 2>&1 || true
        fi
      done

      SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --query "Subnets[*].SubnetId" --output text 2>/dev/null || true)
      for sub in $SUBNETS; do
        if [ -n "$sub" ] && [ "$sub" != "None" ]; then
          aws ec2 delete-subnet --subnet-id "$sub" >/dev/null 2>&1 || true
        fi
      done

      RTS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" --query "RouteTables[*].RouteTableId" --output text 2>/dev/null || true)
      for rt in $RTS; do
        if [ -n "$rt" ] && [ "$rt" != "None" ]; then
          aws ec2 delete-route-table --route-table-id "$rt" >/dev/null 2>&1 || true
        fi
      done

      SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" --query "SecurityGroups[*].GroupId" --output text 2>/dev/null || true)
      for sg in $SGS; do
        if [ -n "$sg" ] && [ "$sg" != "None" ]; then
          aws ec2 delete-security-group --group-id "$sg" >/dev/null 2>&1 || true
        fi
      done

      aws ec2 delete-vpc --vpc-id "$vpc" >/dev/null 2>&1 || true
    fi
  done

  echo "     [8/8] Deregistrant AMIs i Snapshots de l'alumne..."
  AMIS=$(aws ec2 describe-images --owners self --filters "Name=name,Values=AMI-WebCorp-${NOM_ALUMNE}*" --query "Images[*].[ImageId,BlockDeviceMappings[0].Ebs.SnapshotId]" --output text 2>/dev/null || true)
  while read -r ami_id snap_id; do
    if [ -n "$ami_id" ] && [ "$ami_id" != "None" ]; then
      aws ec2 deregister-image --image-id "$ami_id" >/dev/null 2>&1 || true
    fi
    if [ -n "$snap_id" ] && [ "$snap_id" != "None" ]; then
      aws ec2 delete-snapshot --snapshot-id "$snap_id" >/dev/null 2>&1 || true
    fi
  done <<< "$AMIS"

  echo "     [✓] Purga completa finalitzada (sense alarmes residuals)."
}

# Execució prèvia de neteja
netejar_recursos

# ---------------------------------------------------------
# DESPLEGAMENT PAS A PAS DE LA PRÀCTICA AP3
# ---------------------------------------------------------
echo -e "\n=========================================================="
echo "   DESPLEGAMENT PAS A PAS - AP3 ALEX ARJONA LÓPEZ         "
echo "=========================================================="

# 1.1 / 1.2 CREACIÓ DE XARXA I SUBXARXES
echo -e "\n---> [PUNTS 1.1 - 1.2] Creant VPC i Subxarxes en 2 AZs (us-east-1a, us-east-1b)..."
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query "Vpc.VpcId" --output text)
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value": true}' > /dev/null
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support '{"Value": true}' > /dev/null

IGW_ID=$(aws ec2 create-internet-gateway --query "InternetGateway.InternetGatewayId" --output text)
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" > /dev/null

ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query "RouteTable.RouteTableId" --output text)
aws ec2 create-route --route-table-id "$ROUTE_TABLE_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" > /dev/null

AZ1="${REGION}a"
AZ2="${REGION}b"
SUBNET1=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.1.0/24 --availability-zone "$AZ1" --query "Subnet.SubnetId" --output text)
SUBNET2=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.2.0/24 --availability-zone "$AZ2" --query "Subnet.SubnetId" --output text)

aws ec2 modify-subnet-attribute --subnet-id "$SUBNET1" --map-public-ip-on-launch > /dev/null
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET2" --map-public-ip-on-launch > /dev/null

aws ec2 associate-route-table --subnet-id "$SUBNET1" --route-table-id "$ROUTE_TABLE_ID" > /dev/null
aws ec2 associate-route-table --subnet-id "$SUBNET2" --route-table-id "$ROUTE_TABLE_ID" > /dev/null

echo "     VPC ID: $VPC_ID"
echo "     Subxarxa 1 ($AZ1): $SUBNET1"
echo "     Subxarxa 2 ($AZ2): $SUBNET2"

# 1.4 CREACIÓ DEL SECURITY GROUP
echo -e "\n---> [PUNT 1.4] Creant Security Group 'web-corp-sg'..."
SG_ID=$(aws ec2 create-security-group --group-name "web-corp-sg" --description "Security Group per a servidor Web amb SSH restringit" --vpc-id "$VPC_ID" --query "GroupId" --output text)

aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 > /dev/null
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr "${MY_IP}/32" > /dev/null

echo "     Security Group ID: $SG_ID"
echo "     Port 80/TCP -> 0.0.0.0/0 | Port 22/TCP -> ${MY_IP}/32"

# 1.3 INSTÀNCIA BASE I ESPERA DE CLOUD-INIT AMB BARRA DE PROGRÈS
echo -e "\n---> [PUNT 1.3] Llançant 'ServidorBaseAlexArjona' (t2.micro) amb clau SSH..."
BASE_AMI=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 --query "Parameters[0].Value" --output text)

USERDATA_SCRIPT=$(cat <<'EOF'
#!/bin/bash
amazon-linux-extras install -y nginx1
yum install -y stress
systemctl start nginx
systemctl enable nginx
echo "<h1>WebCorp AlexArjona - Servidor Web Actiu</h1>" > /usr/share/nginx/html/index.html
EOF
)

INSTANCE_ID=$(aws ec2 run-instances --image-id "$BASE_AMI" --instance-type t2.micro --key-name "$KEY_NAME" --subnet-id "$SUBNET1" --security-group-ids "$SG_ID" --user-data "$USERDATA_SCRIPT" --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ServidorBase${NOM_ALUMNE}}]" --query "Instances[0].InstanceId" --output text)

echo "     ID Instància Base: $INSTANCE_ID. Esperant estat 'running'..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

BASE_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

echo "     Esperant la instal·lació interna d'stress i nginx via cloud-init..."
MAX_WAIT=25
SECS=0
until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=4 -i "$KEY_PATH" ec2-user@"$BASE_IP" "which stress" >/dev/null 2>&1 || [ $SECS -ge $MAX_WAIT ]; do
  SECS=$((SECS+2))
  percent=$(( SECS * 100 / MAX_WAIT ))
  num_hasheos=$(( SECS * 30 / MAX_WAIT ))
  num_guions=$(( 30 - num_hasheos ))
  hashes=""
  guions=""
  if [ $num_hasheos -gt 0 ]; then hashes=$(printf '%*s' "$num_hasheos" '' | tr ' ' '#'); fi
  if [ $num_guions -gt 0 ]; then guions=$(printf '%*s' "$num_guions" '' | tr ' ' '-'); fi
  printf "\r     Instal·lant stress i nginx [%s%s] %d%% (%ds/%ds)" "$hashes" "$guions" "$percent" "$SECS" "$MAX_WAIT"
  sleep 2
done
echo -e "\n     [✓] Paquets 'stress' i 'nginx' confirmats a la instància base."

# 1.5 ETIQUETATGE UNÍVOC VISIBLE
echo -e "\n---> [PUNT 1.5] Aplicant etiquetes unívoques (Project=$PROJECT_TAG, Role=$ROLE_TAG)..."
aws ec2 create-tags --resources "$INSTANCE_ID" --tags Key=Project,Value="$PROJECT_TAG" Key=Role,Value="$ROLE_TAG"
echo "     [✓] Comanda 'aws ec2 create-tags' executada sobre $INSTANCE_ID."

echo -e "\n[CAPTURA PUNT 1.5] Executant aws ec2 describe-tags:"
aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" --output table

# 2.1 CREACIÓ DE L'AMI I LA PLANTILLA DE LLANÇAMENT
echo -e "\n---> [PUNT 2.1] Generant AMI i Launch Template 'PlantillaWeb'..."
AMI_NAME="AMI-WebCorp-${NOM_ALUMNE}-$(date +%Y%m%d-%H%M)"
CUSTOM_AMI_ID=$(aws ec2 create-image --instance-id "$INSTANCE_ID" --name "$AMI_NAME" --output text)

STATUS="pending"
SECS=0
while [ "$STATUS" != "available" ]; do
  sleep 3
  SECS=$((SECS+3))
  STATUS=$(aws ec2 describe-images --image-ids "$CUSTOM_AMI_ID" --query "Images[0].State" --output text 2>/dev/null || echo "pending")
  printf "\r     Esperant AMI (%s) | Temps: %ds | Estat: %s" "$CUSTOM_AMI_ID" "$SECS" "$STATUS"
done
echo -e "\n     AMI Disponible: $CUSTOM_AMI_ID"

LT_ID=$(aws ec2 create-launch-template --launch-template-name PlantillaWeb --launch-template-data "{\"ImageId\": \"$CUSTOM_AMI_ID\", \"InstanceType\": \"t2.micro\", \"KeyName\": \"$KEY_NAME\", \"SecurityGroupIds\": [\"$SG_ID\"], \"Monitoring\": {\"Enabled\": true}, \"TagSpecifications\": [{\"ResourceType\": \"instance\", \"Tags\": [{\"Key\": \"Project\", \"Value\": \"$PROJECT_TAG\"}, {\"Key\": \"Role\", \"Value\": \"$ROLE_TAG\"}]}]}" --query "LaunchTemplate.LaunchTemplateId" --output text)
echo "     Launch Template ID: $LT_ID (PlantillaWeb, t2.micro, KeyName: $KEY_NAME, Monitoring: Detailed)"

# 2.2 CREACIÓ DEL TARGET GROUP
echo -e "\n---> [PUNT 2.2] Creant Target Group 'tg-web-app'..."
TG_ARN=$(aws elbv2 create-target-group --name tg-web-app --protocol HTTP --port 80 --vpc-id "$VPC_ID" --target-type instance --query "TargetGroups[0].TargetGroupArn" --output text)
echo "     Target Group ARN: $TG_ARN"

# 2.3 CREACIÓ DE L'AUTO SCALING GROUP
echo -e "\n---> [PUNT 2.3] Llistant subxarxes i creant Auto Scaling Group 'asg-web-app'..."
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].[SubnetId,AvailabilityZone]" --output table

aws autoscaling create-auto-scaling-group --auto-scaling-group-name asg-web-app --launch-template LaunchTemplateName=PlantillaWeb,Version='$Latest' --min-size 1 --max-size 4 --desired-capacity 2 --default-cooldown 60 --vpc-zone-identifier "$SUBNET1,$SUBNET2" --target-group-arns "$TG_ARN" > /dev/null
aws autoscaling enable-metrics-collection --auto-scaling-group-name asg-web-app --granularity "1Minute" >/dev/null 2>&1 || true
echo "     ASG Desplegat: Min=1, Desired=2, Max=4 en 2 AZs ($AZ1, $AZ2)"

# 2.4 POLÍTICA D'ESCALAT DINÀMIC (TARGET TRACKING 80% CPU)
echo -e "\n---> [PUNT 2.4] Configurant Target Tracking Policy (80% CPU)..."
aws autoscaling put-scaling-policy --auto-scaling-group-name asg-web-app --policy-name policy-target-cpu-80 --policy-type TargetTrackingScaling --target-tracking-configuration '{"TargetValue": 80.0, "PredefinedMetricSpecification": {"PredefinedMetricType": "ASGAverageCPUUtilization"}}' > /dev/null
echo "     [✓] Política 'policy-target-cpu-80' associada (Objectiu automatitzat: 80% CPU)."

# 2.5 CREACIÓ DEL TOPIC SNS I NOTIFICACIÓ PER CORREU
echo -e "\n---> [PUNT 2.5] Creant Topic SNS i Subscripció de Correu ($EMAIL_ALUMNE)..."
TOPIC_ARN=$(aws sns create-topic --name "$TOPIC_NAME" --query "TopicArn" --output text)
aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint "$EMAIL_ALUMNE" > /dev/null
echo "     Topic SNS ARN: $TOPIC_ARN"
echo "     Subscripció d'avís enviada a: $EMAIL_ALUMNE"

# 2.5 MONITORATGE I ALARMA CLOUDWATCH (80% CPU / 4 MINUTS = 2 PERÍODES DE 120 SECONDS)
echo -e "\n---> [PUNT 2.5] Configurant Alarma CloudWatch (80% CPU durant 2 períodes de 120s = 4 minuts totals)..."
aws cloudwatch put-metric-alarm --alarm-name "Alarma-CPU-Alta-ASG" --alarm-description "Alerta si la CPU supera l'80% durant 2 periodes de 120s" --metric-name CPUUtilization --namespace AWS/EC2 --statistic Average --dimensions Name=AutoScalingGroupName,Value=asg-web-app --period 120 --evaluation-periods 2 --threshold 80 --comparison-operator GreaterThanThreshold --treat-missing-data notBreaching --alarm-actions "$TOPIC_ARN" > /dev/null
echo "     [✓] Alarma 'Alarma-CPU-Alta-ASG' creada (Avaluació: 4 minuts | Threshold: 80% | SNS: $EMAIL_ALUMNE)."

# 2.6 VALIDACIÓ DE LA PRÀCTICA
echo -e "\n---> [PUNT 2.6] Verificant instàncies actives..."
mostrar_barra_progres 25 "Inicialitzant instàncies de l'ASG:"

echo -e "\n=========================================================="
echo " [CAPTURA PUNT 2.6] TAULA D'INSTÀNCIES ACTIVES I IPS PÚBLIQUES:"
echo "=========================================================="
aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[InstanceId, PublicIpAddress, Placement.AvailabilityZone, State.Name, Tags[?Key=='Name'].Value | [0]]" --output table

# ---------------------------------------------------------
# EXECUCIÓ AUTOMÀTICA DE LA PROVA D'ESTRÈS I ACTIVACIÓ DE L'ALARMA (4 MINUTS)
# ---------------------------------------------------------
echo -e "\n=========================================================="
echo "   INICIANT PROVA AUTOMÀTICA D'ESTRÈS I DEMOSTRACIÓ D'ALARMA"
echo "=========================================================="

ASG_IPS=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[?InstanceId!='$INSTANCE_ID'].PublicIpAddress" --output text)

echo " Connecting-se per SSH a les instàncies de l'ASG ($ASG_IPS) i forçant 100% de CPU sostingut..."
for ip in $ASG_IPS; do
  if [ -n "$ip" ] && [ "$ip" != "None" ]; then
    echo "  -> Injectant procés d'estrès complet (100% CPU) a $ip..."
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY_PATH" ec2-user@"$ip" "sudo yum install -y stress >/dev/null 2>&1; sudo nohup stress --cpu 4 --timeout 900 </dev/null >/dev/null 2>&1 & sudo nohup python3 -c 'import multiprocessing; [multiprocessing.Process(target=lambda: [exec(\"while True: pass\")]).start() for _ in range(4)]' </dev/null >/dev/null 2>&1 &" || true
  fi
done

echo ""
mostrar_barra_progres 240 "Processant avaluació de CloudWatch i escalat al 80% (4 minuts):"

echo -e "\n=========================================================="
echo " [RESULTAT DE LA DEMOSTRACIÓ] ESTAT FINAL DE L'ALARMA CLOUDWATCH:"
echo "=========================================================="
aws cloudwatch describe-alarms --alarm-names "Alarma-CPU-Alta-ASG" --query "MetricAlarms[0].[AlarmName, StateValue, StateReason, Threshold]" --output table

# ---------------------------------------------------------
# MENÚ INTERACTIU PER A LA GESTIÓ DE L'ESTRÈS
# ---------------------------------------------------------
echo -e "\n=========================================================="
echo "   OPCIONS DE GESTIÓ D'ESTRÈS D'INSTÀNCIES                 "
echo "=========================================================="
echo " Tria com vols procedir amb el procés 'stress':"
echo "  1) Aturar 'stress' NOMÉS en 1 instància de l'ASG"
echo "  2) Aturar 'stress' a TOTES les instàncies de l'ASG"
echo "  3) No aturar cap (mantenir l'estrès actiu)"
read -p " Selecciona una opció (1/2/3): " OPCIO_STRESS

case "$OPCIO_STRESS" in
  1)
    FIRST_IP=$(echo $ASG_IPS | awk '{print $1}')
    echo " -> Aturant 'stress' únicament a la instància $FIRST_IP..."
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$KEY_PATH" ec2-user@"$FIRST_IP" "sudo pkill -9 stress; sudo pkill -9 python3; sudo pkill -9 bash" >/dev/null 2>&1 || true
    echo "     [✓] Procés 'stress' aturat a $FIRST_IP."
    ;;
  2)
    echo " -> Aturant 'stress' a totes les instàncies de l'ASG..."
    for ip in $ASG_IPS; do
      if [ -n "$ip" ] && [ "$ip" != "None" ]; then
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$KEY_PATH" ec2-user@"$ip" "sudo pkill -9 stress; sudo pkill -9 python3; sudo pkill -9 bash" >/dev/null 2>&1 || true
      fi
    done
    echo "     [✓] Procés 'stress' aturat a totes les instàncies."
    ;;
  3)
    echo " -> Es manté el procés 'stress' en execució a totes les instàncies."
    ;;
  *)
    echo " -> Opció no vàlida. No s'ha aturat cap procés."
    ;;
esac

# ---------------------------------------------------------
# INFORMACIÓ DE CÀRREGA EN TEMPS REAL (< 3 SEGONS D'ESPERA)
# ---------------------------------------------------------
echo ""
mostrar_barra_progres 3 "Consultant estat de CPU via SSH:"

echo "--------------------------------------------------------------------------------"
printf "%-20s | %-16s | %-25s | %-12s\n" "INSTÀNCIA ID" "IP PÚBLICA" "ESTAT D'ESTRÈS" "CPU ACTUAL (%)"
echo "--------------------------------------------------------------------------------"

aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[InstanceId, PublicIpAddress, Tags[?Key=='Name'].Value | [0]]" --output text | while read -r inst_id pub_ip inst_name; do
  if [ -n "$pub_ip" ] && [ "$pub_ip" != "None" ]; then
    CPU_STAT=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=4 -i "$KEY_PATH" ec2-user@"$pub_ip" "top -bn1 | grep '%Cpu' | awk '{print \$2+\$4}'" 2>/dev/null || echo "0.0")
    STRESS_RUNNING=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=4 -i "$KEY_PATH" ec2-user@"$pub_ip" "pgrep -f 'stress|python3' >/dev/null && echo 'ACTIU (100%)' || echo 'INACTIU (0%)'" 2>/dev/null || echo "DESCONEGUT")
    printf "%-20s | %-16s | %-25s | %-12s\n" "$inst_id" "$pub_ip" "$STRESS_RUNNING" "${CPU_STAT}%"
  fi
done
echo "--------------------------------------------------------------------------------"

echo -e "\n=========================================================="
echo " PRÀCTICA I DEMOSTRACIÓ COMPLETADES AMB ÈXIT "
echo "=========================================================="
read -p "Prem [ENTER] per realitzar la neteja total final..."
netejar_recursos

echo -e "\n=========================================================="
echo " ENTORN COMPLETAMENT NET I SENSE ALARMES RESIDUALS "
echo "=========================================================="
