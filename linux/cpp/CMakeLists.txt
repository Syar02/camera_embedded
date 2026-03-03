cmake_minimum_required(VERSION 3.10)
project(camera_driver)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find OpenCV
find_package(OpenCV REQUIRED)
if(OpenCV_FOUND)
    message(STATUS "OpenCV version: ${OpenCV_VERSION}")
    message(STATUS "OpenCV include: ${OpenCV_INCLUDE_DIRS}")
    message(STATUS "OpenCV libraries: ${OpenCV_LIBS}")
else()
    message(FATAL_ERROR "OpenCV not found. Please install libopencv-dev")
endif()

# Buat shared library
add_library(camera_driver SHARED 
    camera_driver.cpp
)

# Set properti library
set_target_properties(camera_driver PROPERTIES
    PREFIX "lib"
    SUFFIX ".so"
    OUTPUT_NAME "camera_driver"
    POSITION_INDEPENDENT_CODE ON
)

# Include directories
target_include_directories(camera_driver PRIVATE ${OpenCV_INCLUDE_DIRS})

# Link libraries
target_link_libraries(camera_driver 
    PRIVATE 
    pthread
    ${OpenCV_LIBS}
)

# Compiler flags
target_compile_options(camera_driver PRIVATE -Wall -Wextra -pthread)