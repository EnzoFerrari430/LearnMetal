cmake_minimum_required(VERSION 3.20)
project(LearnMetal LANGUAGES CXX Swift)

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
# 辅助函数：快速创建 Metal 可执行文件
# ──────────────────────────────────
function(add_metal_executable TARGET_NAME)
    add_executable(${TARGET_NAME} ${ARGN})
    if(PLATFORM_IOS)
        set_target_properties(${TARGET_NAME} PROPERTIES
            MACOSX_BUNDLE TRUE
            MACOSX_BUNDLE_GUI_IDENTIFIER "com.learnmetal.01helloWindow"
            XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.learnmetal.01helloWindow"
            XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic"
            XCODE_ATTRIBUTE_DEVELOPMENT_TEAM ""
        )
        set_target_properties(${TARGET_NAME} PROPERTIES
            GENERATED_INFO_PLIST_FILE ""
        )
    endif()
    target_link_libraries(${TARGET_NAME} PRIVATE ${PLATFORM_LIBS})
    # 使用 @main 时需要此设置
    target_compile_options(${TARGET_NAME} PRIVATE "-parse-as-library")
    # 禁用自动生成 Info.plist
    set_target_properties(${TARGET_NAME} PROPERTIES
        XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE "NO"
        XCODE_ATTRIBUTE_INFOPLIST_FILE "${CMAKE_SOURCE_DIR}/Info.plist"
    )
endfunction()

# ──────────────────────────────────
# 子工程（每新增一个例子在此加一行）
# ──────────────────────────────────
add_subdirectory(src/01_hello_window)
add_subdirectory(src/02_hello_triangle)
