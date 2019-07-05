#!/bin/bash

#
# source : https://gist.github.com/innovia/fbba8259042f71db98ea8d4ad19bd708
#


set -e
set -o pipefail

# Delete service account and secretfrom k8s, no RBAC (must delete RBAC after this script)
if [[ -z "$1" ]] || [[ -z "$2" ]]; then
 echo "usage: $0 <service_account_name> <namespace>"
 exit 1
fi

OS="`uname`"
SERVICE_ACCOUNT_NAME=$1
NAMESPACE="$2"
TARGET_FOLDER="kube"
KUBECFG_FILE_NAME="${TARGET_FOLDER}/k8s-${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-conf"



delete_service_account() {
    echo -e "\\nCreating a service account in ${NAMESPACE} namespace: ${SERVICE_ACCOUNT_NAME}"
    kubectl create sa "${SERVICE_ACCOUNT_NAME}" --namespace "${NAMESPACE}"
}

get_secret_name_from_service_account() {
    echo -e "\\nGetting secret of service account ${SERVICE_ACCOUNT_NAME} on ${NAMESPACE}"
    SECRET_NAME=$(kubectl get sa "${SERVICE_ACCOUNT_NAME}" --namespace="${NAMESPACE}" -o json | jq -r .secrets[].name)
    echo "Secret name: ${SECRET_NAME}"
}

delete_secret() {
    echo -e "\\nDeleting a secret in ${NAMESPACE} namespace: ${SECRET_NAME}"
    kubectl delete secret "${SECRET_NAME}" --namespace "${NAMESPACE}"
}
extract_ca_crt_from_secret() {
    echo -e -n "\\nExtracting ca.crt from secret..."
    if [ OS == "Darwin" ]; then
        kubectl get secret --namespace "${NAMESPACE}" "${SECRET_NAME}" -o json | jq -r '.data["ca.crt"]' | base64 -D > "${TARGET_FOLDER}/ca.crt"
    elif [ OS == "Linux" ]; then
        kubectl get secret --namespace "${NAMESPACE}" "${SECRET_NAME}" -o json | jq -r '.data["ca.crt"]' | base64 -d > "${TARGET_FOLDER}/ca.crt"
    else
        # Do something under 64 bits Windows NT platform
        echo "extract_ca_crt_from_secret() error : "
        echo "sorry no test done on $OS yet"
        exit 1
    fi

    printf "done"
}

get_user_token_from_secret() {
    echo -e -n "\\nGetting user token from secret..."
    if [ OS == "Darwin" ]; then
        USER_TOKEN=$(kubectl get secret --namespace "${NAMESPACE}" "${SECRET_NAME}" -o json | jq -r '.data["token"]' | base64 -D)        
    elif [ OS == "Linux" ]; then
        USER_TOKEN=$(kubectl get secret --namespace "${NAMESPACE}" "${SECRET_NAME}" -o json | jq -r '.data["token"]' | base64 -d)
    else
        # Do something under 64 bits Windows NT platform
        echo "get_user_token_from_secret() error : "
        echo "sorry no test done on $OS yet"
        exit 1
    fi
    printf "done"
}

set_kube_config_values() {
    context=$(kubectl config current-context)
    echo -e "\\nSetting current context to: $context"

    CLUSTER_NAME=$(kubectl config get-contexts "$context" | awk '{print $3}' | tail -n 1)
    echo "Cluster name: ${CLUSTER_NAME}"

    ENDPOINT=$(kubectl config view \
    -o jsonpath="{.clusters[?(@.name == \"${CLUSTER_NAME}\")].cluster.server}")
    echo "Endpoint: ${ENDPOINT}"

    # Set up the config
    echo -e "\\nPreparing k8s-${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-conf"
    echo -n "Setting a cluster entry in kubeconfig..."
    kubectl config set-cluster "${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --server="${ENDPOINT}" \
    --certificate-authority="${TARGET_FOLDER}/ca.crt" \
    --embed-certs=true

    echo -n "Setting token credentials entry in kubeconfig..."
    kubectl config set-credentials \
    "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --token="${USER_TOKEN}"

    echo -n "Setting a context entry in kubeconfig..."
    kubectl config set-context \
    "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --cluster="${CLUSTER_NAME}" \
    --user="${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --namespace="${NAMESPACE}"

    echo -n "Setting the current-context in the kubeconfig file..."
    kubectl config use-context "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}"
}

create_rbac_yaml() {
    echo -e -n "\\nGenerating RBAC yaml file..."
    cp cluster-role.templ.yaml ${TARGET_FOLDER}/cluster-role.yaml
    sed -i '' 's/{{ns-default}}/'${NAMESPACE}'/g' ${TARGET_FOLDER}/cluster-role.yaml
    sed -i '' 's/{{api-service-account}}/'${SERVICE_ACCOUNT_NAME}'/g' ${TARGET_FOLDER}/cluster-role.yaml
    printf "done"
}

get_secret_name_from_service_account
delete_service_account
delete_secret

echo -e "\\nAll done! Test with:"
echo "KUBECONFIG=${KUBECFG_FILE_NAME} kubectl get pods"
echo "you should not have any permissions by default - you have just created the authentication part"
echo "You will need to apply RBAC permissions"
KUBECONFIG=${KUBECFG_FILE_NAME} kubectl get pods
