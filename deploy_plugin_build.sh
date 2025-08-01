#!/bin/bash
shopt -s extglob # required to use cp with exclude pattern.

# Redefine pushd to silent.
pushd () {
    command pushd "$@" > /dev/null
}
# Redefine popd to silent.
popd () {
    command popd "$@" > /dev/null
}

# How to use this script.
usage="$(basename "$0") [-h] [-r ROOT] [-t TARGET] [-v VERSION] [-o OVERWRITE] [-c CLEAN] [-s SOURCE]
Deploy an unreal plugin build to target path
where:
    -h  show this help text.
    -r  plugin root directory where .uplugin description file is. (default '.')
    -t  target path to deploy. (e.g. 'C:/Shared/MyPlugins')
    -v  engine version of the plugin. (e.g. '5.5')
    -o  overwrite existing unreal plugin at target path. (default 'false')
    -c  do a clean deployment by removing target directory content before deploying to ensure no files is kept from an older deployment. (default 'false')
    -s  to deploy the source code too. (default 'false')"

# Constants.
ROOT="."
OVERWRITE=false
CLEAN=false
SOURCE=false

# Options and arguments queries.
options=':hr:t:v:ocs'
while getopts $options option; do
    case "$option" in
        h) echo "$usage"; exit;;
        r) ROOT=$OPTARG;;
        t) TARGET=$OPTARG;;
        v) VERSION=$OPTARG;;
        o) OVERWRITE=true;;
        c) CLEAN=true;;
        s) SOURCE=true;;
        :) printf "missing argument for -%s\n" "$OPTARG" >&2; echo "$usage" >&2; exit 1;;
        \?) printf "illegal option: -%s\n" "$OPTARG" >&2; echo "$usage" >&2; exit 1;;
   esac
done

# Mandatory arguments.
if [ ! "$TARGET" ] || [ ! "$VERSION" ]; then
  echo "arguments -t and -v must be provided"
  echo "$usage" >&2; exit 1
fi

# Is target path a directory ?
if [ ! -d "$TARGET" ]; then
    echo "Target path $TARGET is not a directory, abort"
    exit 1
fi

# Do we have the correct permissions to do so ? "-rwxr-xr-x" is "755" in octal.
# if [ ! "$(stat -c '%A' "${TARGET}")" == "drwxr-xr-x" ]; then
#     echo "Target path $TARGET does not have correct permissions, abort"
#     exit 1
# fi

# Check write permission on the target directory.
if [ ! -w "$TARGET" ]; then
    echo "Target path $TARGET does not have write permission, abort"
    exit 1
fi

# Navigate to the script's directory.
pushd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Navigate to ROOT.
pushd "$(cd "$ROOT" && pwd)"

# Find .uplugin descriptor file.
uplugin=$(find -type f -name '*.uplugin' -print -quit)

# Verify it finds something to continue (which means we are in a valid plugin), if not, abort.
if [ -z "${uplugin}" ]; then
    echo "Invalid plugin: no .plugin descriptor file found"
    exit 1
fi

# Get the plugin name.
name=$(basename "$uplugin" .uplugin)

# Get the plugin root.
ROOT=$(dirname "$uplugin")

# Get the version from .uplugin descriptor file if any.
while IFS="" read -r line; do
    if [[ $line == *"EngineVersion"* ]]; then
      desc_version=${line##*:}
      desc_version=${desc_version:2:3}
    fi
done < $uplugin

# If no version provided by the .uplugin descriptor file, check if we are inside an unreal project to find one.
if [ -z "${desc_version}" ]; then
    # In theory, if we are inside a 'Plugins' folder inside an unreal project, we take back 2 levels.
    pushd "../.."
    # Find .uproject descriptor file.
    uproject=$(find -type f -name '*.uproject' -print -quit)

    # Get the version from .uproject descriptor file if any.
    if [ "${uproject}" ]; then
        while IFS="" read -r line; do
            if [[ $line == *"EngineAssociation"* ]]; then
              desc_version=${line##*:}
              desc_version=${desc_version:2:3}
            fi
        done < $uproject
    fi

    # Return to the plugin root.
    popd

fi

# Is a descriptor version found ?
if [ "${desc_version}" ]; then

    # Check if the descriptor version and the version from args correspond, if not, abort.
    if [[ "$VERSION" != "$desc_version" ]]; then
        echo "Invalid version: the version $VERSION from argument -v does not match the version $desc_version from descriptor file"
        exit 1
    fi
fi

# Final target directory. (e.g. 'C:/Shared/MyPlugins/5.5/MyC++Plugin')
TARGET=$TARGET/$VERSION/$name

# List things that we want to exclude from deployment.
excludes=".git|.github|.gitattributes|.gitignore|.p4ignore|.plastic|ignore.conf" # VCS
excludes="$excludes|.gha" # Github Actions reusable workflows
excludes="$excludes|Intermediate" # compiled source files
excludes="$excludes|.exe|.exp|.lib|.pdb" # compiled and debug files

# Exclude the source code
if [ "${SOURCE}" = false ]; then
    excludes="$excludes|Source"
fi

# Create the final target directory if it doesn't exist.
if [ ! -d "${TARGET}" ]; then
    echo "Final target directory $TARGET does not exist, create it"
    if ! mkdir -p "$TARGET"; then
        exit 1
    fi
else
    # The final target directory exists but what says argument -o ?
    if [ "${OVERWRITE}" = false ]; then
        echo "Final target directory $TARGET already exists, abort. See [-o OVERWRITE]"
        exit 1
    else
        echo "Final target directory $TARGET already exists, overwrite it"
        # Remove final target directory content first if argument -c is true.
        if [ "${CLEAN}" = true ]; then
            echo "Trying to remove its content first:"
            rm -rfdv "$TARGET/"*
        else
            echo "You should first try removing its content to avoid possible conflicts. See [-c CLEAN]"
        fi
    fi
fi

# Copy the files from the plugin root to the final target directory.
# is it better to use cp -a ?
echo "Deploying to $TARGET:"
cp -fprv "$ROOT"/!($excludes) "$TARGET"

# Raise any error
if [ $? -ne 0 ]; then
    exit $?
fi

# Return to the original directory.
popd
