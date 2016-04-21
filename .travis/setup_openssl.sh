#! /bin/bash

source .travis/platform.sh

cd $TRAVIS_BUILD_DIR

git clone --depth=1 --recursive https://github.com/zhaozg/lua-openssl.git

cd lua-openssl

luarocks make rockspecs/openssl-scm-1.rockspec

cd $TRAVIS_BUILD_DIR
