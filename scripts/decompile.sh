#!/usr/bin/env bash

(
set -e
PS1="$"
basedir="$(cd "$1" && pwd -P)"
workdir="$basedir/base"
minecraftversion=$(cat "$workdir/Paper/BuildData/info.json"  | grep minecraftVersion | cut -d '"' -f 4)
windows="$([[ "$OSTYPE" == "cygwin" || "$OSTYPE" == "msys" ]] && echo "true" || echo "false")"
decompiledir="$workdir/mc-dev"
spigotdecompiledir="$decompiledir/spigot"
forgedecompiledir="$decompiledir/forge"
forgeflowerversion="1.5.605.17"
forgeflowerurl="https://maven.minecraftforge.net/net/minecraftforge/forgeflower/$forgeflowerversion/forgeflower-$forgeflowerversion.jar"
# temp use patched version
#forgeflowerurl="https://zachbr.keybase.pub/paper/forgeflower-patched/forgeflower-1.5.380.19.jar?dl=1"
forgeflowerbin="$workdir/ForgeFlower/$forgeflowerversion.jar"
# TODO: Make this better? We don't need spigot compat for this stage
forgefloweroptions="-dgs=1 -hdc=0 -asc=1 -udv=1 -jvn=1"
forgeflowercachefile="$decompiledir/forgeflowercache"
forgeflowercachevalue="$forgeflowerurl - $forgeflowerversion - $forgefloweroptions";
classdir="$decompiledir/classes"
versionjson="$workdir/mc-dev/$minecraftversion.json"

if [[ ! -f "$versionjson" ]]; then
    echo "Downloading $minecraftversion JSON Data"
    verescaped=$(echo ${minecraftversion} | sed 's/\-pre/ Pre-Release /g' | sed 's/\./\\./g')
    urlescaped=$(echo ${verescaped} | sed 's/ /_/g')
    verentry=$(curl -s "https://launchermeta.mojang.com/mc/game/version_manifest.json" | grep -oE "\{\"id\": \"${verescaped}\".*${urlescaped}\.json")
    jsonurl=$(echo $verentry | grep -oE https:\/\/.*\.json)
    curl -o "$versionjson" "$jsonurl"
    echo "$versionjson - $jsonurl"
fi

function downloadLibraries {
    group=$1
    groupesc=$(echo ${group} | sed 's/\./\\./g')
    grouppath=$(echo ${group} | sed 's/\./\//g')
    libdir="$decompiledir/libraries/${group}/"
    mkdir -p "$libdir"
    shift
    for lib in "$@"
    do
        jar="$libdir/${lib}-sources.jar"
        destlib="$libdir/${lib}"
        if [ ! -f "$jar" ]; then
            libesc=$(echo ${lib} | sed 's/\./\\]./g')
            ver=$(grep -oE "${groupesc}:${libesc}:[0-9\.]+" "$versionjson" | sed "s/${groupesc}:${libesc}://g")
            echo "Downloading ${group}:${lib}:${ver} Sources"
            curl -s -o "$jar" "https://libraries.minecraft.net/${grouppath}/${lib}/${ver}/${lib}-${ver}-sources.jar"
            set +e
            grep "<html>" "$jar" && grep -oE "<title>.*?</title>" "$jar" && rm "$jar" && echo "Failed to download $jar" && exit 1
            set -e
        fi

        if [ ! -d "$destlib/$grouppath" ]; then
            echo "Extracting $group:$lib Sources"
            mkdir -p "$destlib"
            (cd "$destlib" && jar xf "$jar")
        fi
    done
}

downloadLibraries "com.mojang" authlib

# prep folders
#mkdir -p "$workdir/ForgeFlower"
mkdir -p "$spigotdecompiledir"
mkdir -p "$forgedecompiledir"

echo "Extracting NMS classes..."
if [ ! -d "$classdir" ]; then
    mkdir -p "$classdir"
    cd "$classdir"
    set +e
    jar xf "$decompiledir/$minecraftversion-mapped.jar" net/minecraft yggdrasil_session_pubkey.der assets
    if [ "$?" != "0" ]; then
        cd "$basedir"
        echo "Failed to extract NMS classes."
        exit 1
    fi
    set -e
fi

#needsDecomp=0
#if [ ! -f "$forgeflowercachefile" ]; then
#    needsDecomp=1
#elif [ "$(cat ${forgeflowercachefile})" != "$forgeflowercachevalue" ]; then
#    needsDecomp=1
#fi
#if [ "$needsDecomp" == "1" ]; then
#    # our local cache is now invalidated, we can update forgeflower to get better deobfuscation
#    rm -rf "$forgedecompiledir/net"
#fi
#
# Forge (for Paper mc-dev imports, and dev src folders for unimported files)
#if [ ! -d "$forgedecompiledir/net" ] ; then
#    echo "Decompiling classes (stage 1)..."
#    cd "$basedir"
#
#    if [ ! -f "$forgeflowerbin" ]; then
#        echo "Downloading ForgeFlower ($forgeflowerversion)..."
#        curl -s -o "$forgeflowerbin" "$forgeflowerurl"
#    fi
#
#    set +e
#    java -Ddecomp.renameparams=true -jar "$forgeflowerbin" ${forgefloweroptions} -ind='    ' "$classdir" "$forgedecompiledir"
#    if [ "$?" != "0" ]; then
#        rm -rf "$forgedecompiledir/net"
#        echo "Failed to decompile classes."
#        exit 1
#    fi
#    echo "$forgeflowercachevalue" > "$forgeflowercachefile"
#    set -e
#fi

# Spigot (for CraftBukkit patches)

# if we see the old net folder, copy it to spigot to avoid redecompiling
if [ -d "$decompiledir/net" ]; then
    cp -r "$decompiledir/net" "$spigotdecompiledir/"
fi

if [ ! -d "$spigotdecompiledir/net" ]; then
    echo "Decompiling classes (stage 2)..."
    cd "$basedir"
    set +e
    java -jar "$workdir/Paper/BuildData/bin/fernflower.jar" -dgs=1 -hdc=0 -rbr=0 -asc=1 -udv=0 "$classdir" "$spigotdecompiledir"
    if [ "$?" != "0" ]; then
        rm -rf "$spigotdecompiledir/net"
        echo "Failed to decompile classes."
        exit 1
    fi
    set -e
fi
)
