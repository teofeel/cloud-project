import urllib3
import json
import os

http = urllib3.PoolManager()
WEBHOOK_URL = os.environ.get("DISCORD_WEBHOOK_URL", "")


def lambda_handler(event, context):
    sns_record = event['Records'][0]['Sns']
    inner_event = json.loads(sns_record['Message'])
    
    detail = inner_event.get('detail', {})
    resources = inner_event.get('resources', [''])
    function_arn = resources[0] if resources else ''

    arn_parts = function_arn.split(':') if function_arn else []
    region = arn_parts[3] if len(arn_parts) > 3 else 'eu-west-1'

    if arn_parts:
        if arn_parts[-1] == '$LATEST':
            function_name = arn_parts[-2]
        else:
            function_name = arn_parts[-1]
    else:
        function_name = 'Unknown-Function'

    status = detail.get('status', 'FAILED')
    error_message = detail.get('errorMessage', 'No explicit error message')

    cloudwatch_log_link = f"https://{region}.console.aws.amazon.com/cloudwatch/home?region={region}#logsV2:log-groups"
    lambda_console_link = f"https://{region}.console.aws.amazon.com/lambda/home?region={region}#/functions/{function_name}"


    message_content = (
        f"AWS Alert: Something Happened\n"
        f"Resource: {function_name}\n"
        f"Status: {status}\n"
        f"Region: {region}\n"
        f"Error: {error_message}\n"
        f"\n"
        f"Check out for more:\n"
        f"Lambda Console: {lambda_console_link}\n"
        f"CloudWatch Execution Logs: {cloudwatch_log_link}\n"

    )

    payload = {'content':message_content}
    encoded_payload = json.dumps(payload).encode('utf-8')

    try:
        res = http.request('POST', WEBHOOK_URL, body=encoded_payload, headers={'Content-Type':'application/json'})

        return {
            'statusCode': 200,
            'body': json.dumps(f"Notification pushed successfully: {res.status}")
        }
    
    except Exception as e:
        print(f"Critical exception occurred: {str(e)}")
        raise e