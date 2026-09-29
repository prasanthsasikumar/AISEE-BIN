cmake_minimum_required(VERSION 3.22.1)
project("aiseebin")

set(CMAKE_CXX_STANDARD 17)

add_library(aiseebin SHARED aiseebin.cpp)

# Realtek's player, for the decoded-frame callback (SmartWear guide §5.3).
find_package(rtk-audioconnect-smartwear REQUIRED CONFIG)
find_library(log-lib log)

target_link_libraries(aiseebin
        rtk-audioconnect-smartwear::rtk-smart-wear
        ${log-lib}
        dl)
