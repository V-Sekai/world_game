export RUST_LOG := "log"
export MVSQLITE_DATA_PLANE := "http://192.168.0.39:7000"
export OPERATING_SYSTEM := os()
export EDITOR_TYPE_COMMAND := "run-editor-$OPERATING_SYSTEM"
export PROJECT_PATH := "" # Can be empty

export BUILD_COUNT := "001"
export DOCKER_GOCDA_AGENT_CENTOS_8_GROUPS_GIT := "abcdefgh"  # Example hash
export GODOT_GROUPS_EDITOR_PIPELINE_DEPENDENCY := "dependency_name"

export LABEL_TEMPLATE := "docker-gocd-agent-centos-8-groups_${DOCKER_GOCDA_AGENT_CENTOS_8_GROUPS_GIT:0:8}.$BUILD_COUNT"
export GROUPS_LABEL_TEMPLATE := "groups-4.3.$GODOT_GROUPS_EDITOR_PIPELINE_DEPENDENCY.$BUILD_COUNT"
export GODOT_STATUS := "groups-4.3"
export GIT_URL_DOCKER := "https://github.com/V-Sekai/docker-groups.git"
export GIT_URL_VSEKAI := "https://github.com/V-Sekai/v-sekai-game.git"
export WORLD_PWD := invocation_directory()
export SCONS_CACHE := "/app/.scons_cache"

deploy_just_docker:
    set windows-shell := ["powershell.exe", "-NoLogo", "-Command"]
    @just build_just_docker
    docker run -it --rm -v $WORLD_PWD:/app just-fedora-app

run-godot-local:
    @just build-godot-local
    ./godot/bin/godot.macos.editor.arm64 --path sandbox_demo -e

list_files:
    ls export_windows
    ls export_linuxbsd

deploy_game:
    echo "Deploying game binaries..."

copy_binaries:
    cp templates/windows_release_x86_64.exe export_windows/v_sekai_windows.exe
    cp templates/linux_release.x86_64 export_linuxbsd/v_sekai_linuxbsd

prepare_exports:
    rm -rf export_windows export_linuxbsd
    mkdir export_windows export_linuxbsd

generate_build_constants:
    echo "## AUTOGENERATED BY BUILD" > v/addons/vsk_version/build_constants.gd
    echo "" >> v/addons/vsk_version/build_constants.gd
    echo "const BUILD_LABEL = \"$GROUPS_LABEL_TEMPLATE\"" >> v/addons/vsk_version/build_constants.gd
    echo "const BUILD_DATE_STR = \"$(shell date --utc --iso=seconds)\"" >> v/addons/vsk_version/build_constants.gd
    echo "const BUILD_UNIX_TIME = $(shell date +%s)" >> v/addons/vsk_version/build_constants.gd

clone_repo_vsekai:
    if [ ! -d "v" ]; then \
        git clone $GIT_URL_VSEKAI v; \
    else \
        git -C v pull origin main; \
    fi

push_docker:
    set -x; \
    docker push "groupsinfra/gocd-agent-centos-8-groups:$LABEL_TEMPLATE" && \
    echo "groupsinfra/gocd-agent-centos-8-groups:$LABEL_TEMPLATE" > docker_image.txt

build_just_docker:
    docker build --platform linux/x86_64 -t just-fedora-app . --cache-from just-fedora-app:latest

deploy_osxcross:
    #!/usr/bin/env bash
    git clone https://github.com/tpoechtrager/osxcross.git || true
    cd osxcross
    ./tools/gen_sdk_package.sh 

build_docker:
    set -x; \
    docker build -t "groupsinfra/gocd-agent-centos-8-groups:$LABEL_TEMPLATE" "g/gocd-agent-centos-8-groups"

clone_repo:
    if [ ! -d "g" ]; then \
        git clone $GIT_URL_DOCKER g; \
    else \
        git -C g pull origin master; \
    fi

run-editor:
    @just build-godot
    @just {{ EDITOR_TYPE_COMMAND }}

build-all:
    #!/usr/bin/env bash
    export PATH=/llvm-mingw-20240917-ucrt-ubuntu-20.04-x86_64/bin:$PATH
    parallel --ungroup --jobs 4 '
        platform={1}
        target={2}
        cd godot
        case "$platform" in
            windows)
                EXTRA_FLAGS="LINKFLAGS='\''-Wl,-pdb='\'' CCFLAGS='\''-gcodeview'\''"
                ;;
            mac)
                EXTRA_FLAGS="OSXCROSS_ROOT='\''/osxcross'\'' osxcross_sdk=darwin24 vulkan=no arch=$arch"
                ;;
            linux|android)
                EXTRA_FLAGS="use_llvm=yes linker=mold"
                ;;
            web)
                EXTRA_FLAGS="threads=yes linker=mold lto=none dlink_enabled=yes builtin_glslang=yes builtin_openxr=yes module_raycast_enabled=no module_speech_enabled=no javascript_eval=no"
                ;;
        esac        
        scons platform=$platform \
            werror=no \
            compiledb=yes \
            generate_bundle=yes \
            precision=double \
            target=$target \
            test=yes \
            debug_symbol=yes \
            $EXTRA_FLAGS
        case "$platform" in
            android)
                if [ "$target" = "editor" ]; then
                    cd platform/android/java
                    ./gradlew generateGodotEditor
                    ./gradlew generateGodotHorizonOSEditor
                    cd ../../..
                    ls -l bin/android_editor_builds/
                elif [ "$target" = "template_release" ] || [ "$target" = "template_debug" ]; then
                    cd platform/android/java
                    ./gradlew generateGodotTemplates
                    cd ../../..
                    ls -l bin/
                fi
                ;;
        esac
    ' ::: android web windows linux macos \
    ::: editor template_release template_debug

build-godot-local:
    #!/usr/bin/env bash
    cd godot 
    scons platform=$OPERATING_SYSTEM \
    use_mingw=yes \
    use_llvm=yes \
    werror=no \
    vulkan=no \
    compiledb=yes \
    dev_build=no \
    generate_bundle="no" \
    precision=single \
    target="editor" \
    test=yes \
    debug_symbol="on"

run-godot-local-windows:
    @just build-godot-local
    ./godot/bin/godot.windows.editor.x86_64 --path sandbox_demo -e

build_vsekai:
    just clone_repo_vsekai generate_build_constants prepare_exports copy_binaries list_files

deploy_vsekai:
    just deploy_game

full_build_deploy:
    just build_vsekai deploy_vsekai build_docker push_docker
