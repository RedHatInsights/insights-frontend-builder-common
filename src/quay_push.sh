IMAGE_NAME=$APP_NAME
if [[ ! $IMAGE_NAME == *"-frontend"* ]]; then
    IMAGE_NAME="$IMAGE_NAME-frontend"
fi

# copy from bellow
if [[ ! -z "${DOCKER_TOKEN}" ]]; then

    # let's build the docker image
    docker build . -t ${IMAGE_NAME}

    # mark it for quay push
    docker tag ${IMAGE_NAME} quay.io/redhat-cloud-services/${IMAGE_NAME}

    # mark it for quay push and tag it with git hash
    docker tag ${IMAGE_NAME} quay.io/redhat-cloud-services/${IMAGE_NAME}:${SRC_HASH}

    # mark it for quay push and tag it with git branch
    docker tag ${IMAGE_NAME} quay.io/redhat-cloud-services/${IMAGE_NAME}:${GIT_BRANCH}

    # login to quay
    echo $DOCKER_TOKEN | docker login quay.io --username \$oauthtoken --password-stdin

    #push tags to quay
    docker push quay.io/redhat-cloud-services/${IMAGE_NAME}
    docker push quay.io/redhat-cloud-services/${IMAGE_NAME}:${SRC_HASH}
    docker push quay.io/redhat-cloud-services/${IMAGE_NAME}:${GIT_BRANCH}
fi
