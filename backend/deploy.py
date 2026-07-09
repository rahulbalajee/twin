import os
import shutil
import zipfile
import subprocess
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent

def main():
    os.chdir(BASE_DIR)

    print("Creating Lambda deployment package...")

    for stale_dir in ["lambda-package", "package"]:
        if os.path.exists(stale_dir):
            shutil.rmtree(stale_dir)
    if os.path.exists("lambda-deployment.zip"):
        os.remove("lambda-deployment.zip")

    os.makedirs("lambda-package")

    print("Exporting pinned requirements from uv.lock...")

    subprocess.run(
        ["uv", "export", "--no-hashes", "--no-dev", "--no-emit-project", "-o", "requirements.txt"],
        check=True,
    )

    print("Installing dependencies for Lambda runtime...")

    subprocess.run(
        [
            "docker",
            "run",
            "--rm",
            "-v",
            f"{BASE_DIR}:/var/task",
            "--platform",
            "linux/amd64",
            "--entrypoint",
            "",
            "public.ecr.aws/lambda/python:3.12",
            "/bin/sh",
            "-c",
            "pip install --target /var/task/lambda-package -r /var/task/requirements.txt --platform manylinux2014_x86_64 --only-binary=:all: --upgrade",
        ],
        check=True,
    )

    print("Copying application code...")

    for file in ["server.py", "lambda_handler.py", "context.py", "resources.py"]:
        shutil.copy2(file, "lambda-package/")

    shutil.copytree("data", "lambda-package/data")

    print("Creating zip file...")

    with zipfile.ZipFile("lambda-deployment.zip", "w", zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk("lambda-package"):
            for file in files:
                file_path = os.path.join(root, file)
                arcname = os.path.relpath(file_path, "lambda-package")
                zipf.write(file_path, arcname)

    size_mb = os.path.getsize("lambda-deployment.zip") / (1024 * 1024)
    print(f"✓ Created lambda-deployment.zip ({size_mb:.2f} MB)")

if __name__ == "__main__":
    main()
