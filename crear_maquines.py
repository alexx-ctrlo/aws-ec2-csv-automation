#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
==============================================================================
 AP3 AWS / Exercici 1.7: Automatització EC2 via Python i Boto3 (Versió Master)
 Alumne: Àlex Arjona
 Descripció: Script amb validació/autocreació de xarxa, control de duplicats,
             impressió automàtica del CSV per pantalla abans de la confirmació
             i opció de neteja persistent de totes les instàncies detectades.
==============================================================================
"""

import csv
import sys
import boto3
from botocore.exceptions import ClientError, BotoCoreError

# ----------------------------------------------------------------------------
# CONFIGURACIÓ DE CONSTANTS I ENTORNS
# ----------------------------------------------------------------------------
REGION = "us-east-1"
KEY_PAIR_NAME = "vockey"
INPUT_CSV = "maquines.csv"
OUTPUT_CSV = "ids_creats.csv"


def crear_infraestructura_xarxa(ec2_client):
    """
    Desplega una infraestructura de xarxa completa (VPC, Subnet, IGW i Route Table)
    si l'entorn d'AWS no en té cap de disponible.
    """
    print("  [AVÍS XARXA] No s'ha trobat cap subxarxa. Creant infraestructura de xarxa automàtica...")
    try:
        # 1. Creació de la VPC
        vpc = ec2_client.create_vpc(
            CidrBlock='10.99.0.0/16',
            TagSpecifications=[{'ResourceType': 'vpc', 'Tags': [{'Key': 'Name', 'Value': 'VPC-Auto-1.7'}]}]
        )
        vpc_id = vpc['Vpc']['VpcId']
        print(f"   + VPC creada: {vpc_id}")

        ec2_client.modify_vpc_attribute(VpcId=vpc_id, EnableDnsHostnames={'Value': True})
        ec2_client.modify_vpc_attribute(VpcId=vpc_id, EnableDnsSupport={'Value': True})

        # 2. Creació de l'Internet Gateway
        igw = ec2_client.create_internet_gateway(
            TagSpecifications=[{'ResourceType': 'internet-gateway', 'Tags': [{'Key': 'Name', 'Value': 'IGW-Auto-1.7'}]}]
        )
        igw_id = igw['InternetGateway']['InternetGatewayId']
        ec2_client.attach_internet_gateway(InternetGatewayId=igw_id, VpcId=vpc_id)
        print(f"   + Internet Gateway creat i associat: {igw_id}")

        # 3. Creació de la Subxarxa
        subnet = ec2_client.create_subnet(
            VpcId=vpc_id,
            CidrBlock='10.99.1.0/24',
            AvailabilityZone=f"{REGION}a",
            TagSpecifications=[{'ResourceType': 'subnet', 'Tags': [{'Key': 'Name', 'Value': 'Subnet-Auto-1.7'}]}]
        )
        subnet_id = subnet['Subnet']['SubnetId']
        ec2_client.modify_subnet_attribute(SubnetId=subnet_id, MapPublicIpOnLaunch={'Value': True})
        print(f"   + Subxarxa creada: {subnet_id}")

        # 4. Creació de la Taula d'Enrutament
        rt = ec2_client.create_route_table(
            VpcId=vpc_id,
            TagSpecifications=[{'ResourceType': 'route-table', 'Tags': [{'Key': 'Name', 'Value': 'RT-Auto-1.7'}]}]
        )
        rt_id = rt['RouteTable']['RouteTableId']
        ec2_client.create_route(RouteTableId=rt_id, DestinationCidrBlock='0.0.0.0/0', GatewayId=igw_id)
        ec2_client.associate_route_table(SubnetId=subnet_id, RouteTableId=rt_id)
        print(f"   + Taula d'enrutament configurada: {rt_id}")

        return {
            'subnet_id': subnet_id,
            'vpc_id': vpc_id,
            'igw_id': igw_id,
            'rt_id': rt_id,
            'es_personalitzada': True
        }

    except ClientError as err:
        print(f"[ERROR AWS CRÍTIC] Error en crear la xarxa: {err.response['Error']['Message']}")
        return None


def obtenir_o_crear_subxarxa(ec2_client):
    """
    Inspecciona si hi ha subxarxes existents; si n'hi ha, n'utilitza una. 
    Si no n'hi ha cap, crida la funció de creació de xarxa.
    """
    try:
        response = ec2_client.describe_subnets()
        subnets = response.get('Subnets', [])
        
        if subnets:
            subnet_id = subnets[0]['SubnetId']
            az = subnets[0]['AvailabilityZone']
            print(f"  [OK] Subxarxa existent detectada: {subnet_id} ({az})")
            return {'subnet_id': subnet_id, 'es_personalitzada': False}
        else:
            return crear_infraestructura_xarxa(ec2_client)

    except ClientError as err:
        print(f"[ERROR AWS] Error en consultar la xarxa: {err.response['Error']['Message']}")
        return None


def comprovar_instancia_existent(ec2_client, nom_instancia):
    """
    CONTROL DE DUPLICATS: Consulta a l'API d'AWS si ja existeix una instància 
    amb el mateix nom (Tag: Name) en estat pending, running o stopped.
    """
    try:
        response = ec2_client.describe_instances(
            Filters=[
                {'Name': 'tag:Name', 'Values': [nom_instancia]},
                {'Name': 'instance-state-name', 'Values': ['pending', 'running', 'stopped']}
            ]
        )
        for reservation in response.get('Reservations', []):
            for instance in reservation.get('Instances', []):
                return instance['InstanceId']
        return None
    except ClientError:
        return None


def mostrar_contingut_csv():
    """
    Llegeix i imprimeix directament per pantalla el fitxer ids_creats.csv 
    perquè l'usuari pugui verificar-lo i capturar-lo abans de qualsevol neteja.
    """
    print("\n==========================================================")
    print("   CONTINGUT DEL FITXER DE CONTROL: ids_creats.csv       ")
    print("==========================================================")
    try:
        with open(OUTPUT_CSV, mode='r', encoding='utf-8') as f:
            contingut = f.read().strip()
            print(contingut)
    except Exception as err:
        print(f"[ERROR] No s'ha pogut llegir el fitxer '{OUTPUT_CSV}': {err}")
    print("==========================================================\n")


def purga_completa_recursos(ec2_client, ids_instancies, dades_xarxa):
    """
    Elimina les instàncies registrades (creades o existents) i, si l'script 
    va crear una xarxa personalitzada, en purga la jerarquia completa.
    """
    print("----------------------------------------------------------")
    print("   NETEJA PROFUNDA I PURGA DE RECURSOS (LEARNER LAB)     ")
    print("----------------------------------------------------------")
    
    if not ids_instancies and not (dades_xarxa and dades_xarxa.get('es_personalitzada')):
        print("  [INFO] No hi ha instàncies actives ni recursos de xarxa per esborrar.")
        return

    if ids_instancies:
        print(f"  Instàncies associades detectades a AWS: {', '.join(ids_instancies)}")

    resposta = input("  Vols esborrar les instàncies i recursos associats a aquesta execució? (s/n): ").strip().lower()
    if resposta not in ['s', 'si', 'y', 'yes']:
        print("  [INFO] Operació de neteja omesa. Els recursos i el fitxer 'ids_creats.csv' romandran intactes.")
        return

    # 1. Terminació d'instàncies EC2
    if ids_instancies:
        print(f"\n---> [1/2] Eliminant instàncies EC2: {', '.join(ids_instancies)}...")
        try:
            ec2_client.terminate_instances(InstanceIds=ids_instancies)
            print("  [INFO] Esperant que les instàncies estiguin completament terminades...")
            waiter = ec2_client.get_waiter('instance_terminated')
            waiter.wait(InstanceIds=ids_instancies)
            print("  [OK] Instàncies eliminades amb èxit.")
        except ClientError as err:
            print(f"  [ERROR AWS] Error en eliminar instàncies: {err.response['Error']['Message']}")

    # 2. Purga de la jerarquia de xarxa (si s'ha creat de zero)
    if dades_xarxa and dades_xarxa.get('es_personalitzada'):
        print("\n---> [2/2] Purgant la jerarquia de xarxa creada...")
        try:
            vpc_id = dades_xarxa['vpc_id']
            igw_id = dades_xarxa['igw_id']
            subnet_id = dades_xarxa['subnet_id']
            rt_id = dades_xarxa['rt_id']

            ec2_client.detach_internet_gateway(InternetGatewayId=igw_id, VpcId=vpc_id)
            ec2_client.delete_internet_gateway(InternetGatewayId=igw_id)
            print(f"   - Internet Gateway eliminat: {igw_id}")

            ec2_client.delete_subnet(SubnetId=subnet_id)
            print(f"   - Subxarxa eliminada: {subnet_id}")

            ec2_client.delete_route_table(RouteTableId=rt_id)
            print(f"   - Taula d'enrutament eliminada: {rt_id}")

            ec2_client.delete_vpc(VpcId=vpc_id)
            print(f"   - VPC eliminada: {vpc_id}")
            print("  [OK] Purga completa de xarxa finalitzada.")

        except ClientError as err:
            print(f"  [ERROR AWS] Error durant la purga de xarxa: {err.response['Error']['Message']}")

    print("\n[OK] Tot l'entorn ha estat netejat satisfactòriament.")


def desplegar_infraestructura():
    print("==========================================================")
    print("   AUTOMATITZACIÓ AWS EC2 - EXERCICI 1.7 (BOTO3)         ")
    print(f"   REGIÓ AWS: {REGION}                                   ")
    print("==========================================================")

    try:
        ec2 = boto3.client('ec2', region_name=REGION)
    except Exception as err:
        print(f"[ERROR CRÍTIC] No s'ha pogut inicialitzar Boto3: {err}")
        sys.exit(1)

    # 1. Validació o creació automàtica de xarxa
    print("\n---> [PAS 1/3] Validant / Preparant entorn de xarxa...")
    dades_xarxa = obtenir_o_crear_subxarxa(ec2)
    if not dades_xarxa:
        sys.exit(1)

    subnet_id = dades_xarxa['subnet_id']

    # 2. Lectura i filtrat del CSV d'entrada
    print(f"\n---> [PAS 2/3] Llegint el fitxer de paràmetres '{INPUT_CSV}'...")
    linies_filtrades = []
    try:
        with open(INPUT_CSV, mode='r', encoding='utf-8') as f:
            linies_filtrades = [
                line.strip() for line in f 
                if line.strip() and not line.strip().startswith('#')
            ]
    except FileNotFoundError:
        print(f"[ERROR CRÍTIC] El fitxer '{INPUT_CSV}' no existeix.")
        sys.exit(1)

    reader = csv.DictReader(linies_filtrades)
    resultats = []
    ids_totals_gestionats = []  # Emmagatzema TOTS els IDs (creats de nou + duplicats existents)

    # 3. Creació d'instàncies amb control de duplicats
    print("\n---> [PAS 3/3] Processant la creació de les instàncies EC2...")
    for idx, row in enumerate(reader, start=1):
        nom = row.get('nom', f'Instancia-Desconeguda-{idx}').strip()
        instance_type = row.get('instance_type', '').strip()
        ami_id = row.get('ami_id', '').strip()

        print(f"\n     [{idx}] Processant instància: '{nom}' ({instance_type} | {ami_id})")

        if not instance_type or not ami_id:
            print(f"     [ERROR DADES] Camps 'instance_type' o 'ami_id' buits a la fila {idx}.")
            resultats.append({'nom': nom, 'instance_id': 'NO_EXECUTAT', 'estat': 'ERROR_DADES_ENTRADA'})
            continue

        # Comprovació de duplicats a AWS
        id_existent = comprovar_instancia_existent(ec2, nom)
        if id_existent:
            print(f"     [AVÍS DUPLICAT] La instància '{nom}' ja existeix a AWS ({id_existent}). S'omet la creació.")
            resultats.append({'nom': nom, 'instance_id': id_existent, 'estat': 'OMÈS_JA_EXISTEIX'})
            ids_totals_gestionats.append(id_existent)
            continue

        try:
            response = ec2.run_instances(
                ImageId=ami_id,
                InstanceType=instance_type,
                MinCount=1,
                MaxCount=1,
                KeyName=KEY_PAIR_NAME,
                SubnetId=subnet_id,
                TagSpecifications=[{
                    'ResourceType': 'instance',
                    'Tags': [
                        {'Key': 'Name', 'Value': nom},
                        {'Key': 'Project', 'Value': 'AWS-Academy-CLI'},
                        {'Key': 'Exercici', 'Value': '1.7'}
                    ]
                }]
            )
            instance_id = response['Instances'][0]['InstanceId']
            print(f"     [OK] INSTÀNCIA CREADA AMB ÈXIT: {instance_id}")
            ids_totals_gestionats.append(instance_id)
            resultats.append({'nom': nom, 'instance_id': instance_id, 'estat': 'CREADA_CORRECTAMENT'})

        except ClientError as err:
            codi_error = err.response['Error']['Code']
            print(f"     [ERROR AWS] [{codi_error}]: {err.response['Error']['Message']}")
            resultats.append({'nom': nom, 'instance_id': 'ERROR_CREACIO', 'estat': f"ERROR_AWS: {codi_error}"})

        except BotoCoreError as err:
            print(f"     [ERROR BOTO3] {err}")
            resultats.append({'nom': nom, 'instance_id': 'ERROR_CONNEXIO', 'estat': 'ERROR_BOTOCORE'})

    # 4. Escriptura del fitxer CSV de sortida
    print(f"\n---> Generant fitxer de control de sortida: '{OUTPUT_CSV}'...")
    try:
        with open(OUTPUT_CSV, mode='w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=['nom', 'instance_id', 'estat'])
            writer.writeheader()
            writer.writerows(resultats)
        print(f"  [OK] Resultats guardats correctament a '{OUTPUT_CSV}'.")
    except Exception as err:
        print(f"[ERROR CRÍTIC] Error en escriure '{OUTPUT_CSV}': {err}")

    # 5. Impressió del contingut del CSV directament a pantalla abans de la confirmació
    mostrar_contingut_csv()

    # 6. Neteja interactiva (passant TOTS els IDs detectats)
    purga_completa_recursos(ec2, ids_totals_gestionats, dades_xarxa)

    print("==========================================================")
    print("   PROCÉS COMPLETAT                                       ")
    print("==========================================================\n")


if __name__ == '__main__':
    desplegar_infraestructura()