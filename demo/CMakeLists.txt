cmake_minimum_required(VERSION 3.23.1 FATAL_ERROR)

project(demo LANGUAGES CXX)

# define location of faiss pre-build lib
list(APPEND CMAKE_PREFIX_PATH "${PROJECT_SOURCE_DIR}/../dist")
find_package(faiss REQUIRED)
find_package(OpenMP REQUIRED)

set(CMAKE_CXX_STANDARD 11)

add_executable(demo EXCLUDE_FROM_ALL demo_ivfpq_indexing.cpp)
target_link_libraries(demo PRIVATE faiss)

add_executable(test_cosine EXCLUDE_FROM_ALL test_cosine.cpp)
target_link_libraries(test_cosine PRIVATE faiss)

add_executable(bench_cosine EXCLUDE_FROM_ALL bench_cosine.cpp)
target_link_libraries(bench_cosine PRIVATE faiss)
