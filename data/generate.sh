#!/usr/bin/env bash
# Generate synthetic patient records with Synthea (FHIR R4 JSON).
# No real patient data is used anywhere in this project.
# Runs Synthea inside a Java container, so only Docker is needed.
set -euo pipefail

cd "$(dirname "$0")"
POPULATION="${POPULATION:-25}"
SEED="${SEED:-2026}"
JAR=synthea-with-dependencies.jar
URL=https://github.com/synthetichealth/synthea/releases/download/master-branch-latest/$JAR

if [[ ! -f $JAR ]]; then
  echo "Downloading Synthea..."
  curl -sSfL -o "$JAR" "$URL"
fi
sha256sum "$JAR" | tee synthea.sha256

rm -rf output
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD":/work -w /work eclipse-temurin:21-jre \
  java -jar "$JAR" -p "$POPULATION" -s "$SEED" -cs "$SEED" \
  --exporter.baseDirectory ./output/

echo
echo "Generated $(ls output/fhir/*.json | wc -l) FHIR bundles in data/output/fhir/"
