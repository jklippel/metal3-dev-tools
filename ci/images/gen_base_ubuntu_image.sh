#! /usr/bin/env bash

set -eux

SSH_PRIVATE_KEY_FILE="${1:?}"
USE_FLOATING_IP="${2:?}"

CI_DIR="$(dirname "$(readlink -f "${0}")")/.."
IMAGES_DIR="${CI_DIR}/images"
SCRIPTS_DIR="${CI_DIR}/scripts/image_scripts"
OS_SCRIPTS_DIR="${CI_DIR}/scripts/openstack"

# shellcheck source=ci/scripts/openstack/infra_defines.sh
source "${OS_SCRIPTS_DIR}/infra_defines.sh"

# shellcheck source=ci/scripts/openstack/utils.sh
source "${OS_SCRIPTS_DIR}/utils.sh"

IMAGE_NAME="${CI_BASE_IMAGE}-$(get_random_string 10)"
FINAL_IMAGE_NAME="${CI_BASE_IMAGE}"
SOURCE_IMAGE_NAME="ubuntu-22.04-server-cloudimg-amd64_01_09_22"
IMAGE_FLAVOR="1C-4GB-20GB"
USER_DATA_FILE="$(mktemp -d)/userdata"
SSH_USER_NAME="${CI_SSH_USER_NAME}"
SSH_KEYPAIR_NAME="${CI_KEYPAIR_NAME}"
NETWORK="$(get_resource_id_from_name network "${CI_EXT_NET}")"
FLOATING_IP_NETWORK="$( [ "${USE_FLOATING_IP}" = 1 ] && echo "${EXT_NET}")"
REMOTE_EXEC_CMD="KUBERNETES_VERSION=${KUBERNETES_VERSION} /home/${SSH_USER_NAME}/image_scripts/provision_base_image.sh"
SSH_USER_GROUP="sudo"

SSH_AUTHORIZED_KEY="$(cat "${OS_SCRIPTS_DIR}/id_ed25519_metal3ci.pub")"
render_user_data \
  "${SSH_AUTHORIZED_KEY}" \
  "${SSH_USER_NAME}" \
  "${SSH_USER_GROUP}" \
  "${IMAGE_NAME}" \
  "${IMAGES_DIR}/ubuntu_userdata.tpl" \
  "${USER_DATA_FILE}"

STARTER_SCRIPT_PATH="/tmp/build_starter.sh"
echo "${REMOTE_EXEC_CMD}" > "${STARTER_SCRIPT_PATH}"

# Create CI Keypair

CI_PUBLIC_KEY_FILE="${OS_SCRIPTS_DIR}/id_ed25519_metal3ci.pub"
delete_keypair "${SSH_KEYPAIR_NAME}"
create_keypair "${CI_PUBLIC_KEY_FILE}" "${SSH_KEYPAIR_NAME}"

# Build Image
packer build \
  -var "image_name=${IMAGE_NAME}" \
  -var "source_image_name=${SOURCE_IMAGE_NAME}" \
  -var "user_data_file=${USER_DATA_FILE}" \
  -var "exec_script_path=${STARTER_SCRIPT_PATH}" \
  -var "ssh_username=${SSH_USER_NAME}" \
  -var "ssh_keypair_name=${SSH_KEYPAIR_NAME}" \
  -var "ssh_private_key_file=${SSH_PRIVATE_KEY_FILE}" \
  -var "network=${NETWORK}" \
  -var "floating_ip_net=${FLOATING_IP_NETWORK}" \
  -var "local_scripts_dir=${SCRIPTS_DIR}" \
  -var "flavor=${IMAGE_FLAVOR}" \
  "${IMAGES_DIR}/image_builder_template.json"

# Replace any old image

replace_image "${IMAGE_NAME}" "${FINAL_IMAGE_NAME}"
