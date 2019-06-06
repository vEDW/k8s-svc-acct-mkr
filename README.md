# k8s-svc-acct-mkr

This script creates a service account and collects kubeconfig file for it.

Usage:

REM : at this time namespace must already exist before using script - no check done (yet).

./create_kubeconfig.sh <service_account_name> <namespace>

kubeconfig file will be delivered in the folder defined in the TARGET_FOLDER variable in the script. (default will create a kube folder in current directory)

This is an extention from : https://gist.github.com/innovia/fbba8259042f71db98ea8d4ad19bd708
