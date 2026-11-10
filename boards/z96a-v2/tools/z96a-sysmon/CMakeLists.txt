cmake_minimum_required(VERSION 3.16)
project(z96a-sysmon LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Widgets)

add_library(z96a-sysmon MODULE
    z96a-sysmon.cpp
    z96a-sysmon.h
)

target_include_directories(z96a-sysmon PRIVATE /usr/include/lxqt)
target_link_libraries(z96a-sysmon PRIVATE Qt6::Widgets)

set_target_properties(z96a-sysmon PROPERTIES
    PREFIX "lib"
    OUTPUT_NAME "z96a-sysmon"
)
