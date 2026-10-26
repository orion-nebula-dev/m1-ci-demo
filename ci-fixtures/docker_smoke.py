import json
import os
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.request
import uuid

image = "m1-ci-fixture:" + os.environ.get("BUILD_NUMBER", "local")
name = "m1-ci-smoke-" + uuid.uuid4().hex[:12]
art = Path("ci-artifacts")
(art / "dist").mkdir(parents=True, exist_ok=True)
record = {"container": name, "image": image}


def docker(*args):
    return subprocess.check_output(["/usr/local/bin/docker", *args], text=True).strip()


try:
    subprocess.run(["/usr/local/bin/docker", "build", "-t", image, "-f", "ci-fixtures/Dockerfile", "."], check=True)
    record["image_id"] = docker("image", "inspect", image, "--format", "{{.Id}}")
    record["architecture"] = docker("image", "inspect", image, "--format", "{{.Architecture}}")
    docker("run", "-d", "--name", name, "-p", "127.0.0.1::8080", image)
    info = json.loads(docker("inspect", name))[0]
    port = int(info["NetworkSettings"]["Ports"]["8080/tcp"][0]["HostPort"])
    for attempt in range(40):
        try:
            with urllib.request.urlopen("http://127.0.0.1:%d/health" % port, timeout=2) as response:
                body = json.load(response)
            break
        except OSError:
            if attempt == 39:
                raise
            time.sleep(0.25)
    assert body["status"] == "ok" and body["service"] == "m1-ci-go-fixture"
    assert body["os"] == "linux" and body["arch"] == "arm64"
    record["health"] = body
    record["host_port"] = port
    try:
        urllib.request.urlopen("http://127.0.0.1:%d/missing" % port, timeout=2)
        raise AssertionError("Missing route did not return 404")
    except urllib.error.HTTPError as error:
        assert error.code == 404
    docker("save", "--output", str(art / "dist/fixture-image.tar"), image)
    record["status"] = "pass"
finally:
    log = subprocess.run(["/usr/local/bin/docker", "logs", name], capture_output=True, text=True)
    (art / "docker-container.log").write_text(log.stdout + log.stderr)
    subprocess.run(["/usr/local/bin/docker", "rm", "-f", name], capture_output=True)
    remaining = subprocess.run(["/usr/local/bin/docker", "inspect", name], capture_output=True)
    record["container_removed"] = remaining.returncode != 0
    subprocess.run(["/usr/local/bin/docker", "image", "rm", image], capture_output=True)
    (art / "docker-smoke.json").write_text(json.dumps(record, indent=2) + "\n")
    assert record["container_removed"], "CI smoke container remains"
print(json.dumps(record, indent=2))
