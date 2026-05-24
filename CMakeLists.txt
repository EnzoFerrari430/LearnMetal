cmake_minimum_required(VERSION 3.20)
project(LearnMetal LANGUAGES CXX Swift)

# ──────────────────────────────────
# Bundle ID 前缀（改成你自己的，比如 com.yourname.learnmetal）
# ──────────────────────────────────
set(BUNDLE_ID_PREFIX "com.flisk.learnmetal" CACHE STRING "Bundle Identifier prefix")

# ──────────────────────────────────
# 平台检测：iOS (默认)
# ──────────────────────────────────
set(CMAKE_SYSTEM_NAME iOS)
set(PLATFORM_IOS TRUE)

# ──────────────────────────────────
# Swift 版本
# ──────────────────────────────────
set(CMAKE_Swift_LANGUAGE_VERSION 6.0)

# ──────────────────────────────────
# 通用配置
# ──────────────────────────────────
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ──────────────────────────────────
# 平台相关配置
# ──────────────────────────────────
if(PLATFORM_IOS)
    set(CMAKE_OSX_DEPLOYMENT_TARGET 17.0)
    set(PLATFORM_LIBS
        "-framework Metal"
        "-framework UIKit"
        "-framework MetalKit"
        "-framework QuartzCore"
    )
else()
    set(CMAKE_OSX_DEPLOYMENT_TARGET 14.0)
    set(CMAKE_OSX_SYSROOT macosx)
    set(PLATFORM_LIBS
        "-framework Metal"
        "-framework Cocoa"
        "-framework MetalKit"
        "-framework QuartzCore"
    )
endif()

# ──────────────────────────────────
# 开发者签名 Team ID（留空时 Xcode 自动处理，或通过 -DDEVELOPMENT_TEAM=xxx 指定）
# ──────────────────────────────────
set(DEVELOPMENT_TEAM "" CACHE STRING "Apple Developer Team ID (e.g. ABC123DEFG)")

# ──────────────────────────────────
# 辅助函数：为 target 添加资源文件（打包到 .app bundle 中）
# ──────────────────────────────────
function(target_add_resources TARGET_NAME)
    foreach(res IN LISTS ARGN)
        get_filename_component(res_abs ${res} ABSOLUTE)
        # 计算相对于 resources/ 的路径，作为 bundle 中的存放位置
        file(RELATIVE_PATH res_rel "${CMAKE_SOURCE_DIR}" "${res_abs}")
        string(REGEX REPLACE "^resources/" "" res_bundle_path "${res_rel}")
        get_filename_component(res_dir "${res_bundle_path}" DIRECTORY)
        set_source_files_properties(${res_abs} PROPERTIES
            MACOSX_PACKAGE_LOCATION "${res_dir}"
        )
        target_sources(${TARGET_NAME} PRIVATE ${res_abs})
    endforeach()
endfunction()

# ──────────────────────────────────
# 辅助函数：快速创建 Metal 可执行文件
# ──────────────────────────────────
function(add_metal_executable TARGET_NAME)
    cmake_parse_arguments(ARG "" "" "RESOURCES" ${ARGN})
    add_executable(${TARGET_NAME} ${ARG_UNPARSED_ARGUMENTS})
    if(PLATFORM_IOS)
        set_target_properties(${TARGET_NAME} PROPERTIES
            MACOSX_BUNDLE TRUE
            MACOSX_BUNDLE_GUI_IDENTIFIER "${BUNDLE_ID_PREFIX}.${TARGET_NAME}"
            XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${BUNDLE_ID_PREFIX}.${TARGET_NAME}"
            XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic"
        )
        set_target_properties(${TARGET_NAME} PROPERTIES
            GENERATED_INFO_PLIST_FILE ""
        )
    endif()
    target_link_libraries(${TARGET_NAME} PRIVATE ${PLATFORM_LIBS})
    target_compile_options(${TARGET_NAME} PRIVATE "-parse-as-library")
    set_target_properties(${TARGET_NAME} PROPERTIES
        XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE "NO"
        XCODE_ATTRIBUTE_INFOPLIST_FILE "${CMAKE_SOURCE_DIR}/Info.plist"
    )
    target_add_resources(${TARGET_NAME} ${ARG_RESOURCES})
endfunction()

# ──────────────────────────────────
# 子工程（每新增一个例子在此加一行）
# ──────────────────────────────────
add_subdirectory(src/01_hello_window)
add_subdirectory(src/02_hello_triangle)
add_subdirectory(src/03_shaders)
add_subdirectory(src/04_textures)
