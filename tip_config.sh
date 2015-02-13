#!/bin/bash

function add_config() {
    read -r remote xxx <<<$(git remote)
    local uri=$(git ls-remote --get-url $remote)
    uri_parser $uri

    # only for gitolite running on remote server
    user=$(ssh $uri_address echo-user)

    branchprefix=tip/$user

    git config --remove-section pushtip
    git config --add pushtip.remote $remote
    git config --add pushtip.branchprefix $branchprefix
}

function get_config() {
    remote=$(git config --get pushtip.remote)
    branchprefix=$(git config --get pushtip.branchprefix)

    if [ -z "$remote" ] || [ -z "$branchprefix" ]; then
        echo "Config not found, trying to get it automatically"
        add_config
    fi
}

function die() {
    echo "ERROR: $1"
    exit 1
}

get_config
if [ -z "$remote" ] || [ -z "$branchprefix" ]; then
    die "Could not automatically get configuration. Set it with
         git config pushtip.remote remote-name
         git config pushtip.branchprefix tip/<your-user-on-remote>
    "
fi
