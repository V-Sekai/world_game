export RUST_LOG := "log"
export MVSQLITE_DATA_PLANE := "http://192.168.0.39:7000"
export OPERATING_SYSTEM := os()
export ANDROID_HOME_COMMAND := "set-android-home-$OPERATING_SYSTEM"
export EDITOR_TYPE_COMMAND := "run-editor-$OPERATING_SYSTEM"
export PROJECT_PATH := "farm_chickens"

default: run-editor

set-android-home:
    @just {{ ANDROID_HOME_COMMAND }}

set-android-home-linux:
    export ANDROID_HOME="/usr/local/share/android-sdk"

set-android-home-windows:
    export ANDROID_HOME="C:/Users/ernest.lee/AppData/Local/Android/Sdk"

build-godot:
    cd godot && scons werror=no compiledb=yes dev_build=no generate_bundle=no precision=double target=editor tests=yes debug_symbols=yes

run-editor:
    @just build-godot
    @just {{ EDITOR_TYPE_COMMAND }}

run-editor-macos:
    ./godot/bin/godot.macos.editor.double.arm64 --path ${PROJECT_PATH} -e --display-driver macos --rendering-driver vulkan

run-editor-linux:
    ./godot/bin/godot.linux.editor.double.x86_64 --path ${PROJECT_PATH} -e

run-editor-windows:
    ./godot/bin/godot.windows.editor.double.x86_64 --path ${PROJECT_PATH} -e
