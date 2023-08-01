#!/bin/bash
set -e
SERVICE_NAME=$(cat pipeline_config.json | jq -r '.commonConfig.serviceName')
PLATFORM=$(cat pipeline_config.json | jq -r '.commonConfig.platform')
REGION=$(cat pipeline_config.json | jq -r '.commonConfig.region')
APP_NAME=$(cat pipeline_config.json | jq -r '.commonConfig.appName')
HOSTING_PATH=$(cat pipeline_config.json | jq -r '.commonConfig.hostingPath')

echo -n "Env (prod, stge, uat): "
read Env
echo
echo -n "EnvId (1, release): "
read EnvId

case "$Env" in

"prod")
    PROFILE="aa-prd"
    case "$EnvId" in
    "1")
        ;;
    *)
        echo "Unknown Env Id"
        exit 1
        ;;
    esac
    ;;
"stge")
    PROFILE="aa-pre"
    case "$EnvId" in
    "release")
        ;;
    *)
        echo "Unknown Env Id"
        exit 1
        ;;
    esac
    ;;
"uat")
    PROFILE="aa-uat"
    case "$EnvId" in
    "release")
        ;;
    *)
        echo "Unknown Env Id"
        exit 1
        ;;
    esac
    ;;
"qa")
    PROFILE="aa-dev"
    case "$EnvId" in
    "develop")
        ;;
    *)
        echo "Unknown Env Id"
        exit 1
        ;;
    esac
    ;;
*) echo "Unknown env"
    exit 1
    ;;
esac

echo "Environment: ${Env}_${EnvId}"


RELEASES_PROFILE="aa-dev"
BUCKET=`aws ssm get-parameter --name "/${PLATFORM}/${SERVICE_NAME}/artifactBucketName" --query "Parameter.Value" --output text --profile ${RELEASES_PROFILE}`
AVAILABLE_VERSIONS=`aws s3api list-objects --bucket ${BUCKET} --prefix ${PLATFORM}-${SERVICE_NAME}/ --delimiter / --output text --profile ${RELEASES_PROFILE}| cut -d / -f2`
EXISTING_VERSION=$(aws cloudformation describe-stacks --stack-name ${PLATFORM}-${SERVICE_NAME}-${Env}-${EnvId} --query 'Stacks[].Outputs[?OutputKey==`Version`].OutputValue[]' --output text --profile ${PROFILE})

echo "existing version is: ${EXISTING_VERSION}"
echo
echo "available versions are:"
echo $AVAILABLE_VERSIONS
echo
echo -n "Please enter new Version (e.g. ${LAST_VERSION}): "
read Version

ArchiveName=$(echo "$Version" |  sed 's/\(.*\)\..*/\1/')

aws s3 cp s3://${BUCKET}/${PLATFORM}-${SERVICE_NAME}/${Version} ./${PLATFORM}-${SERVICE_NAME}-${Version} --profile $RELEASES_PROFILE
unzip -d ./${PLATFORM}-${SERVICE_NAME}-${ArchiveName} ./${PLATFORM}-${SERVICE_NAME}-${Version}

cd ./${PLATFORM}-${SERVICE_NAME}-${ArchiveName}
export AWS_DEFAULT_PROFILE=$PROFILE

ACCOUNT_ID=`aws sts get-caller-identity --query "Account" --output text`

aws cloudformation deploy \
--role-arn arn:aws:iam::${ACCOUNT_ID}:role/CloudFormationRole \
--template-file cloudformation.yml \
--stack-name ${PLATFORM}-${SERVICE_NAME}-${Env}-${EnvId} \
--capabilities CAPABILITY_NAMED_IAM \
--parameter-overrides \
Platform=${PLATFORM} \
ServiceName=${SERVICE_NAME} \
Env=${Env} \
EnvId=${EnvId} \
Version=${Version}

#Upload dist files
cd dist/apps
echo "Get environment config"
ENV_JS_PARAM_NAME="/site-config/${SERVICE_NAME}.${Env}-${EnvId}/env.js"
ENV_JS=$(aws ssm get-parameter --region "${REGION}" --name "${ENV_JS_PARAM_NAME}" --output text --query Parameter.Value)

echo "${ENV_JS}" > ${APP_NAME}/env.js
echo "Deploy application"
HOSTING_BUCKET_NAME=$(aws ssm get-parameter --region "${REGION}" --name "/${PLATFORM}/${Env}/${EnvId}/${SERVICE_NAME}/hosting/bucketName" --output text --query Parameter.Value)
HOSTING_DISTRIBUTION=$(aws ssm get-parameter --region "${REGION}" --name "/${PLATFORM}/${Env}/${EnvId}/${SERVICE_NAME}/hosting/distribution" --output text --query Parameter.Value)

aws s3 sync ${APP_NAME} s3://${HOSTING_BUCKET_NAME}/${HOSTING_PATH}/ --delete

unset AWS_DEFAULT_PROFILE
