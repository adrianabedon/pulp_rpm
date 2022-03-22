#!/bin/bash

# WARNING: DO NOT EDIT!
#
# This file was generated by plugin_template, and is managed by it. Please use
# './plugin-template --github pulp_rpm' to update this file.
#
# For more info visit https://github.com/pulp/plugin_template

set -euv

export PULP_URL="${PULP_URL:-https://pulp}"

# make sure this script runs at the repo root
cd "$(dirname "$(realpath -e "$0")")"/../../..

pip install twine wheel

export REPORTED_VERSION=$(http $PULP_URL/pulp/api/v3/status/ | jq --arg plugin rpm --arg legacy_plugin pulp_rpm -r '.versions[] | select(.component == $plugin or .component == $legacy_plugin) | .version')
export DESCRIPTION="$(git describe --all --exact-match `git rev-parse HEAD`)"
if [[ $DESCRIPTION == 'tags/'$REPORTED_VERSION ]]; then
  export VERSION=${REPORTED_VERSION}
else
  export EPOCH="$(date +%s)"
  export VERSION=${REPORTED_VERSION}${EPOCH}
fi

export response=$(curl --write-out %{http_code} --silent --output /dev/null https://pypi.org/project/pulp-rpm-client/$VERSION/)

if [ "$response" == "200" ];
then
  echo "pulp_rpm client $VERSION has already been released. Installing from PyPI."
  pip install pulp-rpm-client==$VERSION
  mkdir -p dist
  tar cvf python-client.tar ./dist
  exit
fi

cd ../pulp-openapi-generator
rm -rf pulp_rpm-client
./generate.sh pulp_rpm python $VERSION
cd pulp_rpm-client
python setup.py sdist bdist_wheel --python-tag py3
find . -name "*.whl" -exec pip install {} \;
tar cvf ../../pulp_rpm/python-client.tar ./dist

find ./docs/* -exec sed -i 's/Back to README/Back to HOME/g' {} \;
find ./docs/* -exec sed -i 's/README//g' {} \;
cp README.md docs/index.md
sed -i 's/docs\///g' docs/index.md
find ./docs/* -exec sed -i 's/\.md//g' {} \;
tar cvf ../../pulp_rpm/python-client-docs.tar ./docs
exit $?
