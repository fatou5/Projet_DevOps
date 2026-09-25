import os

import redis
from flask import Flask, jsonify

app = Flask(__name__)


def alert_threshold():
    return 25


def sanitize_input(value):
    return value.replace("<", "&lt;").replace(">", "&gt;")


def get_redis_client():
    return redis.Redis(
        host=os.getenv("REDIS_HOST", "redis"),
        port=int(os.getenv("REDIS_PORT", "6379")),
        decode_responses=True,
    )


@app.route("/health")
def health():
    try:
        client = get_redis_client()
        client.ping()
        return jsonify(status="ok", redis="ok"), 200
    except redis.RedisError:
        return jsonify(status="error", redis="unavailable"), 503


@app.route("/status")
def status():
    return jsonify(
        service="projet-devops-groupe-demo",
        version="1.0",
        color=os.getenv("APP_COLOR", "unknown"),
        sha=os.getenv("DEPLOY_SHA", "unknown"),
    ), 200


@app.route("/visits")
def visits():
    client = get_redis_client()
    count = client.incr("visits")
    return jsonify(visits=count), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
