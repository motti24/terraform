#!/usr/bin/env bash
### NOTES:
### This is a wrapper for AWS-VAULT to use Terraform using MFA 
### see help for more info: ./terraform.sh -h
### aws-vault utilise the aws config file, so make sure you have the right profile in place.
### The source profile is set in the ~/.aws/config file
### in your config file you need to set the following:
###
### [profile my-example]
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

export KUBE_CONFIG_PATH=~/.kube/config

aws_vault=$(command -v aws-vault)

if [ -z "$aws_vault" ]; then
  echo -e "aws-vault not found. Please install it first by running: ${cyan}brew install --cask aws-vault${reset}"
  exit 1
fi

function usage() {
    echo -e "${yellow}USAGE: $0 [options] [arguments]${reset}"
    echo "Options:"
    echo "  -a            Initialize a new key to the vault - RUN THIS FIRST"
    echo "  -c            Run a terraform command (init, plan, apply, all, destroy) - Mandatory"
    echo "  -e            Environment to use for the terraform config file [staging/prod] - Mandatory"
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
elif [ -z "$command" ] && [ ! $add ]; then
    echo "Command not specified. Please specify a command with the -c flag."
    exit 1
elif [ -z "$environment" ]; then
  echo "Environment not specified. Using ${cyan}STAGING${reset} as default"
  environment="staging"
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
    aws-vault exec "$profile" -- terraform init -backend-config="$environment.conf"
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
    init) init "$@"       ;;
    plan) plan "$@"       ;;
    apply) apply "$@"     ;;
    all) all              ;;
    destroy) destroy "$@" ;;
    *) exit 1             ;;
esac
