#!/usr/bin/env bash

nix build "$@" --max-jobs 1 --cores 1
