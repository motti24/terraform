#!/usr/bin/env bash
### NOTES:
### to run this file in the terminal: ./terraform.sh <arg1> <arg2>
### see help for more info: ./terraform.sh -h
### aws-vault is using the aws config file and not the credentials file
### The source profile is set in the ~/.aws/config file
### in your config file you need to set the following:
### [profile niio-example]
### region = us-east-1
### mfa_serial = arn:aws:iam::123456789012:mfa/user
### role_arn = arn:aws:iam::123456789012:role/example
### source_profile = my-main-profile
###
### read more about aws-vault here: https://github.com/99designs/aws-vault

# colors
red='\e[31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
reset='\033[0m'

# Vault port-forwarding to avoid the need to run it manually each time
vault_port=8200
nc -zv localhost $vault_port 2>&1 # Checks if already listening
if [ "$?" -ne 0 ];then
  kubectl port-forward --namespace vault vault-0 $vault_port:$vault_port > /dev/null 2>&1 &
  echo -e "${cyan}Vault is listening on port $vault_port ${reset}"
else
  echo -e "${cyan}Vault is already listening on port $vault_port ${reset}"
fi

# This env variable is used by terraform
export VAULT_ADDR=http://localhost:$vault_port
export KUBE_CONFIG_PATH=~/.kube/config

aws_vault=$(command -v aws-vault)
vault_exec=$(command -v vault)

if [ -z "$aws_vault" ]; then
  echo -e "aws_vault not found. Please install it first by running: ${cyan}brew install --cask aws-vault${reset}"
  exit 1
elif [ -z "$vault_exec" ]; then
  echo -e "vault not found. Please install it first by running: ${cyan}brew install vault${reset}"
  exit 1
fi

# Checks if the user is already logged in
vault token lookup > /dev/null 2>&1
if [ "$?" -ne 0 ]; then
# shellcheck disable=SC2034, used in vault login
  read -rp "Please enter your Vault username: " vault_user
  echo -e "Please enter your Vault password"
  vault login -method=userpass username="$vault_user"
fi

function usage() {
    echo -e "${yellow}USAGE: $0 [options] [arguments]${reset}"
    echo "Options:"
    echo "  -a            Initialize a new key to the vault - RUN THIS FIRST"
    echo "  -c            Run a terraform command (init, plan, apply, all, destroy) - Mandatory"
    echo "  -e            Environment to use for the terraform config file [staging/prod/dev] - Default to dev"
    echo "  -h            Prints this help message"
    echo "  -p            The AWS profile to use from the config file - Mandatory"
    echo "  -t            The terraform target to apply - Optional"

    echo "Examples:"
    echo -e "  ${green}For the first time, run the script with the -a option:"
    echo -e "    ./terraform.sh -a -e staging -p staging \n"
    echo -e "  From then on, run the script with the -e -p -c options:"
    echo -e "    ./terraform.sh -p production -e prod -c init"
    echo -e "    ./terraform.sh -p stg -e staging -c plan -t aws_kms_key.my_key \n"
}

if [ -z "$1" ] || [ "$1" = "--help" ]; then
    usage
    exit
fi

while getopts 'ahc:e:p:t:' flag; do
    case "${flag}" in
        a) add=true                     ;;
        c) command="${OPTARG}"          ;;
        e) environment="${OPTARG}"      ;;
        h) usage && exit 0              ;;
        p) profile="${OPTARG}"          ;;
        t) target="-target=${OPTARG}"   ;;
        *) usage && exit 1              ;;
    esac
done

if [ -z "$profile" ]; then
  echo "Profile not specified. Please specify a profile with the -p flag."
  exit 1
elif [ -z "$command" ]; then
  if ! $add ; then
    echo "Command not specified. Please specify a command with the -c flag."
    exit 1
  fi
elif [ -z "$environment" ]; then
  echo -e "Environment not specified. Using ${cyan}STAGING${reset} as default"
  environment="dev"
fi

function add() {
  if [ "$add" = true ]; then
    echo -e "${cyan}Adding AWS credentials to the Mac OS X Keychain for $environment...${reset}"
    read -p "Please enter your main source profile: " source_profile
    aws-vault add "${source_profile}"
  fi
}

function init() {
    echo -e "${cyan}Initializing terraform...${reset}"
    aws-vault exec "$profile" -- terraform init -reconfigure -backend-config="$environment.conf"
}

function plan() {
    echo -e "${cyan}Planning terraform...${reset}"
    aws-vault exec "$profile" -- terraform plan -var-file="_$environment.tfvars" -out=tfplan $target
}

function apply() {
    echo -e "${cyan}Applying terraform...${reset}"
    aws-vault exec "$profile" -- terraform apply tfplan
}

function all() {
    echo -e "${cyan}Running terraform init, plan, and apply...${reset}"
    init
    plan
    apply
}

function destroy() {
    echo -e "${red}ALERT: Running terraform destroy ${reset}"
    read -n 1 -s -r -p "Press any key to continue"
    aws-vault exec "$profile" -- terraform destroy -var-file="_$environment.tfvars" $target
}

add
case "$command" in
    init) init        ;;
    plan) plan        ;;
    apply) apply      ;;
    all) all          ;;
    destroy) destroy  ;;
    *) exit 1         ;;
esac
