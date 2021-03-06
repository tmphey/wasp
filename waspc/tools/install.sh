#!/bin/sh -e

# NOTE: Heavily inspired by get-stack.hs script for installing stack.
# https://raw.githubusercontent.com/commercialhaskell/stack/stable/etc/scripts/get-stack.sh

HOME_LOCAL_BIN="$HOME/.local/bin"
HOME_LOCAL_SHARE="$HOME/.local/share"
WASP_TEMP_DIR=
FORCE=

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force)
            FORCE="true"
            shift
            ;;
        # -d|--dest)
        #     DEST="$2"
        #     shift 2
        #     ;;
        *)
            echo "Invalid argument: $1" >&2
            exit 1
            ;;
    esac
done

main() {
    trap cleanup_temp_dir EXIT
    install_based_on_os
}

install_based_on_os() {
    case "$(uname)" in
        "Linux")
            install_from_bin_package "wasp-linux-x86_64.tar.gz"
            ;;
        "Darwin")
            install_from_bin_package "wasp-osx-x86_64.tar.gz"
            ;;
        *)
            die "Sorry, this installer does not support your operating system: $(uname)."
    esac
}

# TODO: Add option to specify which release to download.

# Download a Wasp binary package and install it in $HOME_LOCAL_BIN.
install_from_bin_package() {
    PACKAGE_URL="https://github.com/wasp-lang/wasp/releases/latest/download/$1"
    make_temp_dir
    info "Downloading binary package to temporary dir and unpacking it there..."
    dl_to_file "$PACKAGE_URL" "$WASP_TEMP_DIR/$1"
    mkdir -p "$WASP_TEMP_DIR/wasp"
    if ! tar xzf "$WASP_TEMP_DIR/$1" -C "$WASP_TEMP_DIR/wasp"; then
      die "Unpacking binary package failed."
    fi

    DATA_DST_DIR="$HOME_LOCAL_SHARE"
    create_dir_if_missing "$DATA_DST_DIR"
    BIN_DST_DIR="$HOME_LOCAL_BIN"
    create_dir_if_missing "$BIN_DST_DIR"

    # If our install locations are already occupied (by previous wasp installation or smth else),
    # inform user that they have to clean it up (or if FORCE is set, we do it for them).
    if [ -e "$DATA_DST_DIR/wasp" ]; then
        if [ "$FORCE" = "true" ]; then
            echo "Removing already existing $DATA_DST_DIR/wasp"
            rm -Ir "$DATA_DST_DIR/wasp"
        else
            die "$DATA_DST_DIR/wasp already exists, remove it manually in order to continue installation."
        fi
    fi
    if [ -e "$BIN_DST_DIR/wasp" ]; then
        if [ ! "$FORCE" = "true" ]; then
            die "$BIN_DST_DIR/wasp already exists, remove it manually in order to continue installation."
        fi
    fi

    info "Installing Wasp data to $DATA_DST_DIR..."
    if ! mv "$WASP_TEMP_DIR/wasp" "$DATA_DST_DIR/"; then
        die "Installing data to $DATA_DST_DIR failed."
    fi

    info "Installing Wasp executable to $BIN_DST_DIR..."
    # TODO: I should make sure here that $DATA_DST_DIR is abs path.
    #  It works for now because we set it to HOME_LOCAL_SHARE which
    #  we obtained using $HOME which is absolute, but if that changes
    #  and it is not absolute any more, .sh file generated below
    #  will not work properly.
    printf '#!/usr/bin/env bash\nwaspc_datadir=%s/wasp/data %s/wasp/wasp-bin "$@"\n' "$DATA_DST_DIR" "$DATA_DST_DIR" \
           > "$BIN_DST_DIR/wasp"
    if ! chmod +x "$BIN_DST_DIR/wasp"; then
        die "Failed to make $BIN_DST_DIR/wasp executable."
    fi

    info "Wasp has been successfully installed! Type 'wasp' to start wasping :)."

    if ! on_path "$BIN_DST_DIR"; then
        info "WARNING: It looks like '$BIN_DST_DIR' is not on your PATH, add it if you want to be able to invoke wasp command directly from anywhere."
    fi
}

create_dir_if_missing() {
    if [ ! -d "$1" ]; then
        info "$1 does not exist, creating it..."
        if ! mkdir -p "$1" 2>/dev/null; then
            die "Could not create directory: $1."
        fi
    fi
}

# Creates a temporary directory, which will be cleaned up automatically
# when the script finishes
make_temp_dir() {
    WASP_TEMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t wasp)"
}

# Cleanup the temporary directory if it's been created.
# Called automatically when the script exits.
cleanup_temp_dir() {
    if [ -n "$WASP_TEMP_DIR" ] ; then
        rm -rf "$WASP_TEMP_DIR"
        WASP_TEMP_DIR=""
    fi
}

# Print a message to stderr and exit with error code.
die() {
    echo "$@" >&2
    exit 1
}

info() {
    echo -e "\033[0;33m{= Wasp installer =}\033[0m" "$@"
}

# Download a URL to file using 'curl' or 'wget'.
dl_to_file() {
    if has_curl ; then
        if ! curl ${QUIET:+-sS} --fail -L -o "$2" "$1"; then
            die "curl download failed: $1"
        fi
    elif has_wget ; then
        if ! wget ${QUIET:+-q} "-O$2" "$1"; then
            die "wget download failed: $1"
        fi
    else
        die "Neither wget nor curl is available, please install one to continue."
    fi
}

# Check whether 'wget' command exists.
has_wget() {
    has_cmd wget
}

# Check whether 'curl' command exists.
has_curl() {
    has_cmd curl
}

# Check whether the given command exists.
has_cmd() {
    command -v "$1" > /dev/null 2>&1
}

# Check whether the given (query) path is listed in the PATH environment variable.
on_path() {
    # We normalize PATH and query regarding ~ by ensuring ~ is expanded to $HOME, avoiding
    # false negatives in case where ~ is expanded in query but not in PATH and vice versa.
    local PATH_BOUNDED=":$PATH:"
    local PATH_NORMALIZED="${PATH_BOUNDED//:\~/:$HOME}" # Expand all ~ that are after :
    local QUERY_NORMALIZED=":${1/#\~/$HOME}:" # Expand ~ if it is first character.
    echo "$PATH_NORMALIZED" | grep -q "$QUERY_NORMALIZED"
}

main
