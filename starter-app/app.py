import os
import time

import redis
from flask import Flask, jsonify, request
from prometheus_client import Counter, Histogram, generate_latest

app = Flask(__name__)


http_requests_total = Counter(
    "http_requests_total",
    "Total number of HTTP requests",
    ["method", "endpoint", "status"],
)

http_request_duration_seconds = Histogram(
    "http_request_duration_seconds",
    "HTTP request processing duration in seconds",
    ["method", "endpoint", "status"],
)


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


@app.before_request
def start_timer():
    request.start_time = time.perf_counter()


@app.after_request
def record_request(response):
    if request.path != "/metrics":
        duration = time.perf_counter() - request.start_time

        http_requests_total.labels(
            method=request.method,
            endpoint=request.path,
            status=response.status_code,
        ).inc()

        http_request_duration_seconds.labels(
            method=request.method,
            endpoint=request.path,
            status=response.status_code,
        ).observe(duration)

    return response


@app.route("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": "text/plain; charset=utf-8"}


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


@app.route("/simulate-error")
def simulate_error():
    return jsonify(status="error", message="simulated error"), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
