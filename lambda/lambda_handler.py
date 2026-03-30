"""
AWS Lambda Handler for CI/CD Failure Prediction
Serverless prediction function for event-driven architectures
"""

import json
import os
import logging
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Global variables for model caching
model = None
scaler = None
label_encoder = None
feature_names = []

# Model files path (will be set from Lambda Layer or S3)
MODEL_PATH = '/opt/model'
S3_BUCKET = os.environ.get('S3_MODEL_BUCKET')
S3_PREFIX = os.environ.get('S3_MODEL_PREFIX', 'models')


def load_model_from_s3(bucket: str, prefix: str) -> bool:
    """Load model files from S3"""
    try:
        import boto3
        s3 = boto3.client('s3')

        model_files = [
            'random_forest_model.pkl',
            'scaler.pkl',
            'label_encoder.pkl',
            'feature_names.txt'
        ]

        for file in model_files:
            s3.download_file(
                bucket,
                f"{prefix}/{file}",
                f"/tmp/{file}"
            )
            logger.info(f"Downloaded {file} from S3")

        return True
    except Exception as e:
        logger.error(f"Failed to load model from S3: {e}")
        return False


def init_model():
    """Initialize model (cached across Lambda invocations)"""
    global model, scaler, label_encoder, feature_names

    if model is not None:
        return True

    try:
        import joblib

        # Try loading from Lambda layer first
        model_path = MODEL_PATH
        if not os.path.exists(f"{model_path}/random_forest_model.pkl"):
            model_path = '/tmp'

        model = joblib.load(f'{model_path}/random_forest_model.pkl')
        scaler = joblib.load(f'{model_path}/scaler.pkl')
        label_encoder = joblib.load(f'{model_path}/label_encoder.pkl')

        with open(f'{model_path}/feature_names.txt', 'r') as f:
            feature_names = f.read().strip().split(',')

        logger.info("✅ Model loaded successfully")
        return True

    except Exception as e:
        logger.error(f"Model load failed: {e}")

        # Try loading from S3 as fallback
        if S3_BUCKET and load_model_from_s3(S3_BUCKET, S3_PREFIX):
            return init_model()

        return False


def encode_time_of_commit(value):
    """Encode commit hour"""
    try:
        hour = int(value)
    except (TypeError, ValueError):
        raise ValueError("time_of_commit must be between 0 and 23")

    if hour < 0 or hour > 23:
        raise ValueError("time_of_commit must be between 0 and 23")

    if label_encoder is None:
        return hour

    for candidate in (hour, str(hour)):
        try:
            return int(label_encoder.transform([candidate])[0])
        except Exception:
            continue

    return hour


def predict_failure_risk(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Predict CI/CD build failure risk

    Args:
        event: Input data containing commit metadata

    Returns:
        Prediction result with risk assessment
    """
    # Extract input data
    if 'body' in event:
        # API Gateway event
        try:
            body = json.loads(event['body'])
        except:
            body = event['body']
    else:
        body = event

    # Validate input
    missing = [f for f in feature_names if f not in body]
    if missing:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': f'Missing features: {missing}'})
        }

    # Prepare input
    import pandas as pd
    input_data = []
    for feature in feature_names:
        value = body[feature]
        if feature == 'time_of_commit':
            value = encode_time_of_commit(value)
        input_data.append(value)

    X = pd.DataFrame([input_data], columns=feature_names)
    X_scaled = scaler.transform(X)

    # Predict
    prediction = model.predict(X_scaled)[0]
    probability = model.predict_proba(X_scaled)[0]

    failure_prob = probability[1]
    if failure_prob < 0.25:
        risk_level = "LOW"
    elif failure_prob < 0.50:
        risk_level = "MEDIUM"
    elif failure_prob < 0.75:
        risk_level = "HIGH"
    else:
        risk_level = "CRITICAL"

    prediction_label = "FAIL" if prediction == 1 else "PASS"
    confidence = max(probability)

    result = {
        'prediction': prediction_label,
        'risk_level': risk_level,
        'failure_probability': round(failure_prob, 4),
        'pass_probability': round(probability[0], 4),
        'confidence': round(confidence, 4),
        'recommendation': "🔴 STOP PIPELINE" if prediction == 1 else "🟢 CONTINUE PIPELINE"
    }

    logger.info(f"Prediction: {prediction_label} (risk: {risk_level})")
    return result


def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    AWS Lambda handler entry point

    Supports multiple invocation types:
    1. Direct invocation with prediction data
    2. API Gateway proxy integration
    3. EventBridge scheduled events
    """
    # Initialize model (cached across invocations)
    if not init_model():
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Model initialization failed'})
        }

    try:
        # Check if this is a warm-up invocation
        if event.get('source') == 'warmup':
            return {'statusCode': 200, 'body': json.dumps({'status': 'warm'})}

        # Make prediction
        result = predict_failure_risk(event)

        # Format response based on invocation type
        if 'httpMethod' in event or 'requestContext' in event:
            # API Gateway proxy
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps(result)
            }
        else:
            # Direct invocation
            return result

    except Exception as e:
        logger.error(f"Prediction error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }


# For local testing
if __name__ == '__main__':
    test_event = {
        "commit_size": 100,
        "files_changed": 5,
        "test_coverage": 75.0,
        "past_failures": 2,
        "dependency_changes": 0,
        "author_experience": 60,
        "time_of_commit": 14,
        "build_time": 350.0
    }

    print("Testing Lambda handler locally...")
    result = lambda_handler(test_event, None)
    print(json.dumps(result, indent=2))
