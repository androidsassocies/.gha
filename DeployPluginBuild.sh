#!/bin/bash
shopt -s extglob # required to use cp with exclude pattern

# How to use this script.
usage="$(basename "$0") [-h] [-r ROOT] [-t TARGET] [-v VERSION] [-c CLEAN] [-s SOURCE]
Deploy an unreal plugin build to target path
where:
    -h  show this help text
    -r  plugin root directory where .uplugin description file is (default '.')
    -t  target path to deploy
    -v  engine version of the plugin (e.g. '5.5')
    -c  do a clean deployment, removing target directory content to ensure no files is kept from an older deployment (default 'false')
    -s  if want to deploy the source code too (default 'false')"

# Constants.
ROOT="."
CLEAN=false
SOURCE=false

# Options and arguments queries.
options=':hr:t:v:cs'
while getopts $options option; do
    case "$option" in
        h) echo "$usage"; exit;;
        r) ROOT=$OPTARG;;
        t) TARGET=$OPTARG;;
        v) VERSION=$OPTARG;;
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


# Navigate to the script's directory.
pushd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Navigate to ROOT.
cd "$ROOT"

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
    cd "../.."
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

    # Return to the original directory.
    popd

    # Then navigate to plugin root.
    cd "$ROOT"

fi

# Is a descriptor version found ?
if [ "${desc_version}" ]; then

    # Check if the descriptor version and the version from args correspond, if not, abort.
    if [[ "$VERSION" != "$desc_version" ]]; then
        echo "Invalid version: the version $VERSION from argument -v does not match the version $desc_version from descriptor file"
        exit 1
    fi

fi

# Final target directory (e.g. 'C:/Shared/MyPlugins/5.5/MyC++Plugin')
TARGET=$TARGET/$VERSION/$name

# Create the final target directory if it doesn't exist
if [ ! -d "${TARGET}" ]; then
    mkdir -p "$TARGET"
fi

# List things that we want to exclude from deployment
excludes=".git|.github|.gitattributes|.gitignore|.p4ignore|.plastic|ignore.conf" # VCS
excludes="$excludes|Intermediate" # compiled source files
excludes="$excludes|.exe|.exp|.lib|.pdb" # compiled and debug files
excludes="$excludes|DeployPluginBuild.sh" # the script itself

# Exclude the source code
if [ "${SOURCE}" = false ]; then
    excludes="$excludes|Source"
fi

# Remove target directory content
if [ "${CLEAN}" = true ]; then
    rm -rf "$TARGET/"*
fi

# Copy the files from the plugin root to the final target directory
cp -fprv "$ROOT"/!($excludes) "$TARGET"

# Return to the original directory.
popd
