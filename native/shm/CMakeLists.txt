cmake_minimum_required(VERSION 3.20)
project(hayalet_shm LANGUAGES CXX)

add_library(hayalet_shm SHARED hayalet_shm.cpp)
target_compile_features(hayalet_shm PRIVATE cxx_std_20)
target_compile_definitions(hayalet_shm PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
