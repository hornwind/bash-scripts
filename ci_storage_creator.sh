#!/usr/bin/env bash

# set -e
# set -x

f_check_env() {
    if [[ -z $STORAGE_USER || -z $STORAGE_USER_PASS ]]; then
        echo "please set STORAGE_USER or STORAGE_USER_PASS"
        exit 1
    fi
    if [[ -z $STORAGE_CLIENT_USER || -z $STORAGE_CLIENT_PASS ]]; then
        echo "please set STORAGE_CLIENT_USER or STORAGE_CLIENT_PASS"
        exit 1
    fi
}

f_obtain_token() {
    curl -s -XPOST https://api.selcdn.ru/v3/auth/tokens -d "{\"auth\": { \"identity\": { \"methods\": [\"password\"], \"password\": { \"user\": { \"id\": \"$STORAGE_USER\", \"password\": \"$STORAGE_USER_PASS\"}}}}}" | jq -r '.token.user.id'
}

f_obtain_client_token() {
    curl -s -XPOST https://api.selcdn.ru/v3/auth/tokens -d "{\"auth\": { \"identity\": { \"methods\": [\"password\"], \"password\": { \"user\": { \"id\": \"$STORAGE_USER_CONCAT\", \"password\": \"$STORAGE_CLIENT_PASS\"}}}}}" | jq -r '.token.user.id'
}

######### user functions

f_get_user() {
    curl -s 'https://api.selcdn.ru/v1/users?format=json' -H "X-Auth-Token: $STORAGE_TOKEN" | jq ".Users[] | select(.Name == \"$STORAGE_CLIENT_USER\")"
}

f_check_client_user_exisis() {
    if [[ -z $(f_get_user) ]]; then
        echo "false"
    else
        echo "true"
    fi
}

f_get_client_user_active() {
    f_get_user | jq '.Active'
}

f_get_client_user_s3() {
    f_get_user | jq '.IsS3User'
}

f_create_client_user() {
    curl -i -XPUT "https://api.selcdn.ru/v1/users/$STORAGE_CLIENT_USER" -H "X-Auth-Token: $STORAGE_TOKEN" -H "X-Auth-Key: $STORAGE_CLIENT_PASS" -H "X-User-Active: on" -H "X-User-S3-Password: yes" -H "X-User-ACL-Containers-W: $STORAGE_CLIENT_CONTAINER"
    sleep 3
    if [[ "$(f_check_client_user_exisis)" == "true" ]]; then
        echo ""
        echo "client create successful:"
        f_get_user
    else
        echo "client create error!"
        exit 1
    fi
}

######### container functions

f_get_list_all_containers() {
    curl -s "https://api.selcdn.ru/v1/SEL_$STORAGE_USER?format=json" -H "X-Auth-Token: $STORAGE_TOKEN"
}

f_get_container() {
    curl -s "https://api.selcdn.ru/v1/SEL_$STORAGE_USER?format=json" -H "X-Auth-Token: $STORAGE_TOKEN" | jq ".[] | select(.name == \"$STORAGE_CLIENT_CONTAINER\")"
}

f_check_client_container_exists() {
    if [[ -z $(f_get_container) ]]; then
        echo "false"
    else
        echo "true"
    fi
}

f_create_client_container() {
    if [[ "$(f_check_client_container_exists)" == "false" ]]; then
        curl -i -XPUT "https://api.selcdn.ru/v1/SEL_$STORAGE_USER/$STORAGE_CLIENT_CONTAINER" -H "X-Auth-Token: $STORAGE_TOKEN" -H "X-Container-Meta-Type: private"
        sleep 3
        echo ""
        if [[ "$(f_check_client_container_exists)" == "true" ]]; then
            echo "container create successful:"
            f_get_container
            echo ""
        else
            echo "container create error!"
            exit 1
        fi
    else
        echo "container already exists:"
        f_get_container
    fi
}

######### check client

f_client_get_container() {
    curl -s "https://api.selcdn.ru/v1/SEL_$STORAGE_USER?format=json" -H "X-Auth-Token: $STORAGE_CLIENT_TOKEN" | jq ".[] | select(.name == \"$STORAGE_CLIENT_CONTAINER\")" 2>/dev/null
}

f_client_check_container_available() {
    if [[ -z $(f_client_get_container) ]]; then
        echo "false"
    else
        echo "true"
    fi
}

#########

main() {
    command -v jq >/dev/null 2>&1 || {
        echo "jq is not installed. Aborting." >&2
        exit 1
        }

    f_check_env

    export STORAGE_USER_CONCAT="$STORAGE_USER"_"$STORAGE_CLIENT_USER"
    export STORAGE_TOKEN=$(f_obtain_token)
    # echo "TOKEN: $STORAGE_TOKEN"
    echo "client user exist: $(f_check_client_user_exisis)"
    echo "client user active: $(f_get_client_user_active)"
    echo "client user s3: $(f_get_client_user_s3)"
    echo ""
    echo "client container exists: $(f_check_client_container_exists)"

    if [[ -z $(f_get_container) ]]; then
        echo "creating container..."
        f_create_client_container
    fi

    if [[ -z $(f_get_user) ]]; then
        echo "creating user..."
        f_create_client_user
    fi

    export STORAGE_CLIENT_TOKEN=$(f_obtain_client_token)
    # echo "CLIENT TOKEN: $STORAGE_CLIENT_TOKEN"

    if [[ "$(f_get_client_user_s3)" != "true" ]]; then
        echo "changing user..."
        echo ""
        f_create_client_user
        export STORAGE_CLIENT_TOKEN=$(f_obtain_client_token)
        echo "client user s3: $(f_get_client_user_s3)"
    fi

    echo "client container available: $(f_client_check_container_available)"
    echo ""

    if [[ "$(f_client_check_container_available)" != "true" ]]; then
        echo "changing user..."
        echo ""
        f_create_client_user
        export STORAGE_CLIENT_TOKEN=$(f_obtain_client_token)
        echo "client container available: $(f_client_check_container_available)"
    fi

    if [[ "$(f_client_check_container_available)" != "true" ]]; then
        exit 1
    fi
}

main "$@"
