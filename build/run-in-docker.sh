#!/bin/bash

# Copyright 2018 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

DEBUG=${DEBUG:-"false"}
if [ "$DEBUG" == "true" ]; then
  set -x
fi

set -o errexit
set -o nounset
set -o pipefail

# temporal directory for the /etc/ingress-controller directory
INGRESS_VOLUME=$(mktemp -d)

# make sure directory for SSL cert storage exists under ingress volume
mkdir "${INGRESS_VOLUME}/ssl"

if [[ "$OSTYPE" == darwin* ]]; then
  INGRESS_VOLUME=/private$INGRESS_VOLUME
fi

function cleanup {
  rm -rf "${INGRESS_VOLUME}"
}
trap cleanup EXIT

E2E_IMAGE=${E2E_IMAGE:-registry.k8s.io/ingress-nginx/e2e-test-runner:v20221125-controller-v1.5.1-21-g9d562c47a@sha256:50c5469f08b664e928a3035ac94a2348955b669d7ac33809abc674c8fd6c19c1}

DOCKER_OPTS=${DOCKER_OPTS:-}
DOCKER_IN_DOCKER_ENABLED=${DOCKER_IN_DOCKER_ENABLED:-}

KUBE_ROOT=$(cd $(dirname "${BASH_SOURCE}")/.. && pwd -P)

FLAGS=$@

PKG=k8s.io/ingress-nginx
ARCH=${ARCH:-}
if [[ -z "$ARCH" ]]; then
  ARCH=$(go env GOARCH)
fi

# create output directory as current user to avoid problem with docker.
mkdir -p "${KUBE_ROOT}/bin" "${KUBE_ROOT}/bin/${ARCH}"

PLATFORM="${PLATFORM:-}"
if [[ -n "$PLATFORM" ]]; then
  PLATFORM_FLAG=--platform
else
  PLATFORM_FLAG=
fi

USER=${USER:-nobody}

echo "..printing env & other vars to stdout"
echo "HOSTNAME=`hostname`"
uname -a
env
echo "DIND_ENABLED=$DOCKER_IN_DOCKER_ENABLED"
echo "done..printing env & other vars to stdout"

if [[ "$DOCKER_IN_DOCKER_ENABLED" == "true" ]]; then
  echo "..reached DIND check TRUE block, inside run-in-docker.sh"
  echo "FLAGS=$FLAGS"
  go env
  set -x
  go install -mod=mod github.com/onsi/ginkgo/v2/ginkgo@v2.6.0
  find / -type f -name ginkgo 2>/dev/null
  which ginkgo
  /bin/bash -c "${FLAGS}"
  set +x
else
  echo "Reached DIND check ELSE block, inside run-in-docker.sh"
  docker run                                            \
    ${PLATFORM_FLAG} ${PLATFORM}                        \
    --tty                                               \
    --rm                                                \
    ${DOCKER_OPTS}                                      \
    -e DEBUG=${DEBUG}                                   \
    -e GOCACHE="/go/src/${PKG}/.cache"                  \
    -e GOMODCACHE="/go/src/${PKG}/.modcache"            \
    -e DOCKER_IN_DOCKER_ENABLED="true"                  \
    -v "${HOME}/.kube:${HOME}/.kube"                    \
    -v "${KUBE_ROOT}:/go/src/${PKG}"                    \
    -v "${KUBE_ROOT}/bin/${ARCH}:/go/bin/linux_${ARCH}" \
    -v "/var/run/docker.sock:/var/run/docker.sock"      \
    -v "${INGRESS_VOLUME}:/etc/ingress-controller/"     \
    -w "/go/src/${PKG}"                                 \
    ${E2E_IMAGE} /bin/bash -c "${FLAGS}"
fi
