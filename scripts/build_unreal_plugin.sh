#!/bin/bash

# /!\ This script requires aliases to work.
# /!\ Be aware that aliases doesn't work in non-interactive shells.
# /!\ https://unix.stackexchange.com/questions/1496/why-doesnt-my-bash-script-recognize-aliases
# /!\ So launch this script in cmd with -i argument for interactive mode.
# /!\ >>> sh -i generate_plugin_build.sh

#TODO: Make the script work if we give the .uplugin file as -p argument.

# Redefine pushd to silent.
pushd () {
    command pushd "$@" >/dev/null
}
# Redefine popd to silent.
popd () {
    command popd "$@" >/dev/null
}

# How to use this script.
usage="$(basename "$0") [-h] [-v VERSION] [-p PLUGIN] [-t TARGET]
Generate an unreal plugin build for specified version to target package path
where:
    -h  show this help text.
    -v  engine version of the plugin. (e.g. '5.5')
    -p  plugin root directory where .uplugin description file is. (default '.')
    -t  target package path to build. (e.g. 'C:/MyPackagedPlugins/MyPlugin')"

# Constants.
PLUGIN="."

# Options and arguments queries.
options=':hv:p:t:'
while getopts $options option; do
    case "$option" in
        h) echo "$usage"; exit;;
        v) VERSION=$OPTARG;;
        p) PLUGIN=$OPTARG;;
        t) TARGET=$OPTARG;;
        :) printf "missing argument for -%s\n" "$OPTARG" >&2; echo "$usage" >&2; exit 1;;
        \?) printf "illegal option: -%s\n" "$OPTARG" >&2; echo "$usage" >&2; exit 1;;
   esac
done

# Mandatory arguments.
if [ ! "$VERSION" ]; then
  echo "argument -v must be provided"
  echo "$usage" >&2; exit 1
fi

# Navigate to the script's directory.
pushd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Navigate to PLUGIN.
pushd "$(cd "$PLUGIN" && pwd)"

# Find .uplugin descriptor file.
uplugin=$(find -type f -name '*.uplugin' -print -quit)

# Verify it finds something to continue (which means we are in a valid plugin), if not, abort.
if [ -z "${uplugin}" ]; then
    echo "Invalid plugin: no .plugin descriptor file found" >&2
    exit 1
fi

# Get the plugin name.
name=$(basename "$uplugin" .uplugin)

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
        echo "Invalid version: the version $VERSION from argument -v does not match the version $desc_version from descriptor file" >&2
        exit 1
    fi
fi

# Resolved .plugin file. (e.g. 'C:/MyPlugin/MyPlugin.uplugin')
# We can't give relative path to RunUAT, we need paths to be absolute.
PLUGIN=$(pwd)
UPLUGIN=$(pwd)/"$name".uplugin

# If none target package path provided, we will create the build at the top path level of the plugin.
if [ -z "${TARGET}" ]; then
    # Navigate to the top folder of PLUGIN.
    pushd ".."

    # We can't give relative path to RunUAT, we need paths to be absolute.
    TARGET=$(pwd)/_pkg

    # Create the package directory.
    if ! mkdir -p "$TARGET"; then
        exit 1
    fi

    # Return to the previous location.
    popd
fi

# Is target package path a directory ?
if [ ! -d "$TARGET" ]; then
    echo "Target package path $TARGET is not a directory, aborting"
    exit 1
fi

# Check write permission on the target directory.
if [ ! -w "$TARGET" ]; then
    echo "Target package path $TARGET does not have write permission, aborting" >&2
    exit 1
fi

# Platform-specific logic.
case "$(uname)" in
    # Windows
    MINGW*|MSYS*|CYGWIN*)
        launcher_installed_file_path="C:\ProgramData\Epic\UnrealEngineLauncher\LauncherInstalled.dat"
        ;;
    # MacOS
    Darwin)
        launcher_installed_file_path="??"
        ;;
    # Linux
    Linux)
        echo "Unsupported platform: $(uname). Epic Games does not offer Epic Games Launcher on Linux" >&2
        exit 1
        ;;
    *)
        echo "Unsupported platform: $(uname)" >&2
        exit 1
        ;;
esac

# We can't find the .dat file belong to Epic Games launcher which list all epic games installations.
if [ ! -f "${launcher_installed_file_path}" ]; then
    echo "Epic Game Launcher is not installed, aborting" >&2
    exit 1
fi

# Bash does not support representing sequences (list or arrays) or associative arrays
# This makes representing the result of parsing JSON somewhat tricky.
# We do need to use a tool designed for this task, like jq.
# https://stackoverflow.com/questions/1955505/parsing-json-with-unix-tools

function cleanup {
    # Clean up.
    rm -fv "$JQ_TO_DELETE" >&2
}

# Is jq available ?
# https://stackoverflow.com/questions/592620/how-can-i-check-if-a-program-exists-from-a-bash-script
if ! [ "$(type "jq")" ]; then

    # So navigate to the script's directory.
    pushd "$(dirname "${BASH_SOURCE[0]}")"

    # Is jq already installed by this script previously ?
    if [ ! -f ./jq.exe ]; then

        # And install jq next to it.
        curl -L -o ./jq.exe https://github.com/jqlang/jq/releases/latest/download/jq-win64.exe

        # Keep reference for cleaning.
        JQ_TO_DELETE=$(pwd)/jq.exe

        # Make the cleanup function run even if the script exits due to errors.
        trap cleanup EXIT

        # Create a jq alias to use it anywhere as expected.
        # /!\ Aliases are not expanded in non-interactive shells.
        # /!\ See header comment.
        alias jq=$(pwd)/jq.exe

        # Check again if the installation was successful.
        if ! [ "$(type "jq")" ]; then
            echo "Error: jq is still not available, aborting
       (This script requires aliases to work. Be aware that aliases doesn't work in non-interactive shells, did you run the script in an non-interactive shell ? With cmd you must use -i argument for interactive mode.)" >&2
            exit 1
        fi
    else
        # Create a jq alias to use it anywhere as expected.
        # /!\ Aliases are not expanded in non-interactive shells.
        # /!\ See header comment.
        alias jq=$(pwd)/jq.exe
    fi

    # Return to the previous location.
    popd
fi

# Get the data of installations from the json file only for engines.
# We don't need other entries, so filtering it.
installations=$(jq '.InstallationList[] |= select(.AppName | test("^UE_."))' "$launcher_installed_file_path")

# Get the count of filtered installations.
# [--argjson]: to pass a json variable to jq rather than a file.
# [--null-input / -n]: don't read any input at all to use jq as simple calculator.
count=$(jq --argjson data "$installations" -n '$data.InstallationList | length')

# Is there at least 1 installation ?
if [ $count == 0 ]; then
    echo "Unreal Engine is not installed, aborting"
    exit 1
fi

# Get the engine install location corresponding to VERSION if any, by filtering the filtered installations.
engine_install_location=$(jq --argjson data "$installations" --arg version "$VERSION" -n '$data.InstallationList[] | select(.AppName | contains($version))' | jq .InstallLocation)

# Check if we found one, otherwise, there is no install for this VERSION.
if [ -z "${engine_install_location}" ]; then
    echo "Unreal Engine $VERSION is not installed, aborting"
    exit 1
fi

# Remove outermost quotes from json to make the path usable.
engine_install_location="${engine_install_location#\"}"
engine_install_location="${engine_install_location%\"}"

# Navigate to the engine install location.
pushd "$engine_install_location/Engine"

# Determine the platform-specific path for RunUAT.
if [[ "$OSTYPE" == "darwin"* ]]; then
    RUN_UAT_PATH="./Build/Mac/RunUAT.sh"
elif [[ "$OSTYPE" == "linux"* ]]; then
    RUN_UAT_PATH="./Build/Linux/RunUAT.sh"
elif [[ "$OSTYPE" == "msys" ]]; then
    RUN_UAT_PATH="./Build/BatchFiles/RunUAT.bat"
else
    echo "Unsupported platform: $OSTYPE"
    exit 1
fi

cleanup

# Let's build.
"$RUN_UAT_PATH" BuildPlugin -plugin="$UPLUGIN" -package="$TARGET"

# Copy the files we want to get from the newly built package to the source plugin.
echo "Copying from $TARGET to $PLUGIN:" >&2
cp -fprv "$TARGET"/Binaries "$PLUGIN"
cp -fprv "$TARGET"/Intermediate "$PLUGIN"

# We finished with the built package and get back what we needed, so remove it.
echo "removed $TARGET" >&2
rm -rfdv "$TARGET" >/dev/null

# Raise any error
if [ $? -ne 0 ]; then
    exit $?
fi

# Return to the original directory.
popd
