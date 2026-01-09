import json
import urllib3
import os
import boto3
from datetime import datetime

# Initialiser le client pour récupérer les secrets
secrets_client = boto3.client('secretsmanager')
http = urllib3.PoolManager()


def get_discord_webhook():
    """Récupère l'URL du webhook Discord depuis Secrets Manager"""
    secret_name = os.environ['DISCORD_WEBHOOK_SECRET_NAME']

    try:
        response = secrets_client.get_secret_value(SecretId=secret_name)
        secret = json.loads(response['SecretString'])
        return secret['DISCORD_WEBHOOK_URL']
    except Exception as e:
        print(f"Erreur lors de la récupération du secret: {str(e)}")
        raise


def lambda_handler(event, context):
    """
    Fonction Lambda déclenchée par SNS lors d'une alarme CloudWatch
    """
    print(f"Event reçu: {json.dumps(event)}")

    # Récupérer le message SNS
    sns_message = json.loads(event['Records'][0]['Sns']['Message'])

    # Extraire les informations de l'alarme
    alarm_name = sns_message.get('AlarmName', 'Unknown')
    new_state = sns_message.get('NewStateValue', 'Unknown')
    reason = sns_message.get('NewStateReason', 'No reason provided')
    timestamp = sns_message.get('StateChangeTime', datetime.now().isoformat())

    # Informations sur la métrique
    trigger = sns_message.get('Trigger', {})
    metric_name = trigger.get('MetricName', 'Unknown')
    threshold = trigger.get('Threshold', 'Unknown')
    instance_id = trigger.get('Dimensions', [{}])[0].get('value', 'Unknown')
    region = trigger.get('Region', 'eu-west-3')  # Région de l'alarme

    # Créer le lien vers l'instance EC2 dans la console AWS
    ec2_console_url = f"https://console.aws.amazon.com/ec2/v2/home?region={region}#InstanceDetails:instanceId={instance_id}"

    # Créer le message Discord enrichi
    discord_message = {
        "content": "⚠️ 🚨 **Veuillez réagir avec ✅ à ce message quand vous avez pris en compte cette alarme**",
        "embeds": [{
            "title": f"🚨 Alarme AWS CloudWatch: {alarm_name}",
            "description": f"**État:** {new_state}",
            "color": 16711680,
            "fields": [
                {
                    "name": "📊 Métrique",
                    "value": metric_name,
                    "inline": True
                },
                {
                    "name": "🎯 Seuil",
                    "value": f"{threshold}%",
                    "inline": True
                },
                {
                    "name": "💻 Instance",
                    "value": f"[{instance_id}]({ec2_console_url})",
                    "inline": True
                },
                {
                    "name": "📝 Raison",
                    "value": reason,
                    "inline": False
                },
                {
                    "name": "🕐 Heure",
                    "value": timestamp,
                    "inline": False
                }
            ],
            "footer": {
                "text": "AWS CloudWatch Monitoring"
            }
        }]
    }

    # Récupérer le webhook et envoyer le message
    try:
        webhook_url = get_discord_webhook()

        encoded_data = json.dumps(discord_message).encode('utf-8')

        response = http.request(
            'POST',
            webhook_url,
            body=encoded_data,
            headers={'Content-Type': 'application/json'}
        )

        print(f"Message envoyé à Discord. Status: {response.status}")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Notification envoyée avec succès',
                'discord_status': response.status
            })
        }

    except Exception as e:
        print(f"Erreur lors de l'envoi à Discord: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Erreur lors de l\'envoi',
                'error': str(e)
            })
        }
