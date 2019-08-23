#!/usr/bin/env bash
# coding=utf-8

# WARNING: DO NOT EDIT!
#
# This file was generated by plugin_template, and is managed by bootstrap.py. Please use
# bootstrap.py to update this file.
#
# For more info visit https://github.com/pulp/plugin_template

set -mveuo pipefail

export POST_SCRIPT=$TRAVIS_BUILD_DIR/.travis/post_script.sh
export POST_DOCS_TEST=$TRAVIS_BUILD_DIR/.travis/post_docs_test.sh
export FUNC_TEST_SCRIPT=$TRAVIS_BUILD_DIR/.travis/func_test_script.sh

# Needed for both starting the service and building the docs.
# Gets set in .travis/settings.yml, but doesn't seem to inherited by
# this script.
export DJANGO_SETTINGS_MODULE=pulpcore.app.settings

wait_for_pulp() {
  TIMEOUT=${1:-5}
  while [ "$TIMEOUT" -gt 0 ]
  do
    echo -n .
    sleep 1
    TIMEOUT=$(($TIMEOUT - 1))
    STATUS=$(http :24817/pulp/api/v3/status/ 2>/dev/null)
    if [ "$(echo $STATUS | jq '.database_connection.connected and .redis_connection.connected')" = "true"\
      -a "$(echo $STATUS | jq '.online_content_apps[0]')" != "null" ]
    then
      echo
      return
    fi
  done
  echo
  return 1
}

# Containers may take a long time to download & start.
# See pulp-operator/.travis/pulp-operator-check-and-wait.sh
wait_for_pulp 600

if [ "$TEST" = 'docs' ]; then
  cd docs
  make html
  cd ..

  if [ -f $POST_DOCS_TEST ]; then
      $POST_DOCS_TEST
  fi
  exit
fi

if [ "$TEST" = 'bindings' ]; then
  COMMIT_MSG=$(git log --format=%B --no-merges -1)
  export PULP_BINDINGS_PR_NUMBER=$(echo $COMMIT_MSG | grep -oP 'Required\ PR:\ https\:\/\/github\.com\/pulp\/pulp-openapi-generator\/pull\/(\d+)' | awk -F'/' '{print $7}')

  cd ..
  git clone https://github.com/pulp/pulp-openapi-generator.git
  cd pulp-openapi-generator

  if [ -n "$PULP_BINDINGS_PR_NUMBER" ]; then
    git fetch origin +refs/pull/$PULP_BINDINGS_PR_NUMBER/merge
    git checkout FETCH_HEAD
  fi

  ./generate.sh pulpcore python
  pip install ./pulpcore-client
  ./generate.sh pulp_rpm python
  pip install ./pulp_rpm-client

  python $TRAVIS_BUILD_DIR/.travis/test_bindings.py

  if [ ! -f $TRAVIS_BUILD_DIR/.travis/test_bindings.rb ]
  then
    exit
  fi

  rm -rf ./pulpcore-client

  ./generate.sh pulpcore ruby
  cd pulpcore-client
  gem build pulpcore_client
  gem install --both ./pulpcore_client-0.gem
  cd ..

  rm -rf ./pulp_rpm-client

  ./generate.sh pulp_rpm ruby

  cd pulp_rpm-client
  gem build pulp_rpm_client
  gem install --both ./pulp_rpm_client-0.gem
  cd ..

  ruby $TRAVIS_BUILD_DIR/.travis/test_bindings.rb
  exit
fi


PULP_API_POD=$(sudo kubectl get pods | grep -E -o "pulp-api-(\w+)-(\w+)")
export CMD_PREFIX="sudo kubectl exec $PULP_API_POD --"
# Many tests require pytest/mock, but users do not need them at runtime
# (or to add plugins on top of pulpcore or pulp container images.)
# So install it here, rather than in the image Dockerfile.
# This has to be done after wait_for_pulp (although not at the very end of it.)
$CMD_PREFIX pip3 install pytest mock
# Many functional tests require these
$CMD_PREFIX dnf install -y lsof which dnf-plugins-core
# The alias does not seem to work in Travis / the scripting framework
#alias pytest="$CMD_PREFIX pytest"

# Run unit tests.
$CMD_PREFIX bash -c "sed \"s/'USER': 'pulp'/'USER': 'postgres'/g\" /etc/pulp/settings.py > unit-test.py"
# Temporarily continue here while we fix them under containers.
set +e
$CMD_PREFIX bash -c "PULP_SETTINGS=/unit-test.py django-admin test  --noinput /usr/local/lib/python${TRAVIS_PYTHON_VERSION}/site-packages/pulp_rpm/tests/unit/"
set -e

# Note: This function is in the process of being merged into after_failure
show_logs_and_return_non_zero() {
  readonly local rc="$?"
  echo "container yum/dnf repos":
  echo -en "travis_fold:start:$containerlog"'\\r'
  $CMD_PREFIX bash -c "ls -latr /etc/yum.repos.d/"
  $CMD_PREFIX bash -c "cat /etc/yum.repos.d/*"
  echo -en "travis_fold:end:$containerlog"'\\r'
  return "${rc}"
}

# Run functional tests
set +u

export PYTHONPATH=$TRAVIS_BUILD_DIR:$TRAVIS_BUILD_DIR/../pulpcore:${PYTHONPATH}

set -u
if [ -f $FUNC_TEST_SCRIPT ]; then
    $FUNC_TEST_SCRIPT
else
    pytest -v -r sx --color=yes --pyargs pulp_rpm.tests.functional || show_logs_and_return_non_zero
fi

if [ -f $POST_SCRIPT ]; then
    $POST_SCRIPT
fi
